FROM rockylinux:9.3.20231119

# 安装 NTP 服务（chrony）和相关工具
RUN yum install -y \
    chrony \
    net-tools \
    psmisc \
    procps-ng \
    vim \
    man \
    iproute \
    iputils \
    tcpdump && \
    yum clean all

# 暴露 NTP 端口
# 123/udp: NTP 服务端口
EXPOSE 123/udp

# 启动 chronyd 服务
CMD ["/usr/sbin/chronyd", "-d", "-x"]
