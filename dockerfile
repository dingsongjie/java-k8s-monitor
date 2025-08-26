FROM maven:3.9-eclipse-temurin-21-alpine

#RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak; \
#    sed -i 's#http://archive.ubuntu.com/#http://mirrors.aliyun.com/#' /etc/apt/sources.list; \
#    sed -i 's#http://ports.ubuntu.com/#http://mirrors.aliyun.com/#' /etc/apt/sources.list; \
#    sed -i 's#http://security.ubuntu.com/#http://mirrors.aliyun.com/#' /etc/apt/sources.list; \
#    apt-get update;

#RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates telnet unzip && \
#    rm -rf /var/lib/apt/lists/*

RUN apk add --no-cache curl busybox-extras unzip

WORKDIR /app

RUN mkdir -p /root/.arthas/lib \
 && wget -O /root/.arthas/lib/arthas-boot.jar https://arthas.aliyun.com/arthas-boot.jar


RUN curl -L https://arthas.aliyun.com/install.sh | sh


COPY monitor.sh monitor.sh
RUN chmod +x monitor.sh
CMD ["/bin/bash", "-c", "./monitor.sh"]

