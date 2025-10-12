# Docker Compose Nginx 安装与命令完整实践指南

## 📚 第一部分：文件描述符与 I/O 模型

### 1.1 文件描述符（File Descriptor）详解

#### 1.1.1 什么是文件描述符

**Linux 哲学**：一切皆文件（Everything is a file）

```
文件描述符（FD）的本质
├── 定义：内核为管理已打开文件创建的索引（整数）
├── 作用：指向被打开的文件、Socket、管道等
└── 用途：所有 I/O 操作都通过文件描述符完成

标准文件描述符
├── 0：stdin（标准输入）
├── 1：stdout（标准输出）
└── 2：stderr（标准错误）

用户打开的文件描述符
├── 3, 4, 5, ...：用户打开的文件、Socket 连接
└── 默认限制：1024 个（可调整）
```

#### 1.1.2 文件描述符的关系

| 关系 | 说明 |
|------|------|
| **1 对 1** | 每个文件描述符对应一个打开的文件 |
| **多对 1** | 不同的文件描述符可能指向同一个文件 |
| **跨进程** | 相同的文件可以被不同进程打开 |
| **复用** | 已释放的文件描述符可以被重新占用 |

---

#### 1.1.3 文件描述符的限制

**系统级限制**：

```bash
# 1. 整个系统可打开的文件描述符总数上限
cat /proc/sys/fs/file-max
# 输出：9223372036854775807（理论最大值）

# 2. 单个进程能打开的文件描述符最大数量
cat /proc/sys/fs/nr_open
# 输出：1073741816
```

**进程级限制**：

```bash
# 3. 每个进程的软限制（当前生效的限制）
ulimit -n
# 输出：1024（默认值）

# 4. 每个进程的硬限制（软限制的最大值，需 root 修改）
ulimit -Hn
# 输出：524288
```

**修改限制**：

```bash
# 临时提高软限制
ulimit -n 65535

# 永久修改（编辑 /etc/security/limits.conf）
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf
```

---

#### 1.1.4 文件描述符对 Nginx 的意义

##### 1.1.4.1 管理连接

```
Nginx 的异步非阻塞模型
├── 每个客户端连接占用 1 个文件描述符
├── 事件循环监控文件描述符的状态变化
│   ├── 可读事件：Socket 上有数据到达
│   ├── 可写事件：Socket 缓冲区可写入
│   └── 错误事件：连接异常
└── 高效并发连接管理

示例：
- 10,000 个并发连接 = 需要 10,000 个文件描述符
- 系统默认限制 1024 → 无法处理高并发
- 需要调整：ulimit -n 65535
```

##### 1.1.4.2 性能瓶颈

**问题场景**：

```
高并发场景下的文件描述符耗尽
├── Nginx 无法接受新连接
├── 错误日志：Too many open files
├── 服务性能下降甚至拒绝服务
└── 解决方案：
    ├── 1. 增加系统级限制（/proc/sys/fs/file-max）
    ├── 2. 增加进程级限制（ulimit -n）
    ├── 3. Nginx 配置（worker_rlimit_nofile）
    └── 4. 优化代码，及时关闭不再使用的连接
```

**Nginx 配置优化**：

```nginx
# /data/server/nginx/conf/nginx.conf
worker_rlimit_nofile 65535;  # 每个 Worker 进程最大打开文件数

events {
    worker_connections 10240;  # 每个 Worker 最大连接数
}

# 计算最大并发：
# max_connections = worker_processes × worker_connections
#                 = 4 × 10240
#                 = 40,960
```

---

### 1.2 三种 I/O 管理模式对比

#### 1.2.1 Select 模型

**工作原理**：

```
1. 用户态发起 select 调用
   ↓
2. 拷贝 FD 数组到内核态（用户空间 → 内核空间）
   ↓
3. 内核态遍历检查所有 FD（O(n) 复杂度）
   ↓
4. 标记就绪 FD（修改 Bitmap）
   ↓
5. 拷贝结果回用户态（内核空间 → 用户空间）
   ↓
6. 用户态遍历查找就绪 FD（O(n) 复杂度）
   ↓
7. 处理就绪 FD 的 I/O 操作
```

**数据结构**：

```
FD 集合（Bitmap）
┌───┬───┬───┬───┬───┬───┬───┬───┬─────┬──────┐
│ 0 │ 1 │ 2 │ 3 │ 4 │ 5 │ 6 │ 7 │ ... │ 1023 │
├───┼───┼───┼───┼───┼───┼───┼───┼─────┼──────┤
│ 0 │ 1 │ 0 │ 1 │ 0 │ 0 │ 1 │ 0 │ ... │  0   │
└───┴───┴───┴───┴───┴───┴───┴───┴─────┴──────┘
  ↑   ↑       ↑           ↑
 未就绪 就绪  未就绪      就绪
```

**优缺点**：

| 优点 | 缺点 |
|------|------|
| ✅ 跨平台（几乎所有操作系统支持） | ❌ FD 数量限制（1024 或 2048） |
| ✅ 实现简单 | ❌ 需要两次遍历（内核 + 用户） |
| | ❌ 需要两次数据拷贝（用户 ↔ 内核） |
| | ❌ 时间复杂度 O(n) |

---

#### 1.2.2 Poll 模型

**工作原理**：

```
与 Select 类似，但改进了数据结构：
├── 使用 pollfd 结构体数组（链表存储）
├── 突破 FD 数量限制（无硬编码上限）
└── 支持更明确的事件类型
    ├── POLLIN：可读
    ├── POLLOUT：可写
    ├── POLLERR：错误
    ├── POLLHUP：挂起
    └── POLLNVAL：无效

特性：
- 水平触发（Level Triggered）
- 如果 FD 未被处理，下次 poll 会再次报告
```

**优缺点**：

| 优点 | 缺点 |
|------|------|
| ✅ 无 FD 数量硬编码限制 | ❌ 仍需遍历所有 FD（O(n)） |
| ✅ 事件类型更清晰 | ❌ 仍需两次数据拷贝 |
| ✅ 水平触发（不会丢失事件） | ❌ 高并发时性能不佳 |

---

#### 1.2.3 Epoll 模型（Linux 推荐）

**工作原理**：

```
用户空间
├── epoll_create()
│   └── 在内核创建 epoll 实例
│       ├── 红黑树（rbr）：管理所有监控的 FD
│       ├── 就绪链表（rdllist）：存放就绪的 FD
│       └── 等待队列（wq）：存储等待事件的进程
│
├── epoll_ctl()
│   └── 添加/修改/删除 FD
│       └── FD 信息添加到红黑树
│
└── epoll_wait()
    └── 等待事件
        ├── 检查就绪链表（rdllist）
        ├── 如果有就绪 FD → 返回事件信息
        └── 如果无就绪 FD → 进程休眠，等待事件

内核空间（数据到达时）
├── Socket 接收到数据 → 触发软中断
├── 在红黑树（rbr）中找到对应的 FD
├── 将 FD 插入就绪链表（rdllist）
├── 检查等待队列（wq）
└── 唤醒等待的进程 → 进程从 rdllist 获取就绪 FD
```

**优势**：

| 特性 | 说明 | 优势 |
|------|------|------|
| **事件通知** | 只返回就绪的 FD | 时间复杂度 O(1) |
| **无 FD 限制** | 理论上可监控数百万连接 | 适合高并发 |
| **无数据拷贝** | 使用 mmap 内存映射 | 避免用户态和内核态拷贝 |
| **边缘触发** | 支持 ET 和 LT 两种模式 | 更高效 |

---

#### 1.2.4 三种模型对比

| 对比项 | select | poll | epoll |
|-------|--------|------|-------|
| **操作方式** | 遍历 | 遍历 | 回调 |
| **底层实现** | 数组（Bitmap） | 链表 | 红黑树 + 链表 |
| **时间复杂度** | O(n) | O(n) | O(1) |
| **最大连接数** | 1024（x86）/2048（x64） | 无上限 | 无上限 |
| **FD 拷贝** | 每次调用都拷贝 | 每次调用都拷贝 | 只在 epoll_ctl 时拷贝一次 |
| **平台支持** | ✅ 跨平台 | ✅ 跨平台 | ⚠️ 仅 Linux |

---

### 1.3 Nginx 为什么选择 Epoll

**性能对比**：

```
场景：10,000 个并发连接，其中 100 个活跃

Select/Poll：
├── 遍历 10,000 个 FD
├── 每次调用都拷贝 10,000 个 FD
├── 时间复杂度：O(10,000)
└── 性能：❌ 差

Epoll：
├── 只通知 100 个就绪 FD
├── 无需拷贝 FD 集合
├── 时间复杂度：O(1)
└── 性能：✅ 优秀
```

**Nginx 配置**：

```nginx
events {
    use epoll;                 # Linux 下默认使用 epoll
    worker_connections 10240;  # 每个 Worker 最大连接数
}
```

---

## 🚀 第二部分：Nginx 安装实践

### 2.1 安装方式对比

| 安装方式 | 优点 | 缺点 | 适用场景 |
|---------|------|------|---------|
| **二进制安装（apt/yum）** | ✅ 简单快速<br>✅ 自动管理依赖<br>✅ 系统集成好 | ❌ 版本可能较旧<br>❌ 功能模块固定 | 快速部署、标准功能需求 |
| **源码编译安装** | ✅ 最新版本<br>✅ 自定义模块<br>✅ 性能优化 | ❌ 编译耗时<br>❌ 需要手动配置 | 生产环境、特殊功能需求 |

---

### 2.2 Ubuntu 二进制安装（apt）

> **⚠️ 容器环境说明**：
> 本 Docker 容器已预装 Nginx（从源码编译），**无需执行此节的安装命令**。
> 以下内容仅供学习参考，了解传统环境中的二进制安装方式。

#### 2.2.1 查看可用版本（参考）

```bash
apt list nginx -a

# 输出示例：
# nginx/noble-updates,noble-security,now 1.24.0-2ubuntu7.1 amd64 [已安装]
# nginx/noble 1.24.0-2ubuntu7 amd64
```

#### 2.2.2 安装 Nginx（参考，容器已完成）

```bash
# 基础安装（仅供参考，容器已预装）
# apt install nginx -y

# 推荐安装（包含完整功能）（仅供参考）
# apt install nginx nginx-core fcgiwrap nginx-doc -y
```

**安装的软件包**：
- **nginx**：主程序
- **nginx-core**：核心模块
- **nginx-common**：公共文件（自动安装）
- **fcgiwrap**：FastCGI 支持
- **nginx-doc**：文档

#### 2.2.3 目录结构（传统安装路径）

```bash
# ⚠️ 注意：本容器使用的是源码编译路径 /data/server/nginx/
# 以下是传统二进制安装的目录结构，仅供参考

# 配置文件目录（传统路径）
/etc/nginx/
├── conf.d/                    # 自定义配置
├── sites-available/           # 可用站点配置
├── sites-enabled/             # 已启用站点配置（软链接）
├── modules-available/         # 可用模块
├── modules-enabled/           # 已启用模块
├── snippets/                  # 配置片段
├── nginx.conf                 # 主配置文件
├── mime.types                 # MIME 类型定义
├── fastcgi_params             # FastCGI 参数
└── proxy_params               # 代理参数

# 默认网站根目录（传统路径）
/var/www/html/
├── index.html                 # 默认首页
└── index.nginx-debian.html    # Nginx 欢迎页

# 日志目录（传统路径）
/var/log/nginx/
├── access.log                 # 访问日志
└── error.log                  # 错误日志

# 二进制文件（传统路径）
/usr/sbin/nginx                # Nginx 可执行文件
```

#### 2.2.4 启动服务（容器环境已调整）

```bash
# ⚠️ 容器环境中不使用 systemctl，使用直接命令

# 查看 Nginx 进程状态
ps aux | grep nginx

# 查看监听端口
netstat -tunlp | grep nginx
# 输出：
# tcp  0  0  0.0.0.0:80  0.0.0.0:*  LISTEN  5516/nginx: master
# tcp6 0  0  :::80       :::*       LISTEN  5516/nginx: master
```

#### 2.2.5 查看版本信息

```bash
nginx -v
# 输出：nginx version: nginx/1.26.2

nginx -V
# 输出：包含编译参数的完整信息
```

---

### 2.3 Rocky9 二进制安装（yum）

> **⚠️ 容器环境说明**：
> 本 Docker 容器已预装 Nginx（从源码编译），**无需执行此节的安装命令**。
> 以下内容仅供学习参考，了解传统环境中的二进制安装方式。

#### 2.3.1 查看可用版本（参考）

```bash
yum list nginx
# 输出：nginx.x86_64  1:1.20.1-16.el9_4.1
```

#### 2.3.2 安装 Nginx（参考，容器已完成）

```bash
# 仅供参考，容器已预装
# yum install nginx nginx-core -y
```

**自动安装的依赖包**：
- **nginx-core**
- **nginx-filesystem**
- **rocky-logos-httpd**

#### 2.3.3 目录结构（传统安装路径）

```bash
# ⚠️ 注意：本容器使用的是源码编译路径 /data/server/nginx/
# 以下是传统二进制安装的目录结构，仅供参考

# 配置文件目录（传统路径）
/etc/nginx/
├── conf.d/                    # 自定义配置
├── default.d/                 # 默认配置
├── nginx.conf                 # 主配置文件
├── mime.types                 # MIME 类型
├── fastcgi_params             # FastCGI 参数
└── ...

# 默认网站根目录（传统路径）
/usr/share/nginx/html/
├── index.html                 # 默认首页
├── 404.html                   # 404 错误页
├── 50x.html                   # 50x 错误页
└── nginx-logo.png             # Logo

# 日志目录（传统路径）
/var/log/nginx/
├── access.log
└── error.log
```

#### 2.3.4 启动服务（容器环境已调整）

```bash
# ⚠️ 容器环境中不使用 systemctl，使用直接命令

# 查看 Nginx 进程状态
ps aux | grep nginx

netstat -tunlp | grep nginx
# 输出：
# tcp  0  0  0.0.0.0:80  0.0.0.0:*  LISTEN  2975/nginx: master
```

---

### 2.4 Ubuntu 源码编译安装

> **⚠️ 容器环境说明**：
> 本 Docker 容器在构建时**已完成源码编译安装**，Nginx 已安装在 `/data/server/nginx/`。
> 以下内容展示编译过程，帮助理解源码编译的完整步骤。

#### 2.4.1 编译环境准备（已完成）

**第一组：基础编译工具**

```bash
# 容器已安装，仅供参考
apt install -y \
    build-essential \
    gcc \
    g++ \
    libc6 \
    libc6-dev \
    libpcre3 \
    libpcre3-dev \
    libssl-dev \
    libsystemd-dev \
    zlib1g-dev
```

**第二组：扩展功能模块依赖**（可选，用于支持更多功能）

```bash
# 容器已安装，仅供参考
apt install -y \
    libxml2 \
    libxml2-dev \
    libxslt1-dev \
    php-gd \
    libgd-dev \
    geoip-database \
    libgeoip-dev
```

#### 2.4.2 创建运行用户（已完成）

```bash
# 容器已创建，仅供参考
useradd -r -s /usr/sbin/nologin nginx
```

#### 2.4.3 下载源码（已完成）

```bash
# 容器构建时已下载，仅供参考
cd /tmp
wget https://nginx.org/download/nginx-1.26.2.tar.gz
tar xzf nginx-1.26.2.tar.gz
cd nginx-1.26.2/
```

#### 2.4.4 配置编译选项（已完成）

```bash
# 容器构建时已配置，仅供参考
./configure \
    --prefix=/data/server/nginx \
    --user=nginx \
    --group=nginx \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_stub_status_module \
    --with-http_gzip_static_module \
    --with-pcre \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module
```

**编译选项说明**：

| 选项 | 说明 |
|------|------|
| `--prefix` | 安装目录 |
| `--user/--group` | 运行用户/组 |
| `--with-http_ssl_module` | 启用 HTTPS 支持 |
| `--with-http_v2_module` | 启用 HTTP/2 |
| `--with-http_realip_module` | 获取真实客户端 IP |
| `--with-http_stub_status_module` | 启用状态监控页 |
| `--with-http_gzip_static_module` | 静态文件压缩 |
| `--with-stream` | 启用四层代理（TCP/UDP） |
| `--with-stream_ssl_module` | 四层代理 SSL 支持 |

#### 2.4.5 编译并安装（已完成）

```bash
# 容器构建时已编译，仅供参考
make -j$(nproc)
make install
```

**注意**：编译过程需要 1-2 分钟。

#### 2.4.6 目录结构（容器环境）

```bash
# ✅ 容器中的实际目录结构
ls -l /data/server/nginx/
# 输出：
# drwxr-xr-x 2 nginx nginx 4096 conf/   # 配置文件
# drwxr-xr-x 2 nginx nginx 4096 html/   # 网站根目录
# drwxr-xr-x 2 nginx nginx 4096 logs/   # 日志目录
# drwxr-xr-x 2 nginx nginx 4096 run/    # PID 文件目录
# drwxr-xr-x 2 nginx nginx 4096 sbin/   # 可执行文件
```

#### 2.4.7 环境配置（已完成）

```bash
# 容器已配置，仅供参考

# 1. 修改目录属主（已完成）
# chown -R nginx:nginx /data/server/nginx/

# 2. 创建软链接（已完成）
# ln -s /data/server/nginx/sbin/nginx /usr/local/bin/nginx

# 3. 验证版本（可直接执行）
nginx -v
# 输出：nginx version: nginx/1.26.2

# 4. PID 目录（已创建）
# mkdir -p /data/server/nginx/run
```

#### 2.4.8 创建 systemd 服务文件（容器不适用）

> **⚠️ 容器环境说明**：
> Docker 容器环境中**不使用 systemd**，直接使用 nginx 命令管理服务。
> 以下内容仅供传统虚拟机/物理机环境参考。

**步骤 1：创建 PID 目录（容器已完成）**

```bash
# 容器已创建，仅供参考
# mkdir -p /data/server/nginx/run
# chown -R nginx:nginx /data/server/nginx/run
```

**步骤 2：修改配置文件（容器已完成）**

```bash
# 容器配置文件已添加 PID 路径
# vim /data/server/nginx/conf/nginx.conf
# 第一行：pid /data/server/nginx/run/nginx.pid;
```

**步骤 3：创建服务文件（仅供参考）**

```bash
# 仅供传统环境参考，容器不使用
# cat > /usr/lib/systemd/system/nginx.service <<'EOF'
# [Unit]
# Description=nginx - high performance web server
# Documentation=http://nginx.org/en/docs/
# After=network-online.target remote-fs.target nss-lookup.target
# Wants=network-online.target
#
# [Service]
# Type=forking
# PIDFile=/data/server/nginx/run/nginx.pid
# ExecStart=/data/server/nginx/sbin/nginx -c /data/server/nginx/conf/nginx.conf
# ExecReload=/bin/kill -s HUP $MAINPID
# ExecStop=/bin/kill -s TERM $MAINPID
# LimitNOFILE=100000
#
# [Install]
# WantedBy=multi-user.target
# EOF
```

**信号说明**：

| 信号 | 作用 |
|------|------|
| **SIGHUP (1)** | 重新加载配置文件 |
| **SIGTERM (15)** | 优雅停止（推荐） |
| **SIGKILL (9)** | 强制终止（不推荐） |

**步骤 4：启动服务（容器环境调整）**

```bash
# ⚠️ 容器环境中使用直接命令，不使用 systemctl

# 启动 Nginx
nginx

# 查看进程状态
ps aux | grep nginx

# 检查监听端口
netstat -tunlp | grep nginx
# 输出：
# tcp  0  0  0.0.0.0:80  0.0.0.0:*  LISTEN  27985/nginx: master
```

---

### 2.5 Rocky9 源码编译安装

> **⚠️ 容器环境说明**：
> 本 Docker 容器在构建时**已完成源码编译安装**，Nginx 已安装在 `/data/server/nginx/`。
> 以下内容展示编译过程，帮助理解源码编译的完整步骤。

#### 2.5.1 编译环境准备（已完成）

```bash
# 容器已安装，仅供参考

# 基础编译工具
# yum install -y gcc make gcc-c++ glibc glibc-devel \
#     pcre pcre-devel openssl openssl-devel \
#     systemd-devel zlib-devel

# 扩展功能模块依赖（可选）
# yum install -y libxml2 libxml2-devel libxslt \
#     libxslt-devel php-gd gd-devel
```

#### 2.5.2 创建用户并下载源码（已完成）

```bash
# 容器构建时已完成，仅供参考

# 创建用户
# useradd -r -s /usr/sbin/nologin nginx

# 创建目录并下载
# mkdir -p /softs && cd /softs
# wget https://nginx.org/download/nginx-1.26.2.tar.gz
# tar xzf nginx-1.26.2.tar.gz
# cd nginx-1.26.2/
```

#### 2.5.3 编译安装（已完成）

```bash
# 容器构建时已编译，仅供参考

# 配置
# ./configure \
#     --prefix=/data/server/nginx \
#     --user=nginx \
#     --group=nginx \
#     --with-http_ssl_module \
#     --with-http_v2_module \
#     --with-http_realip_module \
#     --with-http_stub_status_module \
#     --with-http_gzip_static_module \
#     --with-pcre \
#     --with-stream \
#     --with-stream_ssl_module \
#     --with-stream_realip_module

# 编译
# make

# 安装
# make install

# 修改权限
# chown -R nginx:nginx /data/server/nginx
```

#### 2.5.4 启动服务（容器环境）

```bash
# ✅ 容器中可直接使用以下命令

# 启动 Nginx
nginx
# 或使用完整路径
/data/server/nginx/sbin/nginx

# 验证版本
nginx -V

# 测试访问
curl http://localhost/
```

#### 2.5.5 配置环境变量（已完成）

```bash
# 容器已配置软链接，可直接使用 nginx 命令

# 验证命令可用性
which nginx
# 输出：/usr/local/bin/nginx
```

#### 2.5.6 创建 systemd 服务（容器不适用）

> **⚠️ 容器环境说明**：
> Docker 容器环境中**不使用 systemd**，直接使用 nginx 命令管理服务。
> 参考 2.4.8 节了解 systemd 服务配置（仅供传统环境参考）。

#### 2.5.7 常见问题排查

##### 问题 1：配置语法错误

```bash
# 测试配置
nginx -t
# 错误示例：
# nginx: [emerg] unexpected "}" in /data/server/nginx/conf/nginx.conf:10
```

##### 问题 2：权限问题

```bash
chown -R nginx:nginx /data/server/nginx/run
chmod +x /data/server/nginx/sbin/nginx
```

##### 问题 3：SELinux 阻止

```bash
# 查看状态
sestatus

# 临时禁用
setenforce 0

# 永久禁用
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
```

##### 问题 4：防火墙阻止（容器不适用）

```bash
# ⚠️ 容器环境无防火墙，以下仅供传统环境参考

# 开放端口
# firewall-cmd --permanent --add-service=http
# firewall-cmd --permanent --add-service=https
# firewall-cmd --reload

# 或直接禁用
# systemctl disable --now firewalld
```

---

## 💻 第三部分：Nginx 命令详解

### 3.1 命令帮助

```bash
nginx -h

# 输出：
# nginx version: nginx/1.24.0 (Ubuntu)
# Usage: nginx [-?hvVtTq] [-s signal] [-p prefix]
#              [-e filename] [-c filename] [-g directives]
```

### 3.2 常用选项

| 选项 | 说明 | 示例 |
|------|------|------|
| `-v` | 显示版本信息 | `nginx -v` |
| `-V` | 显示版本信息和编译参数 | `nginx -V` |
| `-t` | 测试配置文件语法 | `nginx -t` |
| `-T` | 测试并输出配置文件内容 | `nginx -T` |
| `-q` | 测试时禁止非错误消息 | `nginx -t -q` |
| `-s signal` | 发送信号 | `nginx -s reload` |
| `-p prefix` | 指定运行目录 | `nginx -p /tmp/nginx` |
| `-c filename` | 指定配置文件 | `nginx -c /data/server/nginx/conf/nginx.conf` |
| `-g directives` | 指定全局配置项 | `nginx -g "worker_processes 4;"` |

### 3.3 信号管理

| 信号 | 命令 | 作用 |
|------|------|------|
| **stop** | `nginx -s stop` | 立即停止（SIGTERM/SIGINT） |
| **quit** | `nginx -s quit` | 优雅退出（SIGQUIT） |
| **reload** | `nginx -s reload` | 重新加载配置（SIGHUP） |
| **reopen** | `nginx -s reopen` | 重新打开日志文件（SIGUSR1） |

### 3.4 配置文件测试

```bash
# 测试配置文件语法
nginx -t

# 输出：
# nginx: the configuration file /data/server/nginx/conf/nginx.conf syntax is ok
# nginx: configuration file /data/server/nginx/conf/nginx.conf test is successful

# 仅输出错误信息
nginx -t -q
echo $?  # 输出 0 表示成功
```

### 3.5 命令行指定配置

```bash
# 启动时指定 Worker 进程数量
nginx -g "worker_processes 4;"

# 禁用守护进程模式（前台运行）
nginx -g "daemon off;"

# 查看进程
ps aux | grep nginx
```

### 3.6 信号测试：stop vs quit

#### 3.6.1 准备测试文件

```bash
# 创建 100MB 测试文件
dd if=/dev/zero of=/data/server/nginx/html/test.img bs=1M count=100
```

#### 3.6.2 测试 stop 信号（立即停止）

```bash
# 客户端限速下载（每秒 1MB）
wget --limit-rate=1024000 http://localhost/test.img

# 服务端发送 stop 信号
nginx -s stop

# 结果：客户端下载立即中断
# 输出：连接关闭。重试中。
```

#### 3.6.3 测试 quit 信号（优雅退出）

```bash
# 客户端限速下载
wget --limit-rate=1024000 http://localhost/test.img

# 服务端发送 quit 信号
nginx -s quit

# 查看进程
ps aux | grep nginx
# 输出：
# nginx: worker process is shutting down

# 结果：
# - 下载继续完成
# - Worker 进程等待请求完成后退出
# - 无法建立新连接
```

---

## 🌐 第四部分：Docker 环境说明

### 4.1 网络拓扑

```
Docker Bridge 网络：nginx-net (10.0.7.0/24)
├── 10.0.7.1   - 网关
├── 10.0.7.20  - nginx-ubuntu-compile（Ubuntu 源码编译）
└── 10.0.7.21  - nginx-rocky-compile（Rocky 源码编译）
```

### 4.2 Docker Compose 配置说明

```yaml
version: '3.8'

services:
  # Ubuntu 源码编译版本
  nginx-ubuntu-compile:
    container_name: nginx-ubuntu-compile
    hostname: nginx-ubuntu-compile
    build:
      context: ..                          # 构建上下文（父目录）
      dockerfile: Dockerfile.ubuntu-compile  # Ubuntu 编译 Dockerfile
    networks:
      nginx-net:
        ipv4_address: 10.0.7.20
    ports:
      - "8080:80"                          # 端口映射
    command: tail -f /dev/null             # 保持容器运行
    tty: true
    stdin_open: true

  # Rocky 源码编译版本
  nginx-rocky-compile:
    container_name: nginx-rocky-compile
    hostname: nginx-rocky-compile
    build:
      context: ..
      dockerfile: Dockerfile.rocky-compile  # Rocky 编译 Dockerfile
    networks:
      nginx-net:
        ipv4_address: 10.0.7.21
    ports:
      - "8081:80"
    command: tail -f /dev/null
    tty: true
    stdin_open: true

networks:
  nginx-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.7.0/24
          gateway: 10.0.7.1
```

---

## 🚀 第五部分：实践演示

### 5.1 启动环境

```bash
# 1. 进入项目目录
cd /home/www/docker-man/07.nginx/02.manual-install

# 2. 构建镜像并启动容器
docker compose up -d --build

# 3. 查看容器状态
docker compose ps

# 4. 查看镜像
docker images | grep nginx

# 5. 查看网络
docker network inspect 02manual-install_nginx-net
```

### 5.2 进入 Ubuntu 容器

```bash
docker compose exec -it nginx-ubuntu-compile bash
```

#### 5.2.1 验证 Nginx 安装

```bash
# 查看版本
nginx -v

# 查看完整编译参数
nginx -V

# 查看目录结构
ls -l /data/server/nginx/

# 启动 Nginx
nginx

# 查看进程
ps aux | grep nginx

# 测试访问
curl http://localhost
```

#### 5.2.2 测试命令

```bash
# 测试配置文件
nginx -t

# 重新加载配置
nginx -s reload

# 查看状态（需要配置 stub_status）
curl http://localhost/nginx_status
```

### 5.3 进入 Rocky 容器

```bash
docker compose exec -it nginx-rocky-compile bash
```

执行相同的验证步骤（参考 5.2 节）。

### 5.4 宿主机访问测试

```bash
# 访问 Ubuntu 容器的 Nginx
curl http://localhost:8080

# 访问 Rocky 容器的 Nginx
curl http://localhost:8081

# 浏览器访问
# http://localhost:8080
# http://localhost:8081
```

---

## 📊 第六部分：性能对比

### 6.1 文件描述符限制测试

```bash
# 查看当前限制
ulimit -n

# 查看 Nginx 进程的限制
cat /proc/$(pgrep nginx | head -1)/limits | grep "Max open files"
```

### 6.2 I/O 模型验证

```bash
# 查看 Nginx 使用的 I/O 模型
nginx -V 2>&1 | grep epoll

# 查看配置
grep -A 5 "events {" /data/server/nginx/conf/nginx.conf
```

---

## 🧪 第七部分：故障排查

### 7.1 常见错误

#### 错误 1：端口被占用

```bash
# 错误信息
nginx: [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)

# 解决方法
netstat -tunlp | grep :80
kill -9 <PID>
```

#### 错误 2：权限不足

```bash
# 错误信息
nginx: [alert] could not open error log file: open() "/data/server/nginx/logs/error.log" failed (13: Permission denied)

# 解决方法
chown -R nginx:nginx /data/server/nginx/logs/
```

---

## 📋 第八部分：测试检查清单

### 8.1 安装验证

- [ ] 理解二进制安装和源码编译的区别
- [ ] 理解源码编译的完整流程（已在容器中完成）
- [ ] 了解 systemd 服务文件的作用（传统环境）
- [ ] 能够在容器环境中直接使用 nginx 命令

### 8.2 命令掌握

- [ ] 掌握 nginx -t 测试配置
- [ ] 掌握 nginx -s reload 重新加载配置
- [ ] 掌握 nginx -s stop 立即停止
- [ ] 掌握 nginx -s quit 优雅退出
- [ ] 理解 stop 和 quit 信号的区别
- [ ] 能够使用 -g 参数指定配置
- [ ] 能够使用 ps aux | grep nginx 查看进程状态

### 8.3 理论知识

- [ ] 理解文件描述符的概念和限制
- [ ] 掌握 select、poll、epoll 的区别
- [ ] 理解 Nginx 为什么选择 epoll

---

## ❓ 第九部分：常见问题

### Q1: 二进制安装和源码编译该选哪个？

**答**：
- **开发/测试环境**：推荐二进制安装（快速简单）
- **生产环境**：推荐源码编译（最新版本、自定义模块、性能优化）

### Q2: 为什么 epoll 比 select 快？

**答**：
- **select**：每次调用都遍历所有 FD（O(n)），需要多次数据拷贝
- **epoll**：只返回就绪 FD（O(1)），无需重复拷贝，使用 mmap 避免数据拷贝

### Q3: ulimit -n 和 worker_rlimit_nofile 有什么区别？

**答**：
- `ulimit -n`：系统级限制，影响所有进程
- `worker_rlimit_nofile`：Nginx 配置，仅影响 Nginx Worker 进程

---

## 🎓 学习总结

通过本环境的学习，你应该掌握：

### 核心概念

1. **文件描述符**：Linux 文件管理、限制配置、对 Nginx 的影响
2. **I/O 模型**：select、poll、epoll 的工作原理和性能对比
3. **安装方式**：二进制安装 vs 源码编译

### 实践技能

1. **理解安装方式**：apt、yum、源码编译三种方式的区别
2. **命令使用**：测试配置、重新加载、信号管理
3. **容器环境**：理解容器中直接使用 nginx 命令而非 systemctl
4. **路径管理**：熟悉 /data/server/nginx/ 目录结构

---

## 🧹 清理环境

```bash
# 停止容器
docker compose down

# 删除镜像
docker compose down --rmi all
```

---

**完成时间**: 2024-10-12
**文档版本**: v1.0
**维护者**: docker-man 项目组
