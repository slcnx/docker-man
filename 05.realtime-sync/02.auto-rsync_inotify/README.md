# 02. 自动化 Rsync + Inotify 实时同步

## 📖 项目简介

本项目是 `01.manual-rsync_inotify` 的**自动化版本**，容器启动时自动配置并运行实时同步服务，无需手动操作。

## 🎯 核心特性

- ✅ **完全自动化**：容器启动自动运行同步脚本
- ✅ **自动配置 SSH**：自动生成密钥、配置免密登录
- ✅ **健康检查**：自动等待服务就绪
- ✅ **批量同步**：5秒间隔批量同步，减少 I/O
- ✅ **彩色日志**：清晰的日志输出，便于监控
- ✅ **环境变量配置**：灵活的配置方式
- ✅ **自动重启**：服务异常自动重启

## 🆚 与 01 版本的区别

| 特性 | 01.manual | 02.auto |
|------|-----------|---------|
| **启动方式** | 手动进入容器执行命令 | 容器自动运行 |
| **SSH 配置** | 手动配置 | 自动配置 |
| **适用场景** | 学习实践、手动控制 | 生产环境、自动化 |
| **操作复杂度** | 高（需多步操作） | 低（一键启动） |
| **日志输出** | 简单 | 彩色、结构化 |

## 🚀 快速开始

### 1. 启动服务

```bash
# 进入项目目录
cd /root/docker-man/05.realtime-sync/02.auto-rsync_inotify

# 首次启动会自动构建镜像（使用上级目录的 rsync_inotify.dockerfile）
docker compose up -d

# 查看日志（观察自动化配置过程）
docker compose logs -f rsync-source

# 查看备份端日志
docker compose logs -f rsync-backup
```

**说明**：
- Docker Compose 会自动使用 `../rsync_inotify.dockerfile` 构建镜像
- 首次启动可能需要 1-2 分钟构建镜像
- 容器启动后会自动完成所有配置，无需手动干预

### 2. 测试同步

```bash
# 创建测试文件
docker compose exec rsync-source bash -c "echo 'Test File' > /data/source/test.txt"

# 查看同步日志（应该在5秒内自动同步）
docker compose logs -f rsync-source

# 验证同步结果
docker compose exec rsync-backup cat /data/backup/test.txt
```

### 3. 停止服务

```bash
docker compose down

# 完全清理（包括数据卷）
docker compose down --volumes
```

## 📁 项目结构

```
02.auto-rsync_inotify/
├── compose.yml              # Docker Compose 配置
├── README.md               # 本文件
├── compose.md              # 详细文档
└── scripts/
    ├── rsync-inotify.sh    # 实时同步脚本
    └── start-sshd.sh       # SSH 服务启动脚本
```

## ⚙️ 环境变量配置

在 `compose.yml` 中可以配置以下环境变量：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `SOURCE_DIR` | 源目录 | `/data/source/` |
| `DEST_HOST` | 目标主机 | `rsync-backup` |
| `DEST_DIR` | 目标目录 | `/data/backup/` |
| `RSYNC_OPTS` | Rsync 选项 | `-avz --delete` |
| `SSH_OPTS` | SSH 选项 | `-o StrictHostKeyChecking=no` |
| `SYNC_INTERVAL` | 同步间隔（秒） | `5` |
| `MAX_RETRIES` | 最大重试次数 | `5` |

## 📊 监控日志

### 查看实时日志

```bash
# 查看源端日志（同步过程）
docker compose logs -f rsync-source

# 查看备份端日志（SSH 服务）
docker compose logs -f rsync-backup
```

### 日志示例

```
[2025-10-09 12:00:00] ==========================================
[2025-10-09 12:00:00] Rsync + Inotify 实时同步服务
[2025-10-09 12:00:00] ==========================================
[2025-10-09 12:00:00] 配置信息：
[2025-10-09 12:00:00]   源目录: /data/source/
[2025-10-09 12:00:00]   目标主机: rsync-backup
[2025-10-09 12:00:00]   目标目录: /data/backup/
[2025-10-09 12:00:00]   Rsync 选项: -avz --delete
[2025-10-09 12:00:00]   同步间隔: 5秒
[2025-10-09 12:00:00] ==========================================
[2025-10-09 12:00:01] 等待 SSH 服务 rsync-backup:22 就绪...
[2025-10-09 12:00:02] SSH 服务已就绪
[2025-10-09 12:00:03] SSH 免密登录配置成功 ✓
[2025-10-09 12:00:04] 开始首次全量同步...
[2025-10-09 12:00:05] 同步成功 (耗时: 1秒) ✓
[2025-10-09 12:00:05] 启动实时监控 /data/source/
[2025-10-09 12:00:05] 服务运行中... (Ctrl+C 停止)
[INFO 2025-10-09 12:01:00] 检测到变化: /data/source/test.txt CLOSE_WRITE,CLOSE
[2025-10-09 12:01:05] 触发批量同步...
[2025-10-09 12:01:06] 同步成功 (耗时: 1秒) ✓
```

## 🔧 故障排查

### 问题 1：服务无法启动

```bash
# 检查服务状态
docker compose ps

# 查看详细日志
docker compose logs

# 重新构建镜像
cd /root/docker-man/05.realtime-sync
docker build -t rsync-inotify:latest -f rsync_inotify.dockerfile .
```

### 问题 2：同步不工作

```bash
# 检查源端日志
docker compose logs rsync-source

# 检查 SSH 连接
docker compose exec rsync-source ssh -o StrictHostKeyChecking=no root@rsync-backup "echo OK"

# 手动触发同步测试
docker compose exec rsync-source rsync -avz /data/source/ root@rsync-backup:/data/backup/
```

### 问题 3：权限问题

```bash
# 检查脚本权限
ls -l scripts/

# 添加执行权限
chmod +x scripts/*.sh
```

## 📚 相关文档

- [详细操作指南](compose.md) - 完整的使用说明
- [Rsync 命令选项](../rsync_inotify.md) - Rsync 选项参考
- [01.manual 版本](../01.manual-rsync_inotify/) - 手动版本对比学习

## 🎓 学习路径

1. **初学者**：先学习 `01.manual-rsync_inotify`，理解原理
2. **进阶**：学习本项目，了解自动化实现
3. **生产**：根据需求调整配置，部署到生产环境

## 💡 生产环境建议

- ✅ 使用持久化存储挂载（而非 Volume）
- ✅ 配置日志轮转避免日志过大
- ✅ 根据网络带宽调整 `SYNC_INTERVAL`
- ✅ 添加监控告警（Prometheus + Grafana）
- ✅ 定期检查备份完整性

## 📝 更新日志

- **2025-10-09**: 初始版本发布

---

**项目路径**: `/root/docker-man/05.realtime-sync/02.auto-rsync_inotify/`
**维护者**: docker-man 项目组
