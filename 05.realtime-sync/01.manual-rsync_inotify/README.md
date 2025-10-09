# Rsync + Inotify 实时同步测试环境

## 📖 项目简介

本项目提供基于 Docker Compose 的 **Rsync + Inotify 实时文件同步** 测试环境，用于学习和实践 Linux 文件同步技术。

## 🎯 学习目标

- 理解 Rsync 增量同步原理
- 掌握 Inotify 文件监控机制
- 配置 SSH 免密登录
- 实现实时文件同步
- 编写自动化同步脚本

## 🏗️ 架构

```
┌─────────────────────┐         ┌─────────────────────┐
│   rsync-source      │         │   rsync-backup      │
│   (10.0.5.10)       │         │   (10.0.5.11)       │
│                     │         │                     │
│  ┌──────────────┐   │         │  ┌──────────────┐   │
│  │ inotifywait  │   │         │  │  SSH Server  │   │
│  │   监控变化   │   │         │  │   接收数据   │   │
│  └──────┬───────┘   │         │  └──────────────┘   │
│         │           │         │                     │
│         ↓           │         │                     │
│  ┌──────────────┐   │  rsync  │  ┌──────────────┐   │
│  │    rsync     │───┼────────→│  │ /data/backup │   │
│  │ /data/source │   │  sync   │  │              │   │
│  └──────────────┘   │         │  └──────────────┘   │
└─────────────────────┘         └─────────────────────┘
```

## 🚀 快速开始

### 1. 启动环境

```bash
cd /root/docker-man/05.实时同步/01.manual-rsync_inotify
docker compose up -d
```

### 2. 配置 SSH 免密登录

```bash
# 进入源端容器
docker compose exec -it rsync-source bash

# 生成 SSH 密钥
ssh-keygen -t rsa -b 2048 -N "" -f /root/.ssh/id_rsa

# 查看公钥
cat /root/.ssh/id_rsa.pub
# 复制输出内容

# 在另一个终端进入备份端容器
docker compose exec -it rsync-backup bash

# 安装并启动 SSH 服务
yum install -y openssh-server
ssh-keygen -A
/usr/sbin/sshd

# 配置公钥
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat > /root/.ssh/authorized_keys <<'EOF'
[粘贴源端的公钥]
EOF
chmod 600 /root/.ssh/authorized_keys

# 返回源端测试连接
ssh -o StrictHostKeyChecking=no root@rsync-backup "echo OK"
```

### 3. 测试手动同步

```bash
# 在源端容器中
echo "Test File" > /data/source/test.txt
rsync -avz -e "ssh -o StrictHostKeyChecking=no" /data/source/ root@rsync-backup:/data/backup/

# 在备份端验证
docker compose exec rsync-backup cat /data/backup/test.txt
```

### 4. 启动实时同步

```bash
# 在源端容器中创建同步脚本（见 compose.md）
/usr/local/bin/rsync-inotify.sh
```

## 📚 详细文档

请查看 [compose.md](./compose.md) 获取完整的实践指南。

## 🛠️ 主要技术

- **Rsync**: 增量文件同步工具
- **Inotify**: Linux 内核文件监控机制
- **SSH**: 加密传输协议
- **Docker Compose**: 容器编排

## 📝 注意事项

- 首次使用需要配置 SSH 免密登录
- 确保备份端 SSH 服务运行
- 大量文件监控时注意 inotify 限制
- 生产环境建议使用更完善的同步方案（如 lsyncd）

## 🔗 相关项目

- **04.nfs/01.manual-nfs**: NFS 网络文件系统
- **03.rsyslog**: 日志管理实践

---

**维护者**: docker-man 项目组
**最后更新**: 2025-10-09
