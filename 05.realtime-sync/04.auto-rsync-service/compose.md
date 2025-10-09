# Rsync Daemon 自动化同步使用指南

## 📚 项目概述

本项目是 **Rsync Daemon 模式的全自动化实现**，无需任何手工配置即可启动实时文件同步。

## 🎯 与其他项目的区别

| 项目 | 模式 | 自动化 | 用途 |
|------|------|--------|------|
| 01.manual-rsync_inotify | SSH 手工 | ❌ | 学习 SSH 模式原理 |
| 02.auto-rsync_inotify | SSH 自动 | ✅ | 生产环境（互联网） |
| 03.manual-rsync-service | Daemon 手工 | ❌ | 学习 Daemon 模式原理 |
| **04.auto-rsync-service** | **Daemon 自动** | **✅** | **生产环境（内网）** |

## 🚀 快速开始

### 1. 一键启动

```bash
cd /root/docker-man/05.realtime-sync/04.auto-rsync-service
docker compose up -d
```

就这么简单！服务会自动：
- ✅ 配置 rsync daemon（包括 uid/gid）
- ✅ 生成并共享密码文件
- ✅ 启动服务端和客户端
- ✅ 开始实时同步

### 2. 查看日志

```bash
# 服务端日志（查看配置过程）
docker compose logs rsync-server

# 预期输出：
# [2024-10-09 12:00:00] ==========================================
# [2024-10-09 12:00:00] Rsync Daemon 服务端自动配置
# [2024-10-09 12:00:00] ==========================================
# [2024-10-09 12:00:01] ✓ 配置目录创建完成
# [2024-10-09 12:00:02] ✓ rsyncd.conf 配置完成
# [2024-10-09 12:00:03] ✓ 密码文件创建完成（权限已设置为 600）
# [2024-10-09 12:00:04] ✓ 密码已共享到 /shared-config/rsync.pass
# [2024-10-09 12:00:05] ✓ 配置完成！rsync daemon 启动中...
```

```bash
# 客户端日志（查看同步过程）
docker compose logs rsync-client

# 预期输出：
# [2024-10-09 12:00:05] ==========================================
# [2024-10-09 12:00:05] Rsync Daemon 客户端自动同步
# [2024-10-09 12:00:05] ==========================================
# [2024-10-09 12:00:06] ✓ 密码文件获取成功
# [2024-10-09 12:00:08] ✓ rsync daemon 服务已就绪
# [2024-10-09 12:00:09] ✓ rsync 连接测试成功
# [2024-10-09 12:00:10] ✓ 自动同步已启动！
# [2024-10-09 12:00:10] ✓ 同步完成（耗时 1s）
```

### 3. 测试实时同步

```bash
# 进入客户端容器
docker compose exec rsync-client bash

# 创建测试文件
echo "实时同步测试 $(date)" > /data/source/test-$(date +%s).txt

# 创建子目录
mkdir -p /data/source/images
echo "图片目录测试" > /data/source/images/test.jpg

# 退出容器
exit

# 查看客户端日志（应该自动检测到变化并同步）
docker compose logs -f rsync-client
```

### 4. 验证同步结果

```bash
# 查看服务端备份数据
docker compose exec rsync-server ls -lh /data/backup/

# 预期输出：
# total 8.0K
# -rw-r--r-- 1 root root  95 Oct  9 12:00 auto-client-test.txt
# drwxr-xr-x 2 root root 4.0K Oct  9 12:05 images
# -rw-r--r-- 1 root root  45 Oct  9 12:05 test-1728475920.txt

# 对比源目录和备份目录
docker compose exec rsync-client tree /data/source/
docker compose exec rsync-server tree /data/backup/
```

## 🔧 配置说明

### 网络架构

```
10.0.5.0/24 网段
├── 10.0.5.30  rsync-client（源端）
│   └── /data/source  →  同步到
└── 10.0.5.31  rsync-server（备份端）
    └── /data/backup
```

### 自动生成的配置文件

**服务端 `/etc/rsync/rsyncd.conf`**（自动生成）：
```ini
# 全局配置
uid = root              # 避免权限问题
gid = root
use chroot = no
port = 873
max connections = 10

# 模块定义
[backup]
    path = /data/backup
    read only = no
    auth users = rsyncuser
    secrets file = /etc/rsync/rsyncd.secrets
    hosts allow = 10.0.5.0/24
    transfer logging = yes
```

**服务端 `/etc/rsync/rsyncd.secrets`**（自动生成，权限 600）：
```
rsyncuser:rsyncpass123
```

**客户端 `/etc/rsync/rsync.pass`**（自动获取，权限 600）：
```
rsyncpass123
```

### 同步命令

客户端自动执行的命令：
```bash
rsync -avz --delete \
    --password-file=/etc/rsync/rsync.pass \
    /data/source/ \
    rsync://rsyncuser@10.0.5.31/backup/
```

**选项说明**：
- `-a`：归档模式（保留权限、时间等）
- `-v`：详细输出
- `-z`：传输时压缩
- `--delete`：删除目标端多余文件（保持镜像）
- `--password-file`：自动认证

## 📊 监控与管理

### 实时监控同步状态

```bash
# 持续查看同步日志
docker compose logs -f rsync-client | grep "同步"

# 查看服务端传输日志
docker compose exec rsync-server tail -f /var/log/rsyncd.log
```

### 查看服务状态

```bash
# 检查容器状态
docker compose ps

# 检查 rsync daemon 进程
docker compose exec rsync-server ps aux | grep rsync

# 检查监听端口
docker compose exec rsync-server ss -tlnp | grep 873

# 列出可用模块
docker compose exec rsync-client rsync rsync://10.0.5.31/
```

### 手动执行同步

```bash
# 进入客户端
docker compose exec rsync-client bash

# 手动触发同步
rsync -avz --delete --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.31/backup/

# 查看详细传输信息
rsync -avz --delete --stats --progress \
    --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.31/backup/
```

## 🎨 自定义配置

### 修改密码

编辑 `compose.yml`：

```yaml
services:
  rsync-server:
    environment:
      - RSYNC_PASSWORD=your-new-password  # 修改这里
```

重启服务：
```bash
docker compose down
docker compose up -d
```

### 修改同步策略

**场景 1：不删除目标端文件**

编辑 `scripts/auto-rsync-client.sh`，移除 `--delete` 选项：
```bash
rsync -avz --password-file=${PASSWORD_FILE} \
    ${SOURCE_DIR}/ rsync://${RSYNC_USER}@${RSYNC_SERVER}/${RSYNC_MODULE}/
```

**场景 2：排除某些文件**

添加 `--exclude` 选项：
```bash
rsync -avz --delete \
    --exclude='*.log' \
    --exclude='.git/' \
    --exclude='node_modules/' \
    --password-file=${PASSWORD_FILE} \
    ${SOURCE_DIR}/ rsync://${RSYNC_USER}@${RSYNC_SERVER}/${RSYNC_MODULE}/
```

**场景 3：限制带宽**

添加 `--bwlimit` 选项：
```bash
# 限制为 1MB/s
rsync -avz --delete --bwlimit=1024 \
    --password-file=${PASSWORD_FILE} \
    ${SOURCE_DIR}/ rsync://${RSYNC_USER}@${RSYNC_SERVER}/${RSYNC_MODULE}/
```

### 修改同步间隔

编辑 `compose.yml`（仅在无 inotify 时生效）：

```yaml
services:
  rsync-client:
    environment:
      - SYNC_INTERVAL=10  # 改为 10 秒
```

## 🔍 故障排除

### 问题 1：客户端无法获取密码

**现象**：
```
⚠ 等待密码文件... (30/30)
✗ 无法获取密码文件，退出
```

**排查**：
```bash
# 检查服务端是否正常启动
docker compose logs rsync-server

# 检查共享卷
docker compose exec rsync-server ls -l /shared-config/
docker compose exec rsync-client ls -l /shared-config/
```

**解决**：重启服务
```bash
docker compose restart
```

### 问题 2：无法连接 rsync daemon

**现象**：
```
⚠ 等待 rsync daemon... (30/30)
✗ 无法连接到 rsync daemon，退出
```

**排查**：
```bash
# 检查服务端进程
docker compose exec rsync-server ps aux | grep rsync

# 检查端口监听
docker compose exec rsync-server ss -tlnp | grep 873

# 手动测试连接
docker compose exec rsync-client nc -zv 10.0.5.31 873
```

**解决**：检查服务端日志，重启服务端
```bash
docker compose logs rsync-server
docker compose restart rsync-server
```

### 问题 3：认证失败

**现象**：
```
✗ rsync 连接失败
@ERROR: auth failed on module backup
```

**排查**：
```bash
# 检查密码文件
docker compose exec rsync-server cat /etc/rsync/rsyncd.secrets
docker compose exec rsync-client cat /etc/rsync/rsync.pass

# 检查权限
docker compose exec rsync-server ls -l /etc/rsync/rsyncd.secrets
docker compose exec rsync-client ls -l /etc/rsync/rsync.pass
```

**解决**：确保密码一致，权限为 600

### 问题 4：权限错误

**现象**：
```
rsync: [receiver] mkstemp failed: Permission denied (13)
```

**排查**：
```bash
# 检查配置文件中的 uid/gid
docker compose exec rsync-server grep -E "^(uid|gid)" /etc/rsync/rsyncd.conf

# 检查目录权限
docker compose exec rsync-server ls -ld /data/backup
```

**解决**：确保配置中有 `uid = root` 和 `gid = root`

## 📈 性能优化

### 大文件同步优化

```bash
# 使用部分传输（网络中断时恢复）
rsync -avz --delete --partial --partial-dir=.rsync-partial \
    --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.31/backup/
```

### 压缩优化

```bash
# 已压缩文件不再压缩
rsync -avz --delete \
    --skip-compress=gz/zip/rar/7z/bz2/xz/jpg/png/mp4/mkv \
    --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.31/backup/
```

### 并发传输

```bash
# 使用多线程（需要 rsync 3.2.0+）
rsync -avz --delete --multi-threaded=4 \
    --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.31/backup/
```

## 🧹 清理环境

```bash
# 停止服务
docker compose down

# 删除所有数据（包括 Volume）
docker compose down --volumes

# 完全清理（包括镜像）
docker compose down --volumes --rmi all
```

## 📚 工作原理

### 1. 启动流程

```
服务端（rsync-server）：
  1. 创建配置目录 /etc/rsync
  2. 生成 rsyncd.conf（包含 uid=root, gid=root）
  3. 生成 rsyncd.secrets（权限 600）
  4. 将密码写入 /shared-config/rsync.pass
  5. 启动 rsync daemon（端口 873）

客户端（rsync-client）：
  1. 等待 /shared-config/rsync.pass 出现
  2. 复制到 /etc/rsync/rsync.pass（权限 600）
  3. 使用 nc -z 检测服务端端口 873
  4. 测试 rsync 连接
  5. 创建测试数据
  6. 启动 inotify 监控或定时同步
```

### 2. 同步流程

```
inotify 监控 /data/source
    ↓ 检测到文件变化
    ↓
执行 rsync 命令：
    ↓
rsync -avz --delete --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.31/backup/
    ↓
连接 rsync daemon（端口 873）
    ↓
发送用户名+密码认证
    ↓
传输文件增量数据
    ↓
同步完成，记录日志
```

## 🎓 学习建议

**推荐学习顺序**：

1. **03.manual-rsync-service**（先学）
   - 理解 Daemon 模式原理
   - 手工配置所有文件
   - 理解认证流程

2. **04.auto-rsync-service**（本项目）
   - 查看自动生成的配置
   - 对比手工配置的区别
   - 理解自动化实现

3. **对比 02.auto-rsync_inotify**
   - SSH vs Daemon 模式
   - 加密 vs 性能
   - 适用场景区别

## 🔗 相关文档

- `../03.manual-rsync-service/compose.md` - Daemon 模式原理
- `../02.auto-rsync_inotify/README.md` - SSH 模式自动化
- `../rsync_inotify.md` - Rsync 选项完整参考
- `README.md` - 项目概述

---

**完成时间**: 2024-10-09
**文档版本**: v1.0
**适用环境**: 04.auto-rsync-service
**维护者**: docker-man 项目组
