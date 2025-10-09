#!/bin/bash
set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 从环境变量读取配置（带默认值）
SOURCE_DIR="${SOURCE_DIR:-/data/source/}"
DEST_HOST="${DEST_HOST:-rsync-backup}"
DEST_DIR="${DEST_DIR:-/data/backup/}"
RSYNC_OPTS="${RSYNC_OPTS:--avz --delete}"
SSH_OPTS="${SSH_OPTS:--o StrictHostKeyChecking=no}"
SYNC_INTERVAL="${SYNC_INTERVAL:-5}"
MAX_RETRIES="${MAX_RETRIES:-10}"

# 日志函数
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

# 生成 SSH 密钥并共享
setup_ssh_keys() {
    log "=========================================="
    log "配置 SSH 密钥（自动化）"
    log "=========================================="

    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    mkdir -p /shared-keys

    # 生成 SSH 密钥对
    if [ ! -f /root/.ssh/id_rsa ]; then
        log "生成 SSH 密钥对..."
        ssh-keygen -t rsa -b 2048 -N "" -f /root/.ssh/id_rsa -q
        log "SSH 密钥生成完成 ✓"
    else
        log "SSH 密钥已存在，跳过生成"
    fi

    # 将公钥复制到共享卷（供备份端读取）
    log "共享公钥到备份服务器..."
    cp /root/.ssh/id_rsa.pub /shared-keys/id_rsa.pub
    log "公钥已共享 ✓"
}

# 等待 SSH 服务就绪
wait_for_ssh() {
    local retries=0
    log "=========================================="
    log "等待 SSH 服务就绪"
    log "=========================================="
    log "目标主机: ${DEST_HOST}:22"

    while [ $retries -lt $MAX_RETRIES ]; do
        if nc -z ${DEST_HOST} 22 2>/dev/null; then
            log "SSH 服务已就绪 ✓"
            sleep 3  # 额外等待服务完全启动和密钥配置
            return 0
        fi

        retries=$((retries + 1))
        info "等待 SSH 服务... (${retries}/${MAX_RETRIES})"
        sleep 5
    done

    error "SSH 服务未就绪，超时退出"
    return 1
}

# 测试 SSH 连接
test_ssh_connection() {
    log "=========================================="
    log "测试 SSH 连接"
    log "=========================================="

    local retries=0
    local max_test_retries=5

    while [ $retries -lt $max_test_retries ]; do
        if ssh ${SSH_OPTS} root@${DEST_HOST} "echo 'SSH connection successful'" >/dev/null 2>&1; then
            log "SSH 免密登录测试成功 ✓"
            return 0
        fi

        retries=$((retries + 1))
        warn "SSH 连接测试失败，重试... (${retries}/${max_test_retries})"
        sleep 5
    done

    error "SSH 连接测试失败"
    error "请检查："
    error "  1. 备份服务器是否正在运行"
    error "  2. SSH 服务是否已启动"
    error "  3. 公钥是否正确配置"
    return 1
}

# 同步函数
do_sync() {
    local start_time=$(date +%s)

    rsync ${RSYNC_OPTS} -e "ssh ${SSH_OPTS}" ${SOURCE_DIR} root@${DEST_HOST}:${DEST_DIR}

    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 0 ]; then
        log "同步成功 (耗时: ${duration}秒) ✓"
        return 0
    else
        error "同步失败 (退出码: $exit_code)"
        return $exit_code
    fi
}

# 主程序
main() {
    log "=========================================="
    log "Rsync + Inotify 自动化实时同步服务"
    log "=========================================="
    log "版本: 自动化 v1.0"
    log "配置信息："
    log "  源目录: ${SOURCE_DIR}"
    log "  目标主机: ${DEST_HOST}"
    log "  目标目录: ${DEST_DIR}"
    log "  Rsync 选项: ${RSYNC_OPTS}"
    log "  同步间隔: ${SYNC_INTERVAL}秒"
    log "  最大重试: ${MAX_RETRIES}次"
    log "=========================================="

    # 1. 生成并共享 SSH 密钥
    if ! setup_ssh_keys; then
        error "SSH 密钥配置失败，退出"
        exit 1
    fi

    # 2. 等待 SSH 服务
    if ! wait_for_ssh; then
        error "无法连接到 SSH 服务，退出"
        exit 1
    fi

    # 3. 测试 SSH 连接
    if ! test_ssh_connection; then
        error "SSH 连接测试失败，退出"
        exit 1
    fi

    # 4. 首次全量同步
    log "=========================================="
    log "首次全量同步"
    log "=========================================="

    if do_sync; then
        log "首次全量同步完成 ✓"
    else
        error "首次全量同步失败，退出"
        exit 1
    fi

    # 5. 启动实时监控
    log "=========================================="
    log "实时监控已启动"
    log "=========================================="
    log "监控目录: ${SOURCE_DIR}"
    log "批量同步间隔: ${SYNC_INTERVAL}秒"
    log "监控事件: CREATE, MODIFY, DELETE, MOVED_TO, CLOSE_WRITE"
    log "=========================================="
    log "✓ 服务运行中，实时监控文件变化..."
    log ""

    # 批量同步变量
    CHANGED=0
    LAST_SYNC=$(date +%s)

    # 监控文件变化
    inotifywait -m -r -e create,modify,delete,moved_to,close_write --format '%w%f %e' ${SOURCE_DIR} | while read line
    do
        info "检测到文件变化: $line"
        CHANGED=1

        NOW=$(date +%s)
        ELAPSED=$((NOW - LAST_SYNC))

        # 批量同步：每隔指定时间同步一次
        if [ $CHANGED -eq 1 ] && [ $ELAPSED -ge $SYNC_INTERVAL ]; then
            log "触发批量同步..."
            do_sync
            CHANGED=0
            LAST_SYNC=$(date +%s)
            log ""
        fi
    done
}

# 信号处理
trap 'log "收到停止信号，正在安全退出..."; exit 0' SIGTERM SIGINT

# 启动主程序
main
