#!/bin/bash
# Rsync Daemon 服务端自动配置脚本

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ✓ $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ✗ $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ⚠ $1"
}

# 环境变量默认值
RSYNC_USER=${RSYNC_USER:-rsyncuser}
RSYNC_PASSWORD=${RSYNC_PASSWORD:-rsyncpass123}
RSYNC_MODULE=${RSYNC_MODULE:-backup}
BACKUP_PATH=${BACKUP_PATH:-/data/backup}

log "=========================================="
log "Rsync Daemon 服务端自动配置"
log "=========================================="
log "模块名称: ${RSYNC_MODULE}"
log "用户名: ${RSYNC_USER}"
log "备份路径: ${BACKUP_PATH}"
log "=========================================="
echo ""

# 1. 创建配置目录
log "步骤 1/6: 创建配置目录..."
mkdir -p /etc/rsync
mkdir -p ${BACKUP_PATH}
log_success "配置目录创建完成"

# 2. 创建 rsyncd.conf 配置文件
log "步骤 2/6: 创建 rsyncd.conf 配置文件..."
cat > /etc/rsync/rsyncd.conf <<EOF
# Rsync Daemon 自动配置文件
# 生成时间: $(date)

# ==================== 全局配置 ====================

# 运行用户和组
uid = root
gid = root

# 是否使用 chroot
use chroot = no

# 日志文件
log file = /var/log/rsyncd.log

# PID 文件
pid file = /var/run/rsyncd.pid

# 锁文件
lock file = /var/run/rsync.lock

# 监听端口
port = 873

# 监听地址
address = 0.0.0.0

# 最大连接数
max connections = 10

# 超时时间（秒）
timeout = 600

# 欢迎信息文件
motd file = /etc/rsync/rsyncd.motd

# ==================== 模块定义 ====================

[${RSYNC_MODULE}]
    comment = Auto-configured Backup Module
    path = ${BACKUP_PATH}
    read only = no
    list = yes
    hosts allow = 10.0.5.0/24
    hosts deny = *
    auth users = ${RSYNC_USER}
    secrets file = /etc/rsync/rsyncd.secrets
    ignore errors = no
    transfer logging = yes
    log format = %t %a %m %f %b
    dont compress = *.gz *.tgz *.zip *.z *.rpm *.deb *.bz2
EOF

log_success "rsyncd.conf 配置完成"

# 3. 创建密码文件
log "步骤 3/6: 创建密码文件..."
echo "${RSYNC_USER}:${RSYNC_PASSWORD}" > /etc/rsync/rsyncd.secrets
chmod 600 /etc/rsync/rsyncd.secrets
log_success "密码文件创建完成（权限已设置为 600）"

# 4. 共享密码到客户端（通过共享卷）
log "步骤 4/6: 共享密码到客户端..."
echo "${RSYNC_PASSWORD}" > /shared-config/rsync.pass
chmod 644 /shared-config/rsync.pass
log_success "密码已共享到 /shared-config/rsync.pass"

# 5. 创建欢迎信息
log "步骤 5/6: 创建欢迎信息..."
cat > /etc/rsync/rsyncd.motd <<EOF
========================================
Rsync Daemon 自动配置服务器
模块: ${RSYNC_MODULE}
启动时间: $(date)
========================================
EOF

log_success "欢迎信息创建完成"

# 6. 启动 rsync daemon
log "步骤 6/6: 启动 rsync daemon..."
echo ""
log_success "配置完成！rsync daemon 启动中..."
log "监听端口: 873"
log "模块名称: ${RSYNC_MODULE}"
log "认证用户: ${RSYNC_USER}"
echo ""

# 前台运行 rsync daemon（Docker 容器中推荐）
exec rsync --daemon --no-detach --config=/etc/rsync/rsyncd.conf --log-file=/dev/stdout
