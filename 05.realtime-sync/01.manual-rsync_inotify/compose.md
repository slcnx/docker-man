# Docker Compose Rsync + Inotify 实时同步实践指南

## 📚 第一部分：基础知识

### 1.1 什么是 Rsync

**Rsync**（Remote Sync）是一个**快速、通用的文件同步工具**，可以在本地和远程系统之间同步文件。

#### Rsync 的特点

| 特性 | 说明 | 优势 |
|------|------|------|
| **增量传输** | 仅传输变化的部分 | 节省带宽，速度快 |
| **压缩传输** | 支持数据压缩 | 减少网络流量 |
| **保留权限** | 保留文件权限、时间戳、所有者 | 完整备份 |
| **断点续传** | 支持中断后继续传输 | 可靠性高 |
| **多种协议** | SSH, rsync daemon, 本地 | 灵活性强 |

#### Rsync 工作原理

```
源端（Source）                          目标端（Destination）
┌─────────────────┐                   ┌─────────────────┐
│  /data/source   │                   │  /data/backup   │
│  ├── file1.txt  │                   │  ├── file1.txt  │
│  ├── file2.txt  │  ──rsync──→       │  ├── file2.txt  │
│  └── file3.txt  │   (增量同步)       │  └── file3.txt  │
└─────────────────┘                   └─────────────────┘

Rsync 算法：
1. 比较源和目标文件的校验和
2. 仅传输差异部分
3. 在目标端重新组装文件
```

---

### 1.2 什么是 Inotify

**Inotify** 是 Linux 内核提供的一种**文件系统事件监控机制**，可以监控文件的创建、修改、删除等操作。

#### Inotify 的特点

| 特性 | 说明 | 优势 |
|------|------|------|
| **实时监控** | 文件变化时立即触发事件 | 即时响应 |
| **内核级别** | 由 Linux 内核提供 | 性能高、可靠 |
| **事件类型丰富** | 支持多种事件类型 | 监控精确 |
| **递归监控** | 可监控目录树 | 功能强大 |

#### Inotify 事件类型

| 事件 | 说明 | 常用场景 |
|------|------|---------|
| **CREATE** | 文件/目录创建 | 监控新文件 |
| **MODIFY** | 文件内容修改 | 监控文件变化 |
| **DELETE** | 文件/目录删除 | 监控删除操作 |
| **MOVED_TO** | 文件移入监控目录 | 监控移动 |
| **MOVED_FROM** | 文件移出监控目录 | 监控移动 |
| **CLOSE_WRITE** | 文件写入后关闭 | 确保写入完成 |

---

### 1.3 Rsync + Inotify 实时同步

**工作原理**：Inotify 监控源目录变化 → 触发 Rsync 同步 → 实时备份

```
┌──────────────────────────────────────────────────────────┐
│                      源端（rsync-source）                  │
│  ┌────────────────────────────────────────────────────┐  │
│  │  inotifywait                                       │  │
│  │  监控 /data/source 目录                             │  │
│  │  事件：CREATE, MODIFY, DELETE, MOVED_TO, CLOSE_WRITE│  │
│  └──────────────┬─────────────────────────────────────┘  │
│                 ↓ 检测到文件变化                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  触发 Rsync 同步                                    │  │
│  │  rsync -avz /data/source/ rsync-backup:/data/backup/│  │
│  └──────────────┬─────────────────────────────────────┘  │
└─────────────────┼──────────────────────────────────────────┘
                  ↓ 网络传输（增量、压缩）
┌─────────────────┼──────────────────────────────────────────┐
│                 ↓                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  /data/backup                                      │  │
│  │  接收并更新文件                                     │  │
│  └────────────────────────────────────────────────────┘  │
│                    目标端（rsync-backup）                  │
└──────────────────────────────────────────────────────────┘
```

---

## 🌐 第二部分：网络架构与环境说明

### 2.1 网络拓扑

```
Docker Bridge 网络：rsync-net (10.0.5.0/24)
├── 10.0.5.1   - 网关（Docker 网桥）
├── 10.0.5.10  - Rsync 源端（rsync-source）
│   ├── Volume: source-data → /data/source
│   └── 运行 inotifywait 监控脚本
└── 10.0.5.11  - Rsync 备份端（rsync-backup）
    ├── Volume: backup-data → /data/backup
    └── 接收同步数据
```

### 2.2 Docker Compose 配置说明

```yaml
version: '3.8'

services:
  rsync-source:
    # Rsync 源端容器
    container_name: rsync-source
    hostname: rsync-source
    networks:
      rsync-net:
        ipv4_address: 10.0.5.10        # 固定 IP
    volumes:
      - source-data:/data/source       # 源数据卷

  rsync-backup:
    # Rsync 备份端容器
    container_name: rsync-backup
    hostname: rsync-backup
    networks:
      rsync-net:
        ipv4_address: 10.0.5.11        # 固定 IP
    volumes:
      - backup-data:/data/backup       # 备份数据卷

networks:
  rsync-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.5.0/24
          gateway: 10.0.5.1

volumes:
  source-data:                          # 源数据卷
    driver: local
  backup-data:                          # 备份数据卷
    driver: local
```

---

## 🚀 第三部分：服务启动与配置

**⚡ 快速开始流程**：

按照文档顺序从上到下执行即可完成整个实验。

```
步骤 1：启动容器（3.1）
   ↓
步骤 2：配置 SSH 环境（3.2）
   ├─ 启动备份端 SSH 服务（3.2.1）
   └─ 配置 SSH 免密登录（3.2.2-3.2.3）
   ↓
步骤 3：创建测试文件并同步（3.3）
   ↓
步骤 4：启动实时同步脚本（4.2）
```

---

### 3.1 启动容器环境

```bash
# 1. 进入项目目录
cd /root/docker-man/05.实时同步/01.manual-rsync_inotify

# 2. 启动所有服务
docker compose up -d

# 3. 检查服务状态
docker compose ps

# 4. 查看网络配置
docker network inspect 01manual-rsync_inotify_rsync-net

# 5. 验证 Volume 创建
docker volume ls | grep rsync
docker volume inspect 01manual-rsync_inotify_source-data
docker volume inspect 01manual-rsync_inotify_backup-data
```

---

### 3.2 配置 SSH 环境

**🔴 重要**：必须先配置 SSH 环境才能进行 rsync 同步！

#### 3.2.1 启动备份端 SSH 服务

```bash
# 进入备份端容器
docker compose exec -it rsync-backup bash

# 1. 生成 SSH 主机密钥（必须先执行）
ssh-keygen -A

# 预期输出：
# ssh-keygen: generating new host keys: RSA DSA ECDSA ED25519

# 2. 启动 SSH 服务
/usr/sbin/sshd

# ⚠️ 如果直接启动 sshd 而没有先执行 ssh-keygen -A，会报错：
# sshd: no hostkeys available -- exiting.

# 3. 验证 SSH 服务运行
ps aux | grep sshd

# 输出应包含：
# root         123  0.0  0.0  12345  6789 ?        Ss   12:00   0:00 /usr/sbin/sshd

# 保持此终端打开或退出（exit）
```

#### 3.2.2 在源端生成 SSH 密钥

```bash
# 进入源端容器
docker compose exec -it rsync-source bash

# 生成 SSH 密钥对
ssh-keygen -t rsa -b 2048 -N "" -f /root/.ssh/id_rsa

# 选项说明：
# -t rsa: 使用 RSA 算法
# -b 2048: 密钥长度 2048 位
# -N "": 无密码
# -f /root/.ssh/id_rsa: 密钥文件路径

# 查看公钥（下一步需要复制）
cat /root/.ssh/id_rsa.pub
```

#### 3.2.3 复制公钥到备份端

**方法 1：手动复制（推荐，更稳定）**

```bash
# ⚠️ 在源端容器中执行（上一步的终端）
# 查看并复制公钥内容
cat /root/.ssh/id_rsa.pub
# 复制输出的内容

# 新开终端，进入备份端容器
docker compose exec -it rsync-backup bash

# 创建 .ssh 目录并设置权限
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# 将公钥写入 authorized_keys（粘贴刚才复制的公钥）
cat > /root/.ssh/authorized_keys <<'EOF'
[粘贴源端的公钥内容]
EOF

# 设置正确的权限
chmod 600 /root/.ssh/authorized_keys

# 退出备份端容器
exit
```

**方法 2：使用 ssh-copy-id（自动化）**

```bash
# 在源端容器中执行
ssh-copy-id -i /root/.ssh/id_rsa.pub root@rsync-backup

# 或使用 IP 地址
ssh-copy-id -i /root/.ssh/id_rsa.pub root@10.0.5.11

# 首次连接会提示确认指纹，输入 yes
```

#### 3.2.4 测试 SSH 免密登录

```bash
# 在源端容器中测试（确保你在 rsync-source 容器中）
ssh -o StrictHostKeyChecking=no root@rsync-backup "echo SSH connection successful"

# 预期输出：
# SSH connection successful

# ✅ 如果成功，说明 SSH 免密登录配置完成，可以继续下一步
# ❌ 如果失败，请检查：
#   1. SSH 服务是否运行（ps aux | grep sshd）
#   2. 公钥是否正确复制（cat /root/.ssh/authorized_keys）
#   3. 权限是否正确（ls -la /root/.ssh/）
```

---

### 3.3 创建测试文件并执行 Rsync 同步

**📝 前置条件**：确保已完成 3.2 的 SSH 环境配置。

#### 3.3.1 创建测试文件

```bash
# 在源端容器中执行（应该还在 rsync-source 容器中）
# 如果已退出，重新进入：
# docker compose exec -it rsync-source bash

# 创建测试文件
echo "Test File 1" > /data/source/test1.txt
echo "Test File 2" > /data/source/test2.txt

# 创建子目录和文件
mkdir -p /data/source/subdir
echo "Subdir File" > /data/source/subdir/test3.txt

# 查看源目录结构
tree /data/source/
# 或者使用 find
find /data/source -type f

# 预期输出：
# /data/source/
# ├── test1.txt
# ├── test2.txt
# └── subdir
#     └── test3.txt
```

#### 3.3.2 首次 Rsync 同步

```bash
# 在源端容器中执行完整同步
rsync -avz -e "ssh -o StrictHostKeyChecking=no" /data/source/ root@rsync-backup:/data/backup/

# 选项说明：
# -a: archive 归档模式（保留权限、时间戳等）
# -v: verbose 显示详细信息
# -z: compress 压缩传输
# -e "ssh ...": 指定使用 SSH 协议
# -o StrictHostKeyChecking=no: 不检查主机密钥（仅测试环境）
# /data/source/: 源目录（注意末尾的 /）
# root@rsync-backup:/data/backup/: 目标（用户@主机:路径）

# 预期输出：
# sending incremental file list
# ./
# test1.txt
# test2.txt
# subdir/
# subdir/test3.txt
#
# sent 345 bytes  received 89 bytes  868.00 bytes/sec
# total size is 45  speedup is 0.10
```

#### 3.3.3 验证同步结果

```bash
# 新开终端，进入备份端容器验证
docker compose exec -it rsync-backup bash

# 查看备份目录结构
tree /data/backup/
# 或
find /data/backup -type f

# 输出应与源端一致：
# /data/backup/
# ├── test1.txt
# ├── test2.txt
# └── subdir
#     └── test3.txt

# 对比文件内容
cat /data/backup/test1.txt
# 输出：Test File 1

cat /data/backup/test2.txt
# 输出：Test File 2

cat /data/backup/subdir/test3.txt
# 输出：Subdir File

# 退出备份端容器
exit
```

#### 3.3.4 测试增量同步

```bash
# 回到源端容器（或重新进入）
docker compose exec -it rsync-source bash

# 修改现有文件
echo "Modified content" >> /data/source/test1.txt

# 创建新文件
echo "New File 4" > /data/source/test4.txt

# 创建新子目录和文件
mkdir -p /data/source/newdir
echo "New Dir File" > /data/source/newdir/test5.txt

# 再次同步
rsync -avz -e "ssh -o StrictHostKeyChecking=no" /data/source/ root@rsync-backup:/data/backup/

# 预期输出（仅同步变化的文件）：
# sending incremental file list
# test1.txt
# test4.txt
# newdir/
# newdir/test5.txt
#
# sent 287 bytes  received 67 bytes  708.00 bytes/sec
# total size is 78  speedup is 0.22

# 验证增量同步结果
docker compose exec rsync-backup bash -c "cat /data/backup/test1.txt"
# 应包含：Test File 1
#        Modified content

docker compose exec rsync-backup bash -c "cat /data/backup/test4.txt"
# 输出：New File 4
```

---

## 🔔 第四部分：Inotify 实时监控

### 4.1 Inotify 基础测试

#### 4.1.1 安装验证

```bash
# 在源端容器中验证
which inotifywait

# 输出：
# /usr/bin/inotifywait

# 查看版本
inotifywait --version

# 输出：
# inotifywait 3.x.x
```

#### 4.1.2 监控测试

**终端 1：启动监控**

```bash
# 在源端容器中执行
inotifywait -m /data/source/

# 选项说明：
# -m: monitor 持续监控模式
# /data/source/: 监控目录

# 输出：
# Setting up watches.
# Watches established.
```

**终端 2：创建文件触发事件**

```bash
# 在源端容器新开终端
docker compose exec -it rsync-source bash

# 创建文件
echo "Trigger Test" > /data/source/trigger.txt

# 终端 1 应该显示：
# /data/source/ CREATE trigger.txt
# /data/source/ OPEN trigger.txt
# /data/source/ MODIFY trigger.txt
# /data/source/ CLOSE_WRITE,CLOSE trigger.txt
```

#### 4.1.3 监控特定事件

```bash
# 仅监控创建、修改、删除、移动、关闭写入
inotifywait -m -e create,modify,delete,moved_to,close_write /data/source/

# 选项说明：
# -e: events 指定事件类型
# create: 文件创建
# modify: 文件修改
# delete: 文件删除
# moved_to: 文件移入
# close_write: 写入后关闭
```

#### 4.1.4 递归监控子目录

```bash
# 递归监控整个目录树
inotifywait -m -r /data/source/

# 选项说明：
# -r: recursive 递归监控

# 测试：创建子目录文件
mkdir -p /data/source/level1/level2
echo "Deep File" > /data/source/level1/level2/deep.txt

# 应该能监控到所有层级的文件变化
```

---

### 4.2 Inotify + Rsync 实时同步脚本

#### 4.2.1 创建同步脚本

```bash
# 在源端容器中创建脚本
cat > /usr/local/bin/rsync-inotify.sh <<'EOF'
#!/bin/bash

# 配置变量
SOURCE_DIR="/data/source/"
DEST_HOST="rsync-backup"
DEST_DIR="/data/backup/"
RSYNC_OPTS="-avz --delete"
SSH_OPTS="-o StrictHostKeyChecking=no"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 首次全量同步
log "开始首次全量同步..."
rsync $RSYNC_OPTS -e "ssh $SSH_OPTS" $SOURCE_DIR root@${DEST_HOST}:${DEST_DIR}
log "首次全量同步完成"

# 实时监控并同步
log "开始实时监控 $SOURCE_DIR"
inotifywait -m -r -e create,modify,delete,moved_to,close_write $SOURCE_DIR | while read path action file
do
    log "检测到变化: $path$file ($action)"

    # 延迟 1 秒，避免频繁同步
    sleep 1

    # 执行同步
    rsync $RSYNC_OPTS -e "ssh $SSH_OPTS" $SOURCE_DIR root@${DEST_HOST}:${DEST_DIR}

    if [ $? -eq 0 ]; then
        log "同步成功"
    else
        log "同步失败，退出码: $?"
    fi
done
EOF

# 添加执行权限
chmod +x /usr/local/bin/rsync-inotify.sh

# 查看脚本
cat /usr/local/bin/rsync-inotify.sh
```

**脚本说明**：

| 部分 | 功能 | 说明 |
|------|------|------|
| **配置变量** | 源目录、目标主机、目标目录 | 便于修改 |
| **log 函数** | 记录日志 | 带时间戳 |
| **首次全量同步** | 启动时完整同步一次 | 确保一致性 |
| **inotifywait 监控** | 实时监控文件变化 | 触发同步 |
| **延迟 1 秒** | 避免频繁同步 | 优化性能 |
| **rsync 同步** | 增量同步 | 仅传输变化 |

#### 4.2.2 测试同步脚本

**终端 1：启动同步脚本**

```bash
# 在源端容器中执行
/usr/local/bin/rsync-inotify.sh

# 输出：
# [2025-10-09 12:00:00] 开始首次全量同步...
# sending incremental file list
# ...
# [2025-10-09 12:00:01] 首次全量同步完成
# [2025-10-09 12:00:01] 开始实时监控 /data/source/
# Setting up watches.  Beware: since -r was given, this may take a while!
# Watches established.
```

**终端 2：创建文件测试**

```bash
# 在源端容器新开终端
docker compose exec -it rsync-source bash

# 创建文件
echo "Real-time Test 1" > /data/source/realtime1.txt

# 终端 1 应该显示：
# [2025-10-09 12:01:00] 检测到变化: /data/source/realtime1.txt (CLOSE_WRITE,CLOSE)
# sending incremental file list
# realtime1.txt
# ...
# [2025-10-09 12:01:01] 同步成功
```

**验证同步结果**：

```bash
# 在备份端验证
docker compose exec rsync-backup cat /data/backup/realtime1.txt

# 输出：
# Real-time Test 1
```

---

### 4.3 高级同步脚本（批量同步）

#### 4.3.1 创建批量同步脚本

```bash
# 在源端容器中创建优化版脚本
cat > /usr/local/bin/rsync-inotify-batch.sh <<'EOF'
#!/bin/bash

# 配置变量
SOURCE_DIR="/data/source/"
DEST_HOST="rsync-backup"
DEST_DIR="/data/backup/"
RSYNC_OPTS="-avz --delete"
SSH_OPTS="-o StrictHostKeyChecking=no"
BATCH_INTERVAL=5  # 批量同步间隔（秒）

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 同步函数
do_sync() {
    log "开始同步..."
    rsync $RSYNC_OPTS -e "ssh $SSH_OPTS" $SOURCE_DIR root@${DEST_HOST}:${DEST_DIR}

    if [ $? -eq 0 ]; then
        log "同步成功"
    else
        log "同步失败，退出码: $?"
    fi
}

# 首次全量同步
log "开始首次全量同步..."
do_sync

# 实时监控并批量同步
log "开始实时监控 $SOURCE_DIR (批量间隔: ${BATCH_INTERVAL}秒)"

CHANGED=0
LAST_SYNC=$(date +%s)

inotifywait -m -r -e create,modify,delete,moved_to,close_write --format '%w%f %e' $SOURCE_DIR | while read line
do
    log "检测到变化: $line"
    CHANGED=1

    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_SYNC))

    # 如果距离上次同步超过批量间隔，且有变化
    if [ $CHANGED -eq 1 ] && [ $ELAPSED -ge $BATCH_INTERVAL ]; then
        do_sync
        CHANGED=0
        LAST_SYNC=$(date +%s)
    fi
done
EOF

# 添加执行权限
chmod +x /usr/local/bin/rsync-inotify-batch.sh
```

**优化说明**：

| 优化项 | 说明 | 好处 |
|-------|------|------|
| **批量同步** | 每 5 秒同步一次（如果有变化） | 减少同步次数 |
| **避免频繁同步** | 多个文件变化合并为一次同步 | 提升性能 |
| **变化标记** | CHANGED 标记是否有文件变化 | 无变化时不同步 |

---

## 📊 第五部分：Rsync 选项详解

### 5.1 常用选项

| 选项 | 说明 | 示例 |
|------|------|------|
| **-a** | 归档模式（等同于 -rlptgoD） | 保留权限、时间戳、所有者 |
| **-r** | 递归复制目录 | 复制整个目录树 |
| **-l** | 保留符号链接 | 链接文件作为链接复制 |
| **-p** | 保留权限 | 保留文件权限 |
| **-t** | 保留时间戳 | 保留修改时间 |
| **-g** | 保留组 | 保留文件所属组 |
| **-o** | 保留所有者 | 保留文件所有者 |
| **-v** | 显示详细信息 | 显示传输过程 |
| **-z** | 压缩传输 | 减少网络流量 |
| **--delete** | 删除目标端多余文件 | 保持源和目标一致 |
| **--exclude** | 排除文件/目录 | 不同步特定文件 |
| **--dry-run** | 模拟运行 | 仅显示会做什么，不实际操作 |
| **--progress** | 显示进度 | 显示每个文件的传输进度 |
| **-h** | 人类可读格式 | 文件大小显示为 KB, MB 等 |

### 5.2 选项组合示例

```bash
# 基础同步
rsync -avz /data/source/ rsync-backup:/data/backup/

# 同步 + 删除目标多余文件
rsync -avz --delete /data/source/ rsync-backup:/data/backup/

# 排除特定文件
rsync -avz --exclude '*.log' --exclude 'tmp/' /data/source/ rsync-backup:/data/backup/

# 显示进度
rsync -avzh --progress /data/source/ rsync-backup:/data/backup/

# 模拟运行（查看会同步什么）
rsync -avz --dry-run /data/source/ rsync-backup:/data/backup/

# 限制带宽（KB/s）
rsync -avz --bwlimit=1024 /data/source/ rsync-backup:/data/backup/

# 仅同步已存在的文件（不创建新文件）
rsync -avz --existing /data/source/ rsync-backup:/data/backup/

# 同步并保留硬链接
rsync -avzH /data/source/ rsync-backup:/data/backup/
```

---

## 🔧 第六部分：故障排除

### 6.1 常见错误

#### 错误 1：Connection refused（最常见）

```bash
# 错误信息
ssh: connect to host rsync-backup port 22: Connection refused
rsync: connection unexpectedly closed (0 bytes received so far) [sender]
rsync error: unexplained error (code 255) at io.c(228) [sender=3.2.5]

# 原因：SSH 服务未启动（这是最常见的错误）

# 解决方法：
# 1. 在备份端启动 SSH 服务
docker compose exec rsync-backup /usr/sbin/sshd

# 2. 验证服务运行
docker compose exec rsync-backup ps aux | grep sshd

# 3. 如果还是失败，生成 SSH 主机密钥
docker compose exec rsync-backup ssh-keygen -A
docker compose exec rsync-backup /usr/sbin/sshd

# 4. 再次测试连接
docker compose exec rsync-source ssh -o StrictHostKeyChecking=no root@rsync-backup "echo OK"
```

---

#### 错误 2：sshd: no hostkeys available -- exiting

```bash
# 错误信息
[root@rsync-backup data]# /usr/sbin/sshd
sshd: no hostkeys available -- exiting.

# 原因：SSH 主机密钥未生成

# 解决方法：
# 1. 生成 SSH 主机密钥
ssh-keygen -A

# 2. 再次启动 SSH 服务
/usr/sbin/sshd

# 3. 验证服务运行
ps aux | grep sshd

# 说明：
# - 这是启动 SSH 服务的必要前置步骤
# - ssh-keygen -A 会自动生成所有类型的主机密钥（RSA, ECDSA, ED25519 等）
# - 密钥存储在 /etc/ssh/ 目录下
```

---

#### 错误 3：Permission denied (publickey)

```bash
# 错误信息
rsync: connection unexpectedly closed (0 bytes received so far) [sender]
rsync error: unexplained error (code 255) at io.c(235) [sender=3.1.3]

# 原因：SSH 免密登录未配置

# 解决：
# 1. 检查公钥是否复制
docker compose exec rsync-backup cat /root/.ssh/authorized_keys

# 2. 检查权限
docker compose exec rsync-backup ls -l /root/.ssh/
# authorized_keys 应该是 600

# 3. 检查 SSH 服务
docker compose exec rsync-backup ps aux | grep sshd
```

---

#### 错误 4：inotify watch limit

```bash
# 错误信息
Failed to watch /data/source; upper limit on inotify watches reached!

# 原因：inotify 监控数量达到上限

# 查看当前限制
cat /proc/sys/fs/inotify/max_user_watches

# 临时增加限制（宿主机执行）
echo 524288 | sudo tee /proc/sys/fs/inotify/max_user_watches

# 永久增加限制（宿主机执行）
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## 🎓 第七部分：学习总结

### 核心知识点

1. **Rsync 特点**：增量传输、压缩、保留属性、断点续传
2. **Inotify 机制**：内核级文件监控，实时响应文件变化
3. **实时同步原理**：Inotify 监控 → 触发 Rsync → 增量同步
4. **SSH 免密登录**：公钥认证，安全便捷

### 关键命令

```bash
# Rsync
rsync -avz /source/ user@host:/dest/       # 基础同步
rsync -avz --delete /source/ host:/dest/   # 同步并删除多余文件

# Inotify
inotifywait -m -r -e create,modify /path   # 实时监控

# SSH
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa   # 生成密钥
ssh-copy-id user@host                      # 复制公钥
```

### 最佳实践

- ✅ 使用 `-avz` 选项保留文件属性并压缩
- ✅ 使用 `--delete` 保持源和目标一致
- ✅ 配置 SSH 免密登录提高安全性
- ✅ 批量同步减少 I/O 压力
- ✅ 使用 `--exclude` 排除不必要的文件

---

## 🧹 清理环境

```bash
# 1. 停止所有容器
docker compose down

# 2. 删除 Volume（会删除数据）
docker compose down --volumes

# 3. 完全清理（包括镜像）
docker compose down --volumes --rmi all
```

---

**完成时间**: 2025-10-09
**文档版本**: v1.0
**适用环境**: 05.实时同步/01.manual-rsync_inotify
**维护者**: docker-man 项目组
