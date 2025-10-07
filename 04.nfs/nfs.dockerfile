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
    rpcbind \
    nfs-utils && \
    yum clean all

# 创建 NFS 共享目录
RUN mkdir -p /data/share && \
    chmod 755 /data/share


# 暴露 NFS 相关端口
# 2049: NFS 主端口
# 111: RPC portmapper (rpcbind)
# 20048: mountd
EXPOSE 2049/tcp 2049/udp 111/tcp 111/udp 20048/tcp 20048/udp

CMD ["bash", "-c", "rpcbind && rpc.statd && sleep 1 && mount -t nfsd nfsd /proc/fs/nfsd 2>/dev/null || true && rpc.nfsd && rpc.mountd && sleep 1 && exportfs -arv && tail -f /dev/null"]
