#!/bin/bash
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO $(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log "=========================================="
log "SSH 服务器 - 自动配置启动"
log "=========================================="

# 1. 生成 SSH 主机密钥
if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
    log "生成 SSH 主机密钥..."
    ssh-keygen -A
    log "SSH 主机密钥生成完成 ✓"
else
    log "SSH 主机密钥已存在，跳过生成"
fi

# 2. 配置 SSH 允许 root 登录
log "配置 SSH 服务..."
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
log "SSH 配置完成 ✓"

# 3. 创建 .ssh 目录
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 4. 等待并读取源端公钥（从共享卷）
log "等待源端公钥..."
RETRY_COUNT=0
MAX_RETRIES=30

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ -f /shared-keys/id_rsa.pub ]; then
        log "发现源端公钥，配置授权..."
        cat /shared-keys/id_rsa.pub > /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        log "SSH 免密登录配置完成 ✓"
        break
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -eq 1 ]; then
        info "等待源端生成公钥... (${RETRY_COUNT}/${MAX_RETRIES})"
    else
        sleep 2
    fi
done

if [ ! -f /root/.ssh/authorized_keys ]; then
    warn "未能获取源端公钥，SSH 免密登录可能无法工作"
fi

# 5. 启动 SSH 服务
log "启动 SSH 服务..."
/usr/sbin/sshd -D &
SSHD_PID=$!

log "SSH 服务已启动 ✓"
log "  PID: $SSHD_PID"
log "  端口: 22"
log "  主机名: $(hostname)"
log "  IP 地址: $(hostname -i)"

# 6. 保持容器运行并监控公钥变化
log "=========================================="
log "SSH 服务器就绪，等待连接..."
log "=========================================="
log ""

# 循环监控公钥变化（实现热更新）
while kill -0 $SSHD_PID 2>/dev/null; do
    sleep 10

    # 如果公钥更新，自动重新配置
    if [ -f /shared-keys/id_rsa.pub ] && [ -f /root/.ssh/authorized_keys ]; then
        if ! diff -q /shared-keys/id_rsa.pub /root/.ssh/authorized_keys >/dev/null 2>&1; then
            info "检测到公钥更新，重新配置..."
            cat /shared-keys/id_rsa.pub > /root/.ssh/authorized_keys
            chmod 600 /root/.ssh/authorized_keys
            log "SSH 公钥已更新 ✓"
        fi
    fi
done

error "SSH 服务异常退出"
exit 1
