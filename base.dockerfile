FROM rockylinux:9.3.20231119


# 配置阿里云 EPEL 源
RUN cat > /etc/yum.repos.d/epel.repo <<'EOF'
[epel]
name=Extra Packages for Enterprise Linux 9 - $basearch
baseurl=https://mirrors.aliyun.com/epel/9/Everything/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://mirrors.aliyun.com/epel/RPM-GPG-KEY-EPEL-9
EOF

# 安装公共工具（所有项目通用）
# RockyLinux: wget net-tools      iproute     iputils     tcpdump     nmap-ncat psmisc     lsof     procps-ng vim     man  tree     file  jq
# Ubuntu: wget net-tools      iproute2     iputils-ping     tcpdump     netcat-openbsd psmisc     lsof     procps vim     man-db  tree     file  jq

RUN yum install -y  \
    # 网络工具
    net-tools  \
    iproute \
    iputils \
    tcpdump \
    wget \
    nmap-ncat \
    # 进程管理工具
    psmisc \
    lsof \
    procps-ng \
    # 编辑器和文档
    vim \
    man \
    # 文件系统工具
    tree \
    file \
    # 数据处理工具
    jq && \
    yum clean all

# 设置工作目录
WORKDIR /data

# 默认保持容器运行
CMD ["tail", "-f", "/dev/null"]
