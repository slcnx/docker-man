# 自动化 Rsync + Inotify 实时同步详细指南

## 📚 目录

1. [项目概述](#1-项目概述)
2. [自动化原理](#2-自动化原理)
3. [快速开始](#3-快速开始)
4. [自动化流程详解](#4-自动化流程详解)
5. [配置说明](#5-配置说明)
6. [监控与日志](#6-监控与日志)
7. [故障排查](#7-故障排查)
8. [进阶使用](#8-进阶使用)

---

## 1. 项目概述

### 1.1 什么是自动化版本

本项目是 `01.manual-rsync_inotify` 的**完全自动化版本**，实现了：

- ✅ **零手动配置**：`docker compose up -d` 一键启动
- ✅ **自动 SSH 配置**：自动生成密钥、自动配置免密登录
- ✅ **自动服务发现**：自动等待服务就绪
- ✅ **自动健康检查**：自动重试、自动恢复
- ✅ **生产级日志**：结构化、彩色输出

### 1.2 vs 手动版本

| 特性 | 01.manual | 02.auto |
|------|-----------|---------|
| 启动命令 | 多步手动操作 | `docker compose up -d` |
| SSH 配置 | 手动生成、手动复制 | 自动通过共享卷交换 |
| 服务检查 | 手动测试 | 自动等待 + 重试 |
| 适用场景 | 学习、理解原理 | 生产环境、CI/CD |
| 学习曲线 | 高（需理解每一步） | 低（开箱即用） |

---

## 2. 自动化原理

### 2.1 架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                      Docker Compose 编排                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────────┴─────────────────────┐
        ↓                                           ↓
┌───────────────────┐                    ┌───────────────────┐
│  rsync-source     │                    │  rsync-backup     │
│  (10.0.5.10)      │                    │  (10.0.5.11)      │
├───────────────────┤                    ├───────────────────┤
│ rsync-inotify.sh  │                    │ start-sshd.sh     │
│                   │                    │                   │
│ 1️⃣ 生成 SSH 密钥  │                    │ 1️⃣ 启动 SSH 服务  │
│ 2️⃣ 共享公钥       │───── ssh-keys ────→│ 2️⃣ 读取公钥       │
│ 3️⃣ 等待 SSH 就绪  │      (共享卷)      │ 3️⃣ 配置 authorized_keys│
│ 4️⃣ 测试 SSH 连接  │                    │ 4️⃣ 监控公钥更新   │
│ 5️⃣ 首次全量同步   │                    │                   │
│ 6️⃣ 实时监控同步   │                    │                   │
└───────────────────┘                    └───────────────────┘
```

### 2.2 关键技术

#### 2.2.1 共享卷自动交换密钥

```yaml
volumes:
  - ssh-keys:/shared-keys     # 两个容器共享此卷
```

**工作流程**：
1. **源端**：生成 `id_rsa` 和 `id_rsa.pub`
2. **源端**：将 `id_rsa.pub` 复制到 `/shared-keys/`
3. **备份端**：从 `/shared-keys/` 读取公钥
4. **备份端**：写入 `/root/.ssh/authorized_keys`

#### 2.2.2 服务依赖与等待

```yaml
depends_on:
  - rsync-backup
```

```bash
# 在脚本中实现智能等待
while [ $retries -lt $MAX_RETRIES ]; do
    if nc -z ${DEST_HOST} 22 2>/dev/null; then
        break
    fi
    sleep 5
done
```

#### 2.2.3 环境变量配置

```yaml
environment:
  - DEST_HOST=rsync-backup
  - SYNC_INTERVAL=5
  - MAX_RETRIES=10
```

---

## 3. 快速开始

### 3.1 一键启动

```bash
# 1. 进入项目目录
cd /root/docker-man/05.realtime-sync/02.auto-rsync_inotify

# 2. 启动（自动构建 + 配置 + 运行）
docker compose up -d

# 3. 查看启动日志
docker compose logs -f
```

### 3.2 验证运行

```bash
# 检查服务状态
docker compose ps

# 预期输出：
# NAME            IMAGE                  STATUS
# rsync-backup    rsync-inotify:latest   Up
# rsync-source    rsync-inotify:latest   Up

# 查看实时日志
docker compose logs -f rsync-source
```

### 3.3 测试同步

```bash
# 创建测试文件
docker compose exec rsync-source bash -c "echo 'Hello Auto Sync' > /data/source/test.txt"

# 等待 5 秒（SYNC_INTERVAL），查看日志
docker compose logs rsync-source | tail -20

# 验证同步结果
docker compose exec rsync-backup cat /data/backup/test.txt
# 输出：Hello Auto Sync
```

---

## 4. 自动化流程详解

### 4.1 启动阶段

#### 步骤 1：镜像构建

```bash
# Docker Compose 自动执行
docker build -f ../rsync_inotify.dockerfile -t rsync-inotify:latest ..
```

**Dockerfile 内容**（参考 `../rsync_inotify.dockerfile`）：
- 基于 Ubuntu/Alpine
- 安装 rsync、inotify-tools、openssh-server
- 配置工作目录

#### 步骤 2：容器启动

```bash
# 按 depends_on 顺序启动
1. rsync-backup (备份端先启动)
2. rsync-source (源端后启动)
```

#### 步骤 3：备份端初始化 (start-sshd.sh)

```
[2025-10-09 12:00:00] ==========================================
[2025-10-09 12:00:00] SSH 服务器 - 自动配置启动
[2025-10-09 12:00:00] ==========================================
[2025-10-09 12:00:00] 生成 SSH 主机密钥...
[2025-10-09 12:00:01] SSH 主机密钥生成完成 ✓
[2025-10-09 12:00:01] 配置 SSH 服务...
[2025-10-09 12:00:01] SSH 配置完成 ✓
[2025-10-09 12:00:01] 等待源端公钥...
[INFO 2025-10-09 12:00:01] 等待源端生成公钥... (1/30)
[2025-10-09 12:00:05] 发现源端公钥，配置授权...
[2025-10-09 12:00:05] SSH 免密登录配置完成 ✓
[2025-10-09 12:00:05] 启动 SSH 服务...
[2025-10-09 12:00:05] SSH 服务已启动 ✓
[2025-10-09 12:00:05]   PID: 123
[2025-10-09 12:00:05]   端口: 22
[2025-10-09 12:00:05]   主机名: rsync-backup
[2025-10-09 12:00:05]   IP 地址: 10.0.5.11
[2025-10-09 12:00:05] ==========================================
[2025-10-09 12:00:05] SSH 服务器就绪，等待连接...
[2025-10-09 12:00:05] ==========================================
```

#### 步骤 4：源端初始化 (rsync-inotify.sh)

```
[2025-10-09 12:00:05] ==========================================
[2025-10-09 12:00:05] Rsync + Inotify 自动化实时同步服务
[2025-10-09 12:00:05] ==========================================
[2025-10-09 12:00:05] 版本: 自动化 v1.0
[2025-10-09 12:00:05] 配置信息：
[2025-10-09 12:00:05]   源目录: /data/source/
[2025-10-09 12:00:05]   目标主机: rsync-backup
[2025-10-09 12:00:05]   目标目录: /data/backup/
[2025-10-09 12:00:05]   Rsync 选项: -avz --delete
[2025-10-09 12:00:05]   同步间隔: 5秒
[2025-10-09 12:00:05]   最大重试: 10次
[2025-10-09 12:00:05] ==========================================
[2025-10-09 12:00:05] ==========================================
[2025-10-09 12:00:05] 配置 SSH 密钥（自动化）
[2025-10-09 12:00:05] ==========================================
[2025-10-09 12:00:05] 生成 SSH 密钥对...
[2025-10-09 12:00:06] SSH 密钥生成完成 ✓
[2025-10-09 12:00:06] 共享公钥到备份服务器...
[2025-10-09 12:00:06] 公钥已共享 ✓
[2025-10-09 12:00:06] ==========================================
[2025-10-09 12:00:06] 等待 SSH 服务就绪
[2025-10-09 12:00:06] ==========================================
[2025-10-09 12:00:06] 目标主机: rsync-backup:22
[2025-10-09 12:00:06] SSH 服务已就绪 ✓
[2025-10-09 12:00:09] ==========================================
[2025-10-09 12:00:09] 测试 SSH 连接
[2025-10-09 12:00:09] ==========================================
[2025-10-09 12:00:10] SSH 免密登录测试成功 ✓
[2025-10-09 12:00:10] ==========================================
[2025-10-09 12:00:10] 首次全量同步
[2025-10-09 12:00:10] ==========================================
[2025-10-09 12:00:11] 同步成功 (耗时: 1秒) ✓
[2025-10-09 12:00:11] 首次全量同步完成 ✓
[2025-10-09 12:00:11] ==========================================
[2025-10-09 12:00:11] 实时监控已启动
[2025-10-09 12:00:11] ==========================================
[2025-10-09 12:00:11] 监控目录: /data/source/
[2025-10-09 12:00:11] 批量同步间隔: 5秒
[2025-10-09 12:00:11] 监控事件: CREATE, MODIFY, DELETE, MOVED_TO, CLOSE_WRITE
[2025-10-09 12:00:11] ==========================================
[2025-10-09 12:00:11] ✓ 服务运行中，实时监控文件变化...
```

### 4.2 运行阶段

#### 文件变化触发同步

```
[INFO 2025-10-09 12:05:00] 检测到文件变化: /data/source/test.txt CLOSE_WRITE,CLOSE
[2025-10-09 12:05:05] 触发批量同步...
[2025-10-09 12:05:06] 同步成功 (耗时: 1秒) ✓
```

#### 批量同步机制

```bash
# 在 5 秒间隔内的多个文件变化，合并为一次同步
CHANGED=0
LAST_SYNC=$(date +%s)

while read line; do
    CHANGED=1
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_SYNC))

    if [ $CHANGED -eq 1 ] && [ $ELAPSED -ge 5 ]; then
        do_sync
        CHANGED=0
        LAST_SYNC=$(date +%s)
    fi
done
```

---

## 5. 配置说明

### 5.1 环境变量完整列表

| 环境变量 | 说明 | 默认值 | 示例 |
|----------|------|--------|------|
| `SOURCE_DIR` | 源目录路径 | `/data/source/` | `/data/web/` |
| `DEST_HOST` | 目标主机名 | `rsync-backup` | `backup-server` |
| `DEST_DIR` | 目标目录路径 | `/data/backup/` | `/backup/web/` |
| `RSYNC_OPTS` | Rsync 选项 | `-avz --delete` | `-avzh --progress` |
| `SSH_OPTS` | SSH 选项 | `-o StrictHostKeyChecking=no` | `-p 2222` |
| `SYNC_INTERVAL` | 同步间隔（秒） | `5` | `10` |
| `MAX_RETRIES` | 最大重试次数 | `10` | `20` |

### 5.2 修改配置

#### 方法 1：修改 compose.yml

```yaml
environment:
  - SYNC_INTERVAL=10        # 改为 10 秒间隔
  - RSYNC_OPTS=-avz         # 移除 --delete 选项
```

#### 方法 2：使用 .env 文件

```bash
# 创建 .env 文件
cat > .env <<'EOF'
SYNC_INTERVAL=10
RSYNC_OPTS=-avz
MAX_RETRIES=20
EOF

# 重启服务
docker compose down && docker compose up -d
```

### 5.3 常用配置场景

#### 场景 1：高频同步（实时性要求高）

```yaml
environment:
  - SYNC_INTERVAL=1         # 1 秒间隔
```

#### 场景 2：低频同步（减少 I/O）

```yaml
environment:
  - SYNC_INTERVAL=30        # 30 秒间隔
```

#### 场景 3：仅增量不删除

```yaml
environment:
  - RSYNC_OPTS=-avz         # 移除 --delete
```

#### 场景 4：限制带宽

```yaml
environment:
  - RSYNC_OPTS=-avz --delete --bwlimit=5120  # 限速 5MB/s
```

---

## 6. 监控与日志

### 6.1 实时日志查看

```bash
# 查看所有服务日志
docker compose logs -f

# 仅查看源端（同步日志）
docker compose logs -f rsync-source

# 仅查看备份端（SSH 服务日志）
docker compose logs -f rsync-backup

# 查看最近 100 行
docker compose logs --tail=100

# 查看带时间戳
docker compose logs -f -t
```

### 6.2 日志级别

| 级别 | 颜色 | 说明 | 示例 |
|------|------|------|------|
| **LOG** | 🟢 绿色 | 正常操作 | `[2025-10-09 12:00:00] 同步成功 ✓` |
| **INFO** | 🔵 蓝色 | 信息提示 | `[INFO] 检测到文件变化` |
| **WARN** | 🟡 黄色 | 警告（可继续） | `[WARN] SSH 连接重试...` |
| **ERROR** | 🔴 红色 | 错误（严重） | `[ERROR] 同步失败` |

### 6.3 关键日志

#### 成功启动标志

```
✓ 服务运行中，实时监控文件变化...
```

#### 同步成功

```
[2025-10-09 12:00:00] 同步成功 (耗时: 1秒) ✓
```

#### 检测到变化

```
[INFO 2025-10-09 12:00:00] 检测到文件变化: /data/source/test.txt
```

---

## 7. 故障排查

### 7.1 服务无法启动

#### 问题：容器立即退出

```bash
# 检查退出原因
docker compose ps
docker compose logs rsync-source
docker compose logs rsync-backup
```

**可能原因**：
1. 脚本权限问题
2. Dockerfile 构建失败
3. 环境变量配置错误

**解决方法**：
```bash
# 1. 检查脚本权限
ls -l scripts/
chmod +x scripts/*.sh

# 2. 重新构建镜像
docker compose build --no-cache

# 3. 查看详细日志
docker compose up
```

### 7.2 SSH 连接失败

#### 问题：SSH connection test failed

```bash
# 查看备份端是否正常运行
docker compose ps rsync-backup

# 手动测试 SSH
docker compose exec rsync-source nc -zv rsync-backup 22

# 检查公钥是否共享
docker compose exec rsync-source ls -l /shared-keys/
docker compose exec rsync-backup ls -l /root/.ssh/authorized_keys
```

### 7.3 同步不工作

#### 问题：文件创建了但未同步

```bash
# 检查 inotify 是否运行
docker compose exec rsync-source ps aux | grep inotify

# 检查文件变化是否被检测到
docker compose logs rsync-source | grep "检测到文件变化"

# 手动触发同步测试
docker compose exec rsync-source rsync -avz /data/source/ root@rsync-backup:/data/backup/
```

### 7.4 常见错误码

| 错误码 | 说明 | 解决方法 |
|--------|------|----------|
| 255 | SSH 连接失败 | 检查 SSH 服务、密钥配置 |
| 23 | 部分文件传输失败 | 检查权限、磁盘空间 |
| 12 | 协议版本不匹配 | 检查 rsync 版本 |

---

## 8. 进阶使用

### 8.1 持久化存储

将 Docker Volume 改为宿主机目录：

```yaml
volumes:
  # - source-data:/data/source      # 注释掉 Volume
  - /path/on/host/source:/data/source   # 挂载宿主机目录
```

### 8.2 多目标同步

修改脚本支持多个备份目标：

```bash
# 在 rsync-inotify.sh 中添加
DEST_HOSTS=("rsync-backup1" "rsync-backup2")

for host in "${DEST_HOSTS[@]}"; do
    rsync -avz /data/source/ root@${host}:/data/backup/
done
```

### 8.3 日志持久化

添加日志文件输出：

```yaml
volumes:
  - ./logs:/var/log/rsync
```

```bash
# 在脚本中添加
exec 1> >(tee -a /var/log/rsync/sync.log)
exec 2>&1
```

### 8.4 监控集成

添加 Prometheus 指标：

```bash
# 导出同步次数、失败次数等指标
echo "rsync_sync_total ${SYNC_COUNT}" > /var/metrics/rsync.prom
```

---

## 📚 相关文档

- [快速入门](README.md)
- [Rsync 选项参考](../rsync_inotify.md)
- [手动版本对比](../01.manual-rsync_inotify/)
- [Dockerfile 源码](../rsync_inotify.dockerfile)

---

**文档版本**: v1.0
**更新日期**: 2025-10-09
**维护者**: docker-man 项目组
