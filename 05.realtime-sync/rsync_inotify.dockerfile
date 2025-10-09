# 使用公共基础镜像
FROM docker-man-base:latest


# 安装 EPEL 和 Rsync 同步服务特定软件包
RUN yum install -y  \
    rsync \
    inotify-tools \
    # source
    openssh-clients \
    # backup
    openssh-server \
    && \
    yum clean all

 
# 暴露 rsync 守护进程端口（可选）
# 873: rsync daemon
EXPOSE 873/tcp

CMD ["tail", "-f", "/dev/null"]
