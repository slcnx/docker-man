# Rsync 服务模式（手工配置）

## 📋 项目说明

本项目提供 **Rsync 守护进程（Daemon）模式** 的手工配置学习环境，用于理解 Rsync 服务的工作原理和配置方法。

## 🎯 学习目标

- 理解 Rsync Daemon 模式与 SSH 模式的区别
- 掌握 rsyncd.conf 配置文件的编写
- 学习基于用户名/密码的认证机制
- 理解模块（module）的概念和配置
- 掌握服务端和客户端的完整配置流程

## 🔄 与其他项目的对比

| 项目 | 传输模式 | 认证方式 | 端口 | 自动化程度 | 适用场景 |
|------|---------|---------|------|-----------|---------|
| 01.manual-rsync_inotify | SSH | SSH密钥 | 22 | 手工 | 学习SSH模式 |
| 02.auto-rsync_inotify | SSH | SSH密钥 | 22 | 全自动 | 生产环境 |
| **03.manual-rsync-service** | **Daemon** | **用户名/密码** | **873** | **手工** | **学习服务模式** |

## 🏗️ 架构特点

### Daemon 模式优势
- ✅ 独立的 rsync 服务，不依赖 SSH
- ✅ 更轻量级，资源占用少
- ✅ 支持匿名访问或用户认证
- ✅ 可以定义多个共享模块
- ✅ 细粒度的访问控制（IP白名单/黑名单）

### Daemon 模式劣势
- ❌ 默认不加密（端口 873）
- ❌ 密码文件需要严格的权限控制
- ❌ 相比 SSH 模式安全性较低

## 📦 项目结构

```
03.manual-rsync-service/
├── compose.yml          # Docker Compose 配置（最小化）
├── compose.md           # 完整的手工配置文档
└── README.md            # 本文件
```

## 🚀 快速开始

### 1. 启动容器
```bash
cd /root/docker-man/05.realtime-sync/03.manual-rsync-service
docker compose up -d
```

### 2. 按照文档操作
打开 `compose.md` 文档，按照以下顺序完成配置：

1. **第 3 节**：服务端配置
   - 创建 rsyncd.conf 配置文件
   - 创建 rsyncd.secrets 密码文件
   - 启动 rsync daemon 服务

2. **第 4 节**：客户端配置
   - 创建密码文件
   - 测试连接和同步

3. **第 5 节**：深入理解配置选项

4. **第 6 节**：故障排除

## 📊 网络架构

```
┌─────────────────────────────────────────┐
│       rsync-net (10.0.5.0/24)           │
│                                         │
│  ┌──────────────┐    ┌──────────────┐  │
│  │ rsync-client │    │ rsync-server │  │
│  │  10.0.5.20   │───▶│  10.0.5.21   │  │
│  │              │    │   :873       │  │
│  │ /data/source │    │ /data/backup │  │
│  └──────────────┘    └──────────────┘  │
│                                         │
└─────────────────────────────────────────┘
       主机端口映射：873 → rsync-server:873
```

## 🔑 核心配置文件

### 服务端（rsync-server）

**rsyncd.conf** - Rsync 守护进程主配置
```ini
[backup]
    path = /data/backup
    read only = no
    auth users = rsyncuser
    secrets file = /etc/rsync/rsyncd.secrets
```

**rsyncd.secrets** - 用户密码文件（权限必须 600）
```
rsyncuser:rsyncpass123
```

### 客户端（rsync-client）

**rsync.pass** - 客户端密码文件（权限必须 600）
```
rsyncpass123
```

## 📝 核心命令

### 列出服务端模块
```bash
rsync rsync://10.0.5.21/
```

### 同步到服务端
```bash
rsync -avz --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.21/backup/
```

### 从服务端同步
```bash
rsync -avz --password-file=/etc/rsync/rsync.pass \
    rsync://rsyncuser@10.0.5.21/backup/ /data/restore/
```

## ⚠️ 注意事项

1. **密码文件权限**：必须设置为 `chmod 600`，否则 rsync 会拒绝使用
2. **防火墙规则**：确保端口 873 开放
3. **安全性**：生产环境建议使用 SSH 模式或配合 stunnel 加密
4. **IP限制**：使用 `hosts allow` 和 `hosts deny` 限制访问来源

## 🎓 学习建议

1. 先完成 `01.manual-rsync_inotify`（SSH 模式）再学习本项目
2. 对比两种模式的配置差异和适用场景
3. 重点理解 rsyncd.conf 的模块概念
4. 实践多模块配置和不同的访问控制策略
5. 学习后可进一步了解 rsync over stunnel 的加密方案

## 📚 相关文档

- `../rsync_inotify.md` - Rsync 命令选项完整参考
- `../01.manual-rsync_inotify/compose.md` - SSH 模式配置文档
- `../02.auto-rsync_inotify/README.md` - 自动化方案参考

## 🔗 参考链接

- [Rsync 官方文档](https://rsync.samba.org/)
- [rsyncd.conf 手册](https://man7.org/linux/man-pages/man5/rsyncd.conf.5.html)
- [Rsync 安全最佳实践](https://rsync.samba.org/security.html)
