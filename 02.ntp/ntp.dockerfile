# 使用公共基础镜像
FROM docker-man-base:latest

# 安装 NTP 服务特定软件包
RUN yum install -y \
    chrony && \
    yum clean all

# 暴露 NTP 端口
# 123/udp: NTP 服务端口
EXPOSE 123/udp

# 启动 chronyd 服务
CMD ["/usr/sbin/chronyd", "-d", "-x"]
