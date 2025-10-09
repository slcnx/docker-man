# Docker Compose Rsync Daemon 完整实践指南

## 📚 第一部分：基础知识

### 1.1 什么是 Rsync Daemon 模式

**Rsync Daemon** 是 rsync 的**服务器-客户端模式**，rsync 作为独立的守护进程运行，监听 873 端口，客户端通过 rsync 协议连接。

#### Rsync 两种工作模式对比

| 特性 | SSH 模式 | Daemon 模式 |
|------|---------|------------|
| **传输协议** | SSH (端口 22) | Rsync Protocol (端口 873) |
| **认证方式** | SSH 密钥 / 密码 | 用户名+密码（rsyncd.secrets） |
| **加密** | SSH 加密 | **明文传输**（可用 stunnel 加密） |
| **配置复杂度** | 中（需配置 SSH） | 中（需配置 rsyncd.conf） |
| **性能** | 稍慢（SSH 加密开销） | 更快（无加密开销） |
| **命令格式** | `rsync -e ssh src/ host:/dest/` | `rsync src/ rsync://host/module/` |
| **模块化** | 不支持 | **支持多个共享模块** |
| **访问控制** | SSH 权限 | IP 白名单 + 用户认证 |
| **适用场景** | 互联网、高安全需求 | 内网、性能优先 |

#### Rsync Daemon 的优势

- ✅ **无需 SSH**：不依赖 SSH 服务和密钥配置
- ✅ **模块化管理**：一个服务器可以配置多个共享模块
- ✅ **灵活的权限控制**：每个模块独立配置权限
- ✅ **更高性能**：无 SSH 加密开销
- ✅ **集中管理**：所有配置集中在 rsyncd.conf

#### Rsync Daemon 的劣势

- ⚠️ **明文传输**：数据和密码不加密（可用 stunnel 解决）
- ⚠️ **安全性较低**：不适合互联网环境
- ⚠️ **防火墙穿透**：需要开放 873 端口

---

### 1.2 Rsync Daemon 工作原理

#### 1.2.1 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                       Rsync Client                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  rsync 命令                                            │  │
│  │  rsync -avz /data/source/ rsync://server/module/      │  │
│  └───────────────┬───────────────────────────────────────┘  │
│                  ↓                                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  1. 连接服务器 (端口 873)                              │  │
│  │  2. 发送用户名+密码                                     │  │
│  │  3. 请求访问模块 (module)                              │  │
│  │  4. 接收文件列表                                       │  │
│  │  5. 传输数据（增量、压缩）                              │  │
│  └───────────────┬───────────────────────────────────────┘  │
└──────────────────┼──────────────────────────────────────────┘
                   ↓ TCP 873 端口（rsync 协议）
┌──────────────────┼──────────────────────────────────────────┐
│  ┌───────────────┴───────────────────────────────────────┐  │
│  │  rsync daemon (rsyncd)                                │  │
│  │  - 监听 873 端口                                       │  │
│  │  - 读取 rsyncd.conf 配置                              │  │
│  │  - 验证用户名+密码 (rsyncd.secrets)                    │  │
│  │  - 检查客户端 IP（hosts allow/deny）                   │  │
│  │  - 应用模块权限（read only, uid, gid）                 │  │
│  └───────────────┬───────────────────────────────────────┘  │
│                  ↓                                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  模块目录                                              │  │
│  │  [backup]  → /data/backup  (rw, 需认证)               │  │
│  │  [public]  → /data/public  (ro, 无需认证)             │  │
│  │  [mirror]  → /data/mirror  (rw, 需认证)               │  │
│  └───────────────────────────────────────────────────────┘  │
│                       Rsync Server                          │
└─────────────────────────────────────────────────────────────┘
```

#### 1.2.2 认证流程

```
1. Client → Server: CONNECT (端口 873)
2. Server → Client: WELCOME (服务器欢迎信息)
3. Client → Server: MODULE REQUEST (请求模块名称)
4. Server → Client: AUTH REQUEST (要求认证 / 或直接允许)
5. Client → Server: USERNAME + PASSWORD
6. Server:           验证 rsyncd.secrets 中的密码
7. Server:           检查 hosts allow/deny
8. Server → Client: AUTH SUCCESS (认证成功)
9. Client ← Server: FILE LIST (文件列表)
10. Client ↔ Server: DATA TRANSFER (数据传输)
```

---

### 1.3 配置文件说明

#### 1.3.1 rsyncd.conf（主配置文件）

**位置**：`/etc/rsyncd.conf` 或 `/etc/rsyncd/rsyncd.conf`

**结构**：
```ini
# 全局配置
option = value

# 模块定义
[module_name]
    option = value
    option = value

[another_module]
    option = value
```

#### 1.3.2 rsyncd.secrets（密码文件）

**位置**：自定义（在 rsyncd.conf 中指定）

**格式**：
```
username:password
user1:pass123
user2:pass456
```

**权限要求**：**必须是 600**（仅所有者可读写）

```bash
chmod 600 /etc/rsyncd.secrets
```

#### 1.3.3 rsyncd.motd（欢迎信息）

**位置**：自定义（在 rsyncd.conf 中指定）

**内容示例**：
```
Welcome to Rsync Server
Please contact admin@example.com if you have any questions.
```

---

## 🌐 第二部分：网络架构与环境说明

### 2.1 网络拓扑

```
Docker Bridge 网络：rsync-net (10.0.5.0/24)
├── 10.0.5.1   - 网关（Docker 网桥）
├── 10.0.5.20  - Rsync 客户端（rsync-client）
│   └── Volume: client-data → /data/source
└── 10.0.5.21  - Rsync 服务器（rsync-server）
    ├── Volume: server-data → /data/backup
    └── 监听端口：873
```

### 2.2 Docker Compose 配置说明

```yaml
version: '3.8'

services:
  rsync-client:
    # Rsync 客户端容器
    container_name: rsync-client
    hostname: rsync-client
    networks:
      rsync-net:
        ipv4_address: 10.0.5.20    # 固定 IP
    volumes:
      - client-data:/data/source    # 源数据卷

  rsync-server:
    # Rsync 服务器容器
    container_name: rsync-server
    hostname: rsync-server
    networks:
      rsync-net:
        ipv4_address: 10.0.5.21    # 固定 IP
    volumes:
      - server-data:/data/backup    # 备份数据卷
    ports:
      - "873:873"                   # 暴露 rsync daemon 端口

networks:
  rsync-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.5.0/24
          gateway: 10.0.5.1

volumes:
  client-data:                      # 客户端数据卷
    driver: local
  server-data:                      # 服务器数据卷
    driver: local
```

---

## 🚀 第三部分：服务启动与配置

### 3.1 启动环境

```bash
# 1. 进入项目目录
cd /root/docker-man/05.realtime-sync/03.manual-rsync-service

# 2. 启动所有服务
docker compose up -d

# 3. 检查服务状态
docker compose ps

# 预期输出：
# NAME            IMAGE                  STATUS
# rsync-client    rsync-inotify:latest   Up
# rsync-server    rsync-inotify:latest   Up

# 4. 查看网络配置
docker network inspect 03manual-rsync-service_rsync-net

# 5. 验证 Volume 创建
docker volume ls | grep 03manual-rsync-service
```

---

### 3.2 Rsync Server 配置

#### 3.2.1 进入服务器容器

```bash
docker compose exec -it rsync-server bash
```

#### 3.2.2 创建配置目录

```bash
# 创建配置文件目录
mkdir -p /etc/rsync

# 创建数据目录（已由 Volume 创建）
ls -ld /data/backup
```

#### 3.2.3 创建主配置文件 rsyncd.conf

```bash
cat > /etc/rsync/rsyncd.conf <<'EOF'
# Rsync Daemon 配置文件

# ==================== 全局配置 ====================

# ⚠️ 运行用户和组（重要！）
# 学习环境使用 root，生产环境建议创建专用用户
uid = root
gid = root

# 是否使用 chroot（no 表示不限制访问）
use chroot = no

# 日志文件
log file = /var/log/rsyncd.log

# PID 文件
pid file = /var/run/rsyncd.pid

# 锁文件
lock file = /var/run/rsync.lock

# 监听端口（默认 873）
port = 873

# 监听地址（0.0.0.0 表示所有接口）
address = 0.0.0.0

# 最大连接数
max connections = 10

# 超时时间（秒）
timeout = 600

# 欢迎信息文件
motd file = /etc/rsync/rsyncd.motd


# ==================== 模块定义 ====================

# 模块 1：backup（读写模式，需要认证）
[backup]
    # 模块描述
    comment = Backup Module with Authentication

    # 实际路径
    path = /data/backup

    # 读写权限
    read only = no

    # 列表权限
    list = yes

    # 允许的主机
    hosts allow = 10.0.5.0/24

    # 拒绝的主机
    hosts deny = *

    # 认证用户
    auth users = rsyncuser

    # 密码文件
    secrets file = /etc/rsync/rsyncd.secrets

    # 忽略错误
    ignore errors = no

    # 不压缩的文件类型
    dont compress = *.gz *.tgz *.zip *.z *.rpm *.deb *.bz2


# 模块 2：public（只读模式，无需认证）
[public]
    comment = Public Read-Only Module
    path = /data/public
    read only = yes
    list = yes
    hosts allow = 10.0.5.0/24
    hosts deny = *
EOF

# 查看配置
cat /etc/rsync/rsyncd.conf
```

#### 3.2.4 创建密码文件 rsyncd.secrets

```bash
cat > /etc/rsync/rsyncd.secrets <<'EOF'
# Rsync Daemon 密码文件
# 格式: username:password

rsyncuser:rsyncpass123
backupuser:backup456
EOF

# ⚠️ 重要：设置正确的权限（必须是 600）
chmod 600 /etc/rsync/rsyncd.secrets

# 验证权限
ls -l /etc/rsync/rsyncd.secrets
# 输出应为：-rw------- 1 root root ... rsyncd.secrets
```

#### 3.2.5 创建欢迎信息文件（可选）

```bash
cat > /etc/rsync/rsyncd.motd <<'EOF'
================================================
Welcome to Rsync Backup Server
Contact: admin@example.com
================================================
EOF
```

#### 3.2.6 创建测试数据

```bash
# 创建公共数据目录（用于 public 模块）
mkdir -p /data/public

# 在 backup 模块创建测试文件
echo "Server Test Data" > /data/backup/server-test.txt

# 在 public 模块创建测试文件
echo "Public Data" > /data/public/readme.txt

# 查看目录结构
tree /data/ || find /data/ -type f
```

#### 3.2.7 启动 Rsync Daemon

```bash
# 启动 rsync daemon（前台运行，用于查看日志）
rsync --daemon --no-detach --config=/etc/rsync/rsyncd.conf --log-file=/dev/stderr


# 预期输出：
# （服务启动，监听 873 端口，无错误信息）
```

**⚠️ 注意**：此时终端会被占用，需要新开终端继续操作。

**后台运行方式**（推荐在容器中使用）：

```bash
# 后台运行
rsync --daemon --config=/etc/rsync/rsyncd.conf --log-file=/dev/stderr


# 验证服务运行
ps aux | grep rsync
# 输出应包含：rsync --daemon --config=/etc/rsync/rsyncd.conf

# 检查监听端口
netstat -tlnp | grep 873
# 或
ss -tlnp | grep 873

# 预期输出：
# tcp  0  0  0.0.0.0:873  0.0.0.0:*  LISTEN  123/rsync
```

#### 3.2.8 查看服务日志

```bash
# 查看日志文件
tail -f /var/log/rsyncd.log

# 如果没有日志，检查：
# 1. 配置文件中 log file 路径是否正确
# 2. 目录 /var/log 是否存在
# 3. 是否有客户端连接过
```

---

## 💻 第四部分：Rsync Client 配置

### 4.1 进入客户端容器

**新开终端**（保持服务器端 daemon 运行）：

```bash
docker compose exec -it rsync-client bash
```

### 4.2 创建测试数据

```bash
# 创建测试文件
echo "Client Test File 1" > /data/source/client-test1.txt
echo "Client Test File 2" > /data/source/client-test2.txt

# 创建子目录
mkdir -p /data/source/subdir
echo "Subdir File" > /data/source/subdir/test3.txt

# 查看源目录
tree /data/source/ || find /data/source/ -type f
```

### 4.3 列出服务器模块

```bash
# 列出所有可用模块
rsync rsync://10.0.5.21/

# 预期输出（包含欢迎信息）：
# ================================================
# Welcome to Rsync Backup Server
# Contact: admin@example.com
# ================================================
# backup         Backup Module with Authentication
# public         Public Read-Only Module
```

### 4.4 测试访问 public 模块（无需认证）

```bash
# 列出 public 模块内容
rsync rsync://10.0.5.21/public/

# 预期输出：
# -rw-r--r--  12 2024/10/09 12:00:00 readme.txt

# 下载 public 模块文件
rsync -avz rsync://10.0.5.21/public/ /tmp/public-download/

# 查看下载内容
cat /tmp/public-download/readme.txt
# 输出：Public Data
```

### 4.5 测试访问 backup 模块（需要认证）

#### 4.5.1 直接访问（会提示输入密码）

```bash
# 尝试列出 backup 模块
rsync rsync://rsyncuser@10.0.5.21/backup/

# 提示：
# Password:
# 输入：rsyncpass123

# 成功后输出：
# -rw-r--r--  17 2024/10/09 12:00:00 server-test.txt
```

#### 4.5.2 使用密码文件（自动认证）

```bash
# 1. 创建客户端密码文件（仅包含密码）
mkdir -p /etc/rsync
echo "rsyncpass123" > /etc/rsync/rsync.pass

# 2. 设置正确权限
chmod 600 /etc/rsync/rsync.pass

# 3. 使用密码文件认证
rsync --password-file=/etc/rsync/rsync.pass \
    rsync://rsyncuser@10.0.5.21/backup/

# 无需输入密码，直接输出：
# -rw-r--r--  17 2024/10/09 12:00:00 server-test.txt
```

### 4.6 同步测试

#### 4.6.1 推送数据到服务器

```bash
# 使用密码文件推送数据
rsync -avz --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.21/backup/

# 预期输出：
# sending incremental file list
# ./
# client-test1.txt
# client-test2.txt
# subdir/
# subdir/test3.txt
#
# sent 456 bytes  received 123 bytes  1158.00 bytes/sec
# total size is 67  speedup is 0.12
```

#### 4.6.2 验证同步结果

```bash
# 列出服务器 backup 模块
rsync --password-file=/etc/rsync/rsync.pass \
    rsync://rsyncuser@10.0.5.21/backup/

# 预期输出（包含客户端推送的文件）：
# drwxr-xr-x  4096 2024/10/09 12:05:00 .
# -rw-r--r--    20 2024/10/09 12:05:00 client-test1.txt
# -rw-r--r--    20 2024/10/09 12:05:00 client-test2.txt
# -rw-r--r--    17 2024/10/09 12:00:00 server-test.txt
# drwxr-xr-x  4096 2024/10/09 12:05:00 subdir
```

#### 4.6.3 从服务器拉取数据

```bash
# 拉取服务器数据到本地
rsync -avz --password-file=/etc/rsync/rsync.pass \
    rsync://rsyncuser@10.0.5.21/backup/ /tmp/backup-download/

# 验证下载内容
ls -l /tmp/backup-download/
cat /tmp/backup-download/server-test.txt
```

#### 4.6.4 增量同步测试

```bash
# 修改文件
echo "Modified Content" >> /data/source/client-test1.txt

# 创建新文件
echo "New File" > /data/source/newfile.txt

# 再次同步（仅同步变化）
rsync -avz --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.21/backup/

# 预期输出（仅同步变化的文件）：
# sending incremental file list
# client-test1.txt
# newfile.txt
#
# sent 234 bytes  received 67 bytes  602.00 bytes/sec
```

---

## 📊 第五部分：配置选项详解

### 5.1 全局配置选项

| 选项 | 默认值 | 说明 | 推荐设置 |
|------|--------|------|---------|
| `port` | 873 | 监听端口 | 873（默认）或自定义 |
| `address` | 0.0.0.0 | 监听地址 | 0.0.0.0（所有接口） |
| `log file` | 无 | 日志文件路径 | `/var/log/rsyncd.log` |
| `pid file` | 无 | PID 文件路径 | `/var/run/rsyncd.pid` |
| `lock file` | 无 | 锁文件路径 | `/var/run/rsync.lock` |
| `max connections` | 0（无限制） | 最大并发连接数 | 10-50 |
| `timeout` | 0（无限制） | 超时时间（秒） | 600 |
| `motd file` | 无 | 欢迎信息文件 | `/etc/rsync/rsyncd.motd` |

### 5.2 模块配置选项

#### 5.2.1 基本选项

| 选项 | 默认值 | 说明 | 示例 |
|------|--------|------|------|
| `path` | **必需** | 模块实际路径 | `/data/backup` |
| `comment` | 无 | 模块描述 | `Backup Module` |
| `read only` | yes | 只读模式 | `no`（允许写入） |
| `list` | yes | 是否允许列出文件 | `yes` |

#### 5.2.2 认证选项

| 选项 | 默认值 | 说明 | 示例 |
|------|--------|------|------|
| `auth users` | 无（匿名） | 认证用户列表 | `user1,user2` 或 `user1` |
| `secrets file` | 无 | 密码文件路径 | `/etc/rsync/rsyncd.secrets` |
| `strict modes` | yes | 检查密码文件权限 | `yes`（推荐） |

#### 5.2.3 访问控制

| 选项 | 默认值 | 说明 | 示例 |
|------|--------|------|------|
| `hosts allow` | *（所有） | 允许的主机 | `10.0.5.0/24` |
| `hosts deny` | 无 | 拒绝的主机 | `*`（拒绝其他所有） |

**匹配顺序**：
1. 先检查 `hosts allow`，如果匹配则允许
2. 再检查 `hosts deny`，如果匹配则拒绝
3. 如果都不匹配，默认**允许**

**示例**：
```ini
# 仅允许 10.0.5.0/24 网段
hosts allow = 10.0.5.0/24
hosts deny = *

# 允许多个网段
hosts allow = 10.0.5.0/24 192.168.1.0/24

# 允许特定 IP
hosts allow = 10.0.5.20 10.0.5.21

# 拒绝特定 IP，允许其他
hosts deny = 10.0.5.100
hosts allow = 10.0.5.0/24
```

#### 5.2.4 权限选项

| 选项 | 默认值 | 说明 | 示例 |
|------|--------|------|------|
| `uid` | nobody | 运行 rsync 的用户 UID | `rsync` 或 `1000` |
| `gid` | nobody | 运行 rsync 的组 GID | `rsync` 或 `1000` |
| `fake super` | no | 存储完整文件属性 | `yes`（非 root 环境） |

#### 5.2.5 传输选项

| 选项 | 默认值 | 说明 | 示例 |
|------|--------|------|------|
| `max connections` | 0（继承全局） | 模块最大连接数 | `5` |
| `timeout` | 0（继承全局） | 模块超时时间 | `300` |
| `dont compress` | 无 | 不压缩的文件类型 | `*.gz *.zip *.jpg` |
| `exclude` | 无 | 排除的文件/目录 | `.git/ tmp/ *.log` |
| `refuse options` | 无 | 拒绝的客户端选项 | `delete`（禁止删除） |

#### 5.2.6 日志选项

| 选项 | 默认值 | 说明 | 示例 |
|------|--------|------|------|
| `transfer logging` | no | 记录传输日志 | `yes` |
| `log format` | `%o %h [%a] %m (%u) %f %l` | 日志格式 | `%t %a %m %f %b` |

**日志格式占位符**：

| 占位符 | 说明 | 示例 |
|--------|------|------|
| `%a` | 客户端 IP | `10.0.5.20` |
| `%h` | 客户端主机名 | `rsync-client` |
| `%u` | 认证用户名 | `rsyncuser` |
| `%m` | 模块名 | `backup` |
| `%f` | 文件名 | `test.txt` |
| `%b` | 传输字节数 | `1234` |
| `%t` | 时间 | `2024/10/09 12:00:00` |
| `%o` | 操作类型 | `send` / `recv` |

---

### 5.3 常用配置场景

#### 场景 1：开发测试（完全开放）

```ini
[dev]
    path = /data/dev
    read only = no
    list = yes
    # 无认证
    # 允许所有主机
```

#### 场景 2：生产备份（严格认证）

```ini
[backup]
    path = /data/backup
    read only = no
    list = yes
    auth users = backupuser
    secrets file = /etc/rsync/rsyncd.secrets
    hosts allow = 10.0.5.0/24
    hosts deny = *
    dont compress = *.gz *.tgz *.zip
    transfer logging = yes
```

#### 场景 3：公共只读（文档分发）

```ini
[public]
    path = /data/public
    read only = yes
    list = yes
    hosts allow = 10.0.5.0/24
    hosts deny = *
    # 无认证
```

#### 场景 4：镜像同步（允许删除）

```ini
[mirror]
    path = /data/mirror
    read only = no
    list = yes
    auth users = mirroruser
    secrets file = /etc/rsync/rsyncd.secrets
    hosts allow = 10.0.5.0/24
    hosts deny = *
    # 客户端可以使用 --delete 选项
```

#### 场景 5：多用户不同权限

```ini
# 读写模块
[data-rw]
    path = /data/shared
    read only = no
    auth users = rwuser
    secrets file = /etc/rsync/rsyncd.secrets

# 只读模块（相同路径）
[data-ro]
    path = /data/shared
    read only = yes
    auth users = rouser
    secrets file = /etc/rsync/rsyncd.secrets
```

---

## 🔧 第六部分：故障排除

### 6.1 常见错误

#### 错误 1：@ERROR: auth failed on module backup

```bash
# 错误信息
rsync: @ERROR: auth failed on module backup
rsync error: error starting client-server protocol (code 5) at main.c(1635)

# 原因 1：密码错误
# 解决：检查密码文件内容
cat /etc/rsync/rsyncd.secrets  # 服务器端
cat /etc/rsync/rsync.pass      # 客户端

# 原因 2：密码文件权限错误
# 解决：设置正确权限
chmod 600 /etc/rsync/rsyncd.secrets
chmod 600 /etc/rsync/rsync.pass

# 原因 3：用户名不在 auth users 列表中
# 解决：检查配置文件
cat /etc/rsync/rsyncd.conf | grep -A 10 '\[backup\]'
```

#### 错误 2：@ERROR: Unknown module 'backup'

```bash
# 错误信息
rsync: @ERROR: Unknown module 'backup'

# 原因：模块名拼写错误或不存在
# 解决：列出可用模块
rsync rsync://10.0.5.21/

# 检查配置文件
cat /etc/rsync/rsyncd.conf | grep '^\['
```

#### 错误 3：Connection refused

```bash
# 错误信息
rsync: failed to connect to 10.0.5.21 (10.0.5.21): Connection refused (111)

# 原因：rsync daemon 未启动
# 解决：检查服务状态
ps aux | grep rsync
ss -tlnp | grep 873

# 启动服务
rsync --daemon --config=/etc/rsync/rsyncd.conf
```

#### 错误 4：@ERROR: access denied

```bash
# 错误信息
rsync: @ERROR: access denied to backup from 10.0.5.30 (10.0.5.30)

# 原因：客户端 IP 不在允许列表
# 解决：检查 hosts allow/deny
cat /etc/rsync/rsyncd.conf | grep -A 3 'hosts'

# 修改配置允许该 IP
hosts allow = 10.0.5.0/24
```

#### 错误 5：Permission denied / Operation not permitted

```bash
# 错误信息
rsync: [generator] recv_generator: mkdir "/subdir" (in backup) failed: Permission denied (13)
rsync: [receiver] mkstemp "/.file.xxx" (in backup) failed: Permission denied (13)
rsync: [generator] failed to set times on "/." (in backup): Operation not permitted (1)

# ⚠️ 这是最常见的权限错误！

# 原因：rsyncd.conf 中缺少 uid/gid 配置
# rsync daemon 无法确定运行身份，导致权限混乱

# 解决方案 1（学习环境）：配置为 root 运行
cat >> /etc/rsync/rsyncd.conf <<'EOF'

# 全局配置：运行用户和组
uid = root
gid = root
use chroot = no
EOF

# 重启 rsync daemon
pkill rsync
rsync --daemon --config=/etc/rsync/rsyncd.conf --log-file=/dev/stderr

# 解决方案 2（生产环境）：创建专用用户
useradd -r -s /sbin/nologin rsyncuser
chown -R rsyncuser:rsyncuser /data/backup

# 配置文件设置
cat >> /etc/rsync/rsyncd.conf <<'EOF'

uid = rsyncuser
gid = rsyncuser
use chroot = no
EOF

# 重启服务
pkill rsync
rsync --daemon --config=/etc/rsync/rsyncd.conf
```

#### 错误 6：@ERROR: chdir failed

```bash
# 错误信息
rsync: @ERROR: chdir failed
rsync error: error starting client-server protocol (code 5)

# 原因：path 指定的目录不存在
# 解决：创建目录
mkdir -p /data/backup

# 或修改配置指向正确路径
vim /etc/rsync/rsyncd.conf
```

---

### 6.2 调试技巧

#### 6.2.1 查看服务器日志

```bash
# 实时查看日志
tail -f /var/log/rsyncd.log

# 查看最近 50 行
tail -50 /var/log/rsyncd.log

# 搜索特定错误
grep ERROR /var/log/rsyncd.log
grep 'auth failed' /var/log/rsyncd.log
```

#### 6.2.2 测试配置文件

```bash
# rsync daemon 没有专门的配置测试命令
# 可以尝试启动并查看错误
rsync --daemon --no-detach --config=/etc/rsync/rsyncd.conf

# Ctrl+C 停止后检查是否有错误信息
```

#### 6.2.3 网络连通性测试

```bash
# 检查端口是否可达
telnet 10.0.5.21 873
# 或
nc -zv 10.0.5.21 873

# 检查服务器监听状态
ss -tlnp | grep 873
netstat -tlnp | grep 873
```

#### 6.2.4 权限测试

```bash
# 检查目录权限
ls -ld /data/backup

# 检查文件权限
ls -l /etc/rsync/rsyncd.secrets
# 应该是：-rw------- (600)

# 测试写入权限
touch /data/backup/test-write.txt
```

---

## 🎓 第七部分：学习总结

### 核心知识点

1. **Daemon 模式特点**：
   - 独立服务（端口 873）
   - 用户名+密码认证
   - 模块化配置
   - 无 SSH 依赖

2. **配置文件**：
   - `rsyncd.conf`：主配置（全局 + 模块）
   - `rsyncd.secrets`：密码文件（权限 600）
   - `rsyncd.motd`：欢迎信息（可选）

3. **认证机制**：
   - 服务器：auth users + secrets file
   - 客户端：--password-file 或交互输入

4. **访问控制**：
   - IP 白名单：hosts allow/deny
   - 读写权限：read only
   - 用户映射：uid/gid

### 关键命令

```bash
# 服务器端
rsync --daemon --config=/etc/rsync/rsyncd.conf  # 启动服务
exportfs -v                                      # 查看导出（不适用）
ps aux | grep rsync                              # 检查进程

# 客户端端
rsync rsync://server/                            # 列出模块
rsync rsync://server/module/                     # 列出文件
rsync -avz src/ rsync://user@server/module/      # 推送
rsync -avz rsync://user@server/module/ dest/     # 拉取
rsync --password-file=pass.txt ...               # 使用密码文件
```

### 常见问题解决

| 问题 | 原因 | 解决方法 |
|------|------|----------|
| **Permission denied** | **缺少 uid/gid 配置** | **添加 uid=root gid=root** |
| auth failed | 密码错误或权限错误 | 检查密码、权限 600 |
| Unknown module | 模块不存在 | 列出模块、检查配置 |
| Connection refused | 服务未启动 | 启动 daemon |
| access denied | IP 不在白名单 | 修改 hosts allow |
| chdir failed | 路径不存在 | 创建目录 |

### 最佳实践

- ✅ 密码文件权限必须是 600
- ✅ 使用 hosts allow/deny 限制访问
- ✅ 生产环境使用认证（auth users）
- ✅ 启用传输日志（transfer logging）
- ✅ 合理设置 max connections 和 timeout
- ⚠️ Daemon 模式明文传输，内网使用
- ⚠️ 互联网环境建议使用 SSH 模式或 stunnel 加密

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
**适用环境**: 05.realtime-sync/03.manual-rsync-service
**维护者**: docker-man 项目组
