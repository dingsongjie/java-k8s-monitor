FROM eclipse-temurin:21-jdk

#RUN cp /etc/apt/sources.list /etc/apt/sources.list.bak; \
#    sed -i 's#http://archive.ubuntu.com/#http://mirrors.aliyun.com/#' /etc/apt/sources.list; \
#    sed -i 's#http://ports.ubuntu.com/#http://mirrors.aliyun.com/#' /etc/apt/sources.list; \
#    sed -i 's#http://security.ubuntu.com/#http://mirrors.aliyun.com/#' /etc/apt/sources.list; \
#    apt-get update;

#RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates telnet unzip && \
#    rm -rf /var/lib/apt/lists/*

RUN apk add --no-cache curl busybox-extras unzip bash

WORKDIR /app




RUN curl -L "https://release-assets.githubusercontent.com/github-production-release-asset/56894212/1398c903-9276-4f3e-9efe-a8afc00ffe65?sp=r&sv=2018-11-09&sr=b&spr=https&se=2025-09-02T10%3A34%3A07Z&rscd=attachment%3B+filename%3Dasync-profiler-4.1-linux-x64.tar.gz&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2025-09-02T09%3A33%3A34Z&ske=2025-09-02T10%3A34%3A07Z&sks=b&skv=2018-11-09&sig=f5UBcjLmmDuKrUykN3Dshtcn1QKRX12M5Lnh0MrUP6c%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc1NjgwNzUzNywibmJmIjoxNzU2ODA3MjM3LCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.d9Pwz4Yi2_oIu7X2cqc0GX0QPAmFhKBHmCjDMsycgpU&response-content-disposition=attachment%3B%20filename%3Dasync-profiler-4.1-linux-x64.tar.gz&response-content-type=application%2Foctet-stream" -o "async-profiler-4.1-linux-x64.tar.gz"

RUN  tar -xzf "async-profiler-4.1-linux-x64.tar.gz" -C "./" --strip-components=1
RUN rm -f async-profiler-4.1-linux-x64.tar.gz

RUN chmod +x /app/bin/asprof
RUN chmod +x /app/bin/jfrconv
RUN export ASYNC_PROFILER_HOME=/opt/async-profiler
RUN curl -L https://arthas.aliyun.com/install.sh | sh


COPY monitor.sh monitor.sh
RUN chmod +x monitor.sh
CMD ["/bin/bash", "-c", "./monitor.sh"]

