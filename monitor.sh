#!/bin/bash

# ========== 默认参数 ==========
CPU_THRESHOLD_DEFAULT=65        # CPU 超过 65% (mbean 返回 0~1)
CPU_DURATION_DEFAULT=5            # 持续秒数
MEM_THRESHOLD_DEFAULT=95        # 内存超过 95%
PROFILER_DURATION_DEFAULT=10      # profiler 持续秒数
COOLDOWN_DEFAULT=900              # 冷却时间（秒），15 分钟
STARTUP_GRACE_PERIOD=120     #开始运行的等待时间，等待主容器运行2分钟后再进行

# ========== 从外部传入参数（优先级：命令行参数 > 环境变量 > 默认值）==========
CPU_THRESHOLD=${1:-${CPU_THRESHOLD:-$CPU_THRESHOLD_DEFAULT}}
CPU_DURATION=${2:-${CPU_DURATION:-$CPU_DURATION_DEFAULT}}
MEM_THRESHOLD=${3:-${MEM_THRESHOLD:-$MEM_THRESHOLD_DEFAULT}}
PROFILER_DURATION=${4:-${PROFILER_DURATION:-$PROFILER_DURATION_DEFAULT}}
COOLDOWN=${5:-${COOLDOWN:-$COOLDOWN_DEFAULT}}

echo "CPU_THRESHOLD=$CPU_THRESHOLD, CPU_DURATION=$CPU_DURATION, MEM_THRESHOLD=$MEM_THRESHOLD, PROFILER_DURATION=$PROFILER_DURATION, COOLDOWN=$COOLDOWN, STARTUP_GRACE_PERIOD=$STARTUP_GRACE_PERIOD"   

# 安装 arthas lib
echo '安装 arthas lib 开始..................'
mkdir -p /arthas/lib/4.0.5 && \
    curl -L https://repo1.maven.org/maven2/com/taobao/arthas/arthas-packaging/4.0.5/arthas-packaging-4.0.5-bin.zip \
    -o /arthas/lib/4.0.5/arthas-packaging-4.0.5-bin.zip && \
    unzip /arthas/lib/4.0.5/arthas-packaging-4.0.5-bin.zip -d /arthas/lib/4.0.5/arthas && \
    rm /arthas/lib/4.0.5/arthas-packaging-4.0.5-bin.zip
echo '安装 arthas lib 完成..................'

CPU_COOLDOWN_FILE="/tmp/cpu_profiler_cooldown"
MEM_COOLDOWN_FILE="/tmp/mem_dump_cooldown"

# 获取 Arthas 执行命令路径
ARTHAS_BIN="./as.sh --arthas-home /arthas/lib/4.0.5/arthas"

#--arthas-home /arthas/lib/4.0.5/arthas


get_container_start_time() {
    local pid=$1
    local start_ticks=$(awk '{print $22}' /proc/$pid/stat)
    local hertz=$(getconf CLK_TCK)
    local boot_time=$(awk '/btime/ {print $2}' /proc/stat)
    # 用浮点计算避免舍入为0
    local start_time=$(awk -v b="$boot_time" -v t="$start_ticks" -v h="$hertz" 'BEGIN {printf "%.0f", b + t/h}')
    echo "$start_time"
}

get_process_memory_percent() {
    local pid=$1
    CGROUP_ROOT="/cgroup_sidecar"
    # 获取进程 cgroup 路径
    CGROUP_PATH=$(grep memory /proc/$pid/cgroup | cut -d: -f3)
    # 拼接容器挂载路径
    FULL_PATH="$CGROUP_ROOT/memory$CGROUP_PATH"
    # 判断 cgroup 版本并读取内存使用/限制
    if [ -f "$FULL_PATH/memory.usage_in_bytes" ]; then
      # cgroup v1
      MEM_USAGE=$(cat "$FULL_PATH/memory.usage_in_bytes")
      MEM_LIMIT=$(cat "$FULL_PATH/memory.limit_in_bytes")
    elif [ -f "$FULL_PATH/memory.current" ]; then
      # cgroup v2
      MEM_USAGE=$(cat "$FULL_PATH/memory.current")
      MEM_LIMIT=$(cat "$FULL_PATH/memory.max")
    else
      echo "Error: Cannot find memory stats for PID $pid"
      exit 1
    fi

    # 计算使用百分比
    MEM_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($MEM_USAGE/$MEM_LIMIT)*100}")

    echo "$MEM_PERCENT"
}

# 获取进程占容器 CPU 限额百分比
# 参数：
#   $1 - PID
#   $2 - 采样间隔秒（可选，默认1秒）
get_process_cpu_percent() {
    local pid=$1
    local interval=${2:-1}
    CGROUP_ROOT="/cgroup_sidecar"
    CGROUP_PATH=$(grep cpu /proc/$pid/cgroup | cut -d: -f3 | head -n 1)
    FULL_PATH_V1="$CGROUP_ROOT/cpu$CGROUP_PATH"
    FULL_PATH_V2="$CGROUP_ROOT$CGROUP_PATH"

    local cpu_usage_1 cpu_usage_2
    local timestamp_1 timestamp_2
    local cpu_limit_cores=1

    if [ -f "$FULL_PATH_V1/cpu.cfs_quota_us" ] && [ -f "$FULL_PATH_V1/cpu.cfs_period_us" ]; then
        # cgroup v1
        quota=$(cat "$FULL_PATH_V1/cpu.cfs_quota_us")
        period=$(cat "$FULL_PATH_V1/cpu.cfs_period_us")
        if [[ "$quota" -le 0 ]]; then
            cpu_limit_cores=$(nproc)   # quota=-1表示不限，使用全部核
        else
            cpu_limit_cores=$(awk "BEGIN {printf \"%.2f\", $quota/$period}")
        fi

        cpu_usage_1=$(cat "$FULL_PATH_V1/cpuacct.usage")
        timestamp_1=$(date +%s%N)
        sleep $interval
        cpu_usage_2=$(cat "$FULL_PATH_V1/cpuacct.usage")
        timestamp_2=$(date +%s%N)

    elif [ -f "$FULL_PATH_V2/cpu.max" ]; then
        # cgroup v2
        read quota period < "$FULL_PATH_V2/cpu.max"
        if [[ "$quota" == "max" ]]; then
            cpu_limit_cores=$(nproc)
        else
            cpu_limit_cores=$(awk "BEGIN {printf \"%.2f\", $quota/$period}")
        fi

        cpu_usage_1=$(awk '/usage_usec/ {print $2*1000}' "$FULL_PATH_V2/cpu.stat")
        timestamp_1=$(date +%s%N)
        sleep $interval
        cpu_usage_2=$(awk '/usage_usec/ {print $2*1000}' "$FULL_PATH_V2/cpu.stat")
        timestamp_2=$(date +%s%N)
    else
        echo "Error: Cannot find CPU stats for PID $pid"
        return 1
    fi

    local delta_usage=$((cpu_usage_2 - cpu_usage_1))
    local delta_time=$((timestamp_2 - timestamp_1))

    # CPU 使用率百分比
    cpu_percent=$(awk -v u=$delta_usage -v t=$delta_time -v c=$cpu_limit_cores \
                    'BEGIN {printf "%.2f", (u/t)/c*100}')
    echo "$cpu_percent"
}


function cooldown_passed() {
  local file=$1
  local now=$(date +%s)
  if [[ ! -f $file ]]; then
    return 0
  fi
  local last=$(cat $file)
  local diff=$(( now - last ))
  if (( diff >= COOLDOWN )); then
    return 0
  else
    return 1
  fi
}

function start_profiler() {
  echo "$(date) CPU超过阈值，启动 Arthas profiler，持续${PROFILER_DURATION}s"
  $ARTHAS_BIN  $PID -c "profiler start --duration ${PROFILER_DURATION} -f /dumpfile/profile-$(date +%s).html cpu"
  echo "创建profiler成功"
  echo $(date +%s) > $CPU_COOLDOWN_FILE
}

function start_heap_dump() {
  local dump_file="/dumpfile/heapdump-$(date +%s).hprof"
  echo "$(date) 内存超过阈值，生成 heap dump: $dump_file"
  $ARTHAS_BIN -p $PID -c "dumpheap $dump_file"
  echo $(date +%s) > $MEM_COOLDOWN_FILE
}

function check_cpu() {
  local pid=$1  
  local count=0
  for ((i=0; i<CPU_DURATION; i++)); do
    local cpu_load=$(get_process_cpu_percent "$pid")
    cpu_load=${cpu_load:-0}
    # echo "CPU load: $cpu_load"
    # 乘100方便对比
    cpu_int=$(awk "BEGIN {print int($cpu_load)}")
    threshold_int=$(awk "BEGIN {print int($CPU_THRESHOLD)}")
    if (( cpu_int >= threshold_int )); then
      ((count++))
    fi
  done
  if (( count == CPU_DURATION )); then
    return 0
  else
    return 1
  fi
}

function check_mem() {
  local pid=$1
  local mem_load=$(get_process_memory_percent "$pid" 1)
  mem_load=${mem_load:-0}
  mem_int=$(awk "BEGIN {print int($mem_load)}")
  threshold_int=$(awk "BEGIN {print int($MEM_THRESHOLD)}")
  # echo "Heap Usage: $mem_load"
  if (( mem_int >= threshold_int )); then
    return 0
  else
    return 1
  fi
}

while true; do

    #获取第一个 java 进程 PID
    pid=$(pgrep -f java | head -n 1)
    if [ -z "$pid" ]; then
        echo "未找到 java 进程"
        exit 1
    fi
    container_start_time=$(get_container_start_time "$pid")
    current_time=$(date +%s)
    echo "current_time=$current_time"
    elapsed=$((current_time - container_start_time))    
    echo "Monitoring Java process PID: $pid"
 
    if (( elapsed >= STARTUP_GRACE_PERIOD )); then
        if cooldown_passed $CPU_COOLDOWN_FILE && check_cpu "$pid"; then
            start_profiler
        fi

        if cooldown_passed $MEM_COOLDOWN_FILE && check_mem "$pid"; then
            start_heap_dump
        fi
    else  
        echo "容器启动保护期内，跳过检测..."
        sleep 10
    fi    
done