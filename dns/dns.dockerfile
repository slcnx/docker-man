FROM rockylinux:9.3.20231119

# 安装DNS服务和相关工具
RUN yum install -y \
    bind \
    bind-utils \
    net-tools \
    psmisc \
    procps-ng \
    vim \
    man \
    iproute \
    file \
    nscd && \
    yum clean all

# 创建日志目录并设置权限
RUN install -dv -o named -g named /var/log/named  

# 生成rndc密钥
RUN /usr/libexec/generate-rndc-key.sh

# 配置rndc允许远程访问
RUN sed -i '/^options {/i include "/etc/rndc.key";' /etc/named.conf && \
    sed -i 's/inet 127.0.0.1 port 953/inet * port 953/' /etc/named.conf || \
    echo 'controls { inet * port 953 allow { any; } keys { "rndc-key"; }; };' >> /etc/named.conf

# 暴露DNS端口
EXPOSE 53/tcp 53/udp 953/tcp

# 启动DNS服务
CMD ["/usr/sbin/named", "-u", "named", "-c", "/etc/named.conf", "-g","-4"]
