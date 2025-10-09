# 使用公共基础镜像
FROM docker-man-base:latest

# 安装 Rsyslog 服务特定软件包
RUN yum install -y  \
    rsyslog \
    rsyslog-doc \
    systemd && \
    yum clean all

 
# 暴露 syslog 端口
EXPOSE 514/udp 514/tcp

CMD ["rsyslogd", "-n", "-f", "/etc/rsyslog.conf"]

 