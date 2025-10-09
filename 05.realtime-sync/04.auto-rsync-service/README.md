# Rsync Daemon 自动化同步

## 📋 项目说明

本项目提供 **Rsync Daemon 模式的全自动化同步方案**，适用于生产环境的实时文件备份。

## 🎯 特性

- ✅ **零配置启动**：服务端和客户端完全自动配置
- ✅ **自动密码交换**：通过共享卷自动分发认证密码
- ✅ **实时同步**：基于 inotify 的文件变化监控
- ✅ **智能重试**：服务启动等待和连接重试机制
- ✅ **生产就绪**：包含日志记录、错误处理、健康检查

## 🏗️ 架构

### 工作流程

```
1. 启动阶段：
   rsync-server → 生成配置 → 启动 daemon → 共享密码
                                                   ↓
   rsync-client → 等待密码 → 等待服务 → 测试连接 → 开始同步

2. 运行阶段：
   /data/source (客户端)
        ↓ inotify 监控文件变化
        ↓ rsync daemon 协议 (端口 873)
   /data/backup (服务端)
```

### 配置交换机制

```
shared-config volume（共享卷）
     ↓
Server: 写入 rsync.pass → /shared-config/rsync.pass
     ↓
Client: 读取 rsync.pass ← /shared-config/rsync.pass
     ↓
自动认证，无需手工操作
```

## 🔄 与其他项目的对比

| 项目 | 传输模式 | 认证方式 | 自动化 | 适用场景 |
|------|---------|---------|--------|---------|
| 01.manual-rsync_inotify | SSH | SSH密钥 | ❌ 手工 | 学习 SSH 模式 |
| 02.auto-rsync_inotify | SSH | SSH密钥 | ✅ 自动 | 生产环境（互联网） |
| 03.manual-rsync-service | Daemon | 用户密码 | ❌ 手工 | 学习 Daemon 模式 |
| **04.auto-rsync-service** | **Daemon** | **用户密码** | **✅ 自动** | **生产环境（内网）** |

## 🚀 快速开始

### 1. 启动服务

```bash
cd /root/docker-man/05.realtime-sync/04.auto-rsync-service
docker compose up -d
```

### 2. 查看日志

```bash
# 查看服务端日志（配置过程）
docker compose logs -f rsync-server

# 查看客户端日志（同步过程）
docker compose logs -f rsync-client
```

### 3. 测试同步

```bash
# 进入客户端容器
docker compose exec rsync-client bash

# 创建测试文件
echo "Test File $(date)" > /data/source/test-$(date +%s).txt

# 查看客户端日志，应该会自动同步
exit

# 验证服务端数据
docker compose exec rsync-server ls -lh /data/backup/
```

### 4. 停止服务

```bash
docker compose down

# 删除所有数据（包括 Volume）
docker compose down --volumes
```

## 📊 网络架构

```
Docker Bridge: rsync-net (10.0.5.0/24)
├── 10.0.5.1   - 网关
├── 10.0.5.30  - rsync-client
│   ├── Volume: client-data → /data/source
│   └── Volume: shared-config → /shared-config
└── 10.0.5.31  - rsync-server
    ├── Volume: server-data → /data/backup
    ├── Volume: shared-config → /shared-config
    └── Port: 873 → 主机 873
```

## ⚙️ 环境变量配置

### 服务端 (rsync-server)

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `RSYNC_USER` | rsyncuser | 认证用户名 |
| `RSYNC_PASSWORD` | rsyncpass123 | 认证密码 |
| `RSYNC_MODULE` | backup | 模块名称 |
| `BACKUP_PATH` | /data/backup | 备份路径 |

### 客户端 (rsync-client)

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `RSYNC_SERVER` | 10.0.5.31 | 服务器地址 |
| `RSYNC_MODULE` | backup | 模块名称 |
| `RSYNC_USER` | rsyncuser | 认证用户名 |
| `SOURCE_DIR` | /data/source | 源目录 |
| `SYNC_INTERVAL` | 5 | 同步间隔（秒，仅无 inotify 时使用） |

## 📁 项目结构

```
04.auto-rsync-service/
├── compose.yml                    # Docker Compose 配置
├── README.md                      # 本文件
├── compose.md                     # 详细使用文档
└── scripts/
    ├── auto-rsync-server.sh       # 服务端自动配置脚本
    └── auto-rsync-client.sh       # 客户端自动同步脚本
```

## 🔑 核心脚本说明

### auto-rsync-server.sh（服务端）

**功能**：
1. 自动创建 rsyncd.conf 配置文件（包含 uid/gid）
2. 自动创建 rsyncd.secrets 密码文件（权限 600）
3. 将密码共享到 /shared-config/rsync.pass
4. 启动 rsync daemon 服务

**关键配置**：
- `uid = root` / `gid = root`（避免权限问题）
- `use chroot = no`
- `hosts allow = 10.0.5.0/24`（网段限制）
- `transfer logging = yes`（启用日志）

### auto-rsync-client.sh（客户端）

**功能**：
1. 等待服务端共享密码文件（最多 30 次重试）
2. 等待 rsync daemon 服务启动（nc -z 探测）
3. 测试连接并创建测试数据
4. 使用 inotify 监控文件变化（或定时同步）
5. 自动执行 rsync 同步

**同步命令**：
```bash
rsync -avz --delete --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.31/backup/
```

## 🔧 自定义配置

### 修改密码

编辑 `compose.yml`：

```yaml
services:
  rsync-server:
    environment:
      - RSYNC_PASSWORD=your-secure-password  # 修改密码
```

### 修改同步选项

编辑 `scripts/auto-rsync-client.sh`，修改 rsync 命令：

```bash
# 示例：不删除目标端多余文件
rsync -avz --password-file=${PASSWORD_FILE} \
    ${SOURCE_DIR}/ rsync://${RSYNC_USER}@${RSYNC_SERVER}/${RSYNC_MODULE}/

# 示例：排除某些文件
rsync -avz --delete --exclude='*.log' --exclude='.git/' \
    --password-file=${PASSWORD_FILE} \
    ${SOURCE_DIR}/ rsync://${RSYNC_USER}@${RSYNC_SERVER}/${RSYNC_MODULE}/
```

### 修改网段

编辑 `compose.yml` 和 `scripts/auto-rsync-server.sh`：

```yaml
# compose.yml
networks:
  rsync-net:
    ipam:
      config:
        - subnet: 192.168.100.0/24  # 修改网段
```

```bash
# auto-rsync-server.sh
hosts allow = 192.168.100.0/24  # 修改网段
```

## 📈 监控与维护

### 查看同步状态

```bash
# 实时查看客户端同步日志
docker compose logs -f rsync-client | grep "同步"

# 查看服务端传输日志
docker compose exec rsync-server tail -f /var/log/rsyncd.log
```

### 检查服务健康

```bash
# 检查 rsync daemon 进程
docker compose exec rsync-server ps aux | grep rsync

# 检查端口监听
docker compose exec rsync-server ss -tlnp | grep 873

# 列出模块
docker compose exec rsync-client rsync rsync://10.0.5.31/
```

### 手动触发同步

```bash
# 进入客户端容器
docker compose exec rsync-client bash

# 手动执行同步
rsync -avz --delete --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.31/backup/
```

## ⚠️ 注意事项

### 安全性

1. **明文传输**：Daemon 模式不加密，仅适用于内网
2. **密码安全**：生产环境应使用强密码
3. **网络隔离**：使用 `hosts allow` 限制访问来源
4. **互联网环境**：建议使用 02.auto-rsync_inotify（SSH 模式）

### 性能优化

1. **网络带宽**：大文件同步会占用带宽
2. **inotify 限制**：大量文件可能触发限制（可调整内核参数）
3. **同步间隔**：根据实际需求调整 `SYNC_INTERVAL`
4. **压缩选项**：已压缩文件使用 `dont compress` 排除

### 数据安全

1. **--delete 选项**：会删除目标端多余文件，请谨慎使用
2. **备份策略**：建议结合增量快照（--link-dest）
3. **测试环境**：生产部署前充分测试
4. **监控告警**：生产环境应配置监控和告警

## 🔗 相关文档

- `../rsync_inotify.md` - Rsync 命令选项完整参考
- `../03.manual-rsync-service/compose.md` - Daemon 模式手工配置文档
- `../02.auto-rsync_inotify/README.md` - SSH 模式自动化方案
- `compose.md` - 本项目详细使用文档

## 📚 学习路径

**推荐顺序**：
1. 先学习 `03.manual-rsync-service`（理解 Daemon 模式原理）
2. 再使用本项目（生产环境自动化方案）
3. 对比 `02.auto-rsync_inotify`（理解 SSH vs Daemon）

## 🎓 总结

本项目将 Rsync Daemon 模式**完全自动化**，适合：

✅ 内网环境的实时文件同步
✅ 高性能备份场景（无 SSH 加密开销）
✅ 容器化部署的备份服务
✅ 需要快速部署的临时备份方案

**关键优势**：零配置、自动化、生产就绪
