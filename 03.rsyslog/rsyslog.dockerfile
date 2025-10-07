FROM rockylinux:9.3.20231119
 
RUN yum install -y  \
    net-tools \
    psmisc lsof \
    jq \
    procps-ng \
    vim \
    man \
    iproute \
    iputils \
    tcpdump \
    rsyslog-doc \
    rsyslog \
    systemd && \
    yum clean all

 
# 暴露 syslog 端口
EXPOSE 514/udp 514/tcp

CMD ["rsyslogd", "-n", "-f", "/etc/rsyslog.conf"]

 