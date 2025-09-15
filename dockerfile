FROM eclipse-temurin:21-jdk

#RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak; \
#    sed -i 's#http://archive.ubuntu.com/#http://mirrors.aliyun.com/#' /etc/apt/sources.list; \
#    sed -i 's#http://ports.ubuntu.com/#http://mirrors.aliyun.com/#' /etc/apt/sources.list; \
#    sed -i 's#http://security.ubuntu.com/#http://mirrors.aliyun.com/#' /etc/apt/sources.list; \
#    apt-get update;

#RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates telnet unzip && \
#    rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        unzip \
        bash \
        busybox && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app


# 安装 arthas lib
RUN  echo '安装 arthas lib 开始..................'
RUN  mkdir -p /arthas/lib/4.0.5 && \
    curl -L https://repo1.maven.org/maven2/com/taobao/arthas/arthas-packaging/4.0.5/arthas-packaging-4.0.5-bin.zip \
    -o /arthas/lib/4.0.5/arthas-packaging-4.0.5-bin.zip && \
    unzip /arthas/lib/4.0.5/arthas-packaging-4.0.5-bin.zip -d /arthas/lib/4.0.5/arthas && \
    rm /arthas/lib/4.0.5/arthas-packaging-4.0.5-bin.zip
RUN echo '安装 arthas lib 完成..................'




RUN curl -L "https://github.com/async-profiler/async-profiler/releases/download/v4.1/async-profiler-4.1-linux-x64.tar.gz" -o "async-profiler-4.1-linux-x64.tar.gz"

RUN  tar -xzf "async-profiler-4.1-linux-x64.tar.gz" -C "./" --strip-components=1 -c ./sync-profiler
RUN rm -f async-profiler-4.1-linux-x64.tar.gz

RUN chmod +x /app/bin/asprof
RUN chmod +x /app/bin/jfrconv
RUN export ASYNC_PROFILER_HOME=/opt/async-profiler
RUN curl -L https://arthas.aliyun.com/install.sh | sh


COPY monitor.sh monitor.sh
RUN chmod +x monitor.sh
CMD ["/bin/bash", "-c", "./monitor.sh"]