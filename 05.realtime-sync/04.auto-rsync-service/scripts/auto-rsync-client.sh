#!/bin/bash
# Rsync Daemon 客户端自动同步脚本（with inotify）

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

# 环境变量
RSYNC_SERVER=${RSYNC_SERVER:-10.0.5.31}
RSYNC_MODULE=${RSYNC_MODULE:-backup}
RSYNC_USER=${RSYNC_USER:-rsyncuser}
SOURCE_DIR=${SOURCE_DIR:-/data/source}
SYNC_INTERVAL=${SYNC_INTERVAL:-5}
PASSWORD_FILE="/etc/rsync/rsync.pass"
MAX_RETRIES=30
RETRY_COUNT=0

log "=========================================="
log "Rsync Daemon 客户端自动同步"
log "=========================================="
log "服务器地址: ${RSYNC_SERVER}"
log "模块名称: ${RSYNC_MODULE}"
log "用户名: ${RSYNC_USER}"
log "源目录: ${SOURCE_DIR}"
log "同步间隔: ${SYNC_INTERVAL}秒"
log "=========================================="
echo ""

# 1. 等待并读取密码文件（从共享卷）
log "步骤 1/5: 等待服务端共享密码..."
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ -f /shared-config/rsync.pass ]; then
        mkdir -p /etc/rsync
        cp /shared-config/rsync.pass ${PASSWORD_FILE}
        chmod 600 ${PASSWORD_FILE}
        log_success "密码文件获取成功"
        break
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    log_warning "等待密码文件... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_error "无法获取密码文件，退出"
    exit 1
fi

# 2. 等待 rsync daemon 服务启动
log "步骤 2/5: 等待 rsync daemon 服务..."
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if nc -z ${RSYNC_SERVER} 873 2>/dev/null; then
        log_success "rsync daemon 服务已就绪"
        sleep 2  # 额外等待 2 秒确保服务完全启动
        break
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    log_warning "等待 rsync daemon... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_error "无法连接到 rsync daemon，退出"
    exit 1
fi

# 3. 测试连接
log "步骤 3/5: 测试 rsync 连接..."
if rsync --password-file=${PASSWORD_FILE} rsync://${RSYNC_USER}@${RSYNC_SERVER}/${RSYNC_MODULE}/ >/dev/null 2>&1; then
    log_success "rsync 连接测试成功"
else
    log_error "rsync 连接失败"
    exit 1
fi

# 4. 创建测试数据（首次）
log "步骤 4/5: 准备源数据..."
if [ ! -f ${SOURCE_DIR}/auto-client-test.txt ]; then
    mkdir -p ${SOURCE_DIR}
    cat > ${SOURCE_DIR}/auto-client-test.txt <<EOF
自动同步测试文件
创建时间: $(date)
服务器: ${RSYNC_SERVER}
模块: ${RSYNC_MODULE}
EOF
    log_success "测试数据创建完成"
else
    log "源数据已存在，跳过创建"
fi

# 5. 执行同步函数
do_sync() {
    local start_time=$(date +%s)

    log "开始同步 ${SOURCE_DIR}/ → rsync://${RSYNC_USER}@${RSYNC_SERVER}/${RSYNC_MODULE}/"

    if rsync -avz --delete --password-file=${PASSWORD_FILE} \
        ${SOURCE_DIR}/ rsync://${RSYNC_USER}@${RSYNC_SERVER}/${RSYNC_MODULE}/ 2>&1 | \
        grep -v "^$" | while read line; do
            if echo "$line" | grep -q "sending\|receiving\|total size"; then
                log "$line"
            fi
        done; then

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "同步完成（耗时 ${duration}s）"
        return 0
    else
        log_error "同步失败"
        return 1
    fi
}

# 6. 启动同步循环
log "步骤 5/5: 启动自动同步循环..."
echo ""
log_success "自动同步已启动！"
log "监控目录: ${SOURCE_DIR}"
log "同步间隔: ${SYNC_INTERVAL}秒"
log "按 Ctrl+C 停止"
echo ""

# 首次立即同步
do_sync

# 使用 inotify 监控文件变化
if command -v inotifywait >/dev/null 2>&1; then
    log "使用 inotify 监控文件变化..."

    inotifywait -m -r -e modify,create,delete,move ${SOURCE_DIR} --format '%w%f %e' | while read file event; do
        log "检测到变化: $file ($event)"
        sleep 1  # 防止频繁触发
        do_sync
    done
else
    log_warning "inotify 不可用，使用定时同步..."

    while true; do
        sleep ${SYNC_INTERVAL}
        do_sync
    done
fi
