# Docker Compose Nginx 完整实践指南

## 📚 第一部分：基础知识

### 1.1 什么是 Nginx

Nginx（engine x）是一款**高性能的 HTTP 和反向代理 Web 服务器**，同时也提供了 IMAP/POP3/SMTP 服务。

#### Nginx 的特点

| 特性 | 说明 | 优势 |
|------|------|------|
| **高性能** | 采用事件驱动架构 | 处理大量并发连接 |
| **低资源消耗** | 内存占用小 | 节省服务器成本 |
| **高并发** | 支持 50000+ 并发连接 | 适合高流量网站 |
| **模块化设计** | 功能模块化 | 灵活扩展 |
| **热部署** | 不停机升级 | 零停机时间 |

#### Nginx vs Apache

| 对比项 | Nginx | Apache |
|--------|-------|--------|
| **并发模型** | 事件驱动（epoll） | 进程/线程模型 |
| **内存占用** | 低 | 相对较高 |
| **静态文件** | 非常快 | 较快 |
| **动态内容** | 需要 FastCGI | 原生支持 |
| **配置** | 简洁 | 功能强大但复杂 |

---

### 1.2 IO 多路复用模型对比

#### 1.2.1 select 模型

**工作原理**：
- 将需要监视的文件描述符放入一个集合
- 调用 select() 函数，内核会轮询检查集合中的文件描述符
- 当有文件描述符就绪时，select() 返回
- 用户程序需要再次遍历集合找出就绪的文件描述符

**限制**：
- 最大支持 1024 个文件描述符（FD_SETSIZE）
- 性能随文件描述符数量线性下降
- 每次调用都需要拷贝整个文件描述符集合到内核空间

**使用场景**：
- 文件描述符数量较少的情况
- 需要跨平台支持的场景

---

#### 1.2.2 poll 模型

**工作原理**：
- 使用链表存储文件描述符，没有最大数量限制
- 调用 poll() 函数，内核轮询检查所有文件描述符
- 返回就绪的文件描述符数量
- 用户程序遍历找出就绪的文件描述符

**优点**：
- 没有最大并发连接的限制

**缺点**：
- 性能随文件描述符数量线性下降（仍需轮询）
- 每次调用都需要拷贝整个文件描述符列表

**使用场景**：
- 需要监视大量文件描述符且没有最大数量限制的场景

---

#### 1.2.3 epoll 模型（Linux）

**工作原理**：
- 通过 epoll_create 创建 epoll 实例
- 使用 epoll_ctl 注册、修改或删除文件描述符上的事件
- 当有文件描述符就绪时，内核会将其加入就绪队列
  - **也就是说，epoll 最大的优点就在于它只管理"活跃"的连接，而跟连接总数无关**
- 用户态程序通过 epoll_wait 从就绪队列中获取就绪的文件描述符

**优点**：
- 没有最大并发连接的限制（能打开的 FD 的上限远大于 1024）
- 效率极高，不会随着文件描述符数量的增加而下降
- 使用 mmap 减少用户空间和内核空间之间的数据拷贝开销
- 提供两种触发模式：水平触发（LT）和边缘触发（ET）
  - 最大的特点在于边缘触发，它只告诉进程哪些 fd 刚刚变为就绪态，并且只会通知一次

**性能对比**：

| 场景 | 最佳选择 | 原因 |
|------|---------|------|
| **文件描述符数量较少且都活跃** | select/poll | epoll 的通知机制涉及较多的函数回调 |
| **文件描述符数量较多且只有部分活跃** | epoll | 避免了不必要的轮询，只关注活跃的文件描述符 |
| **跨平台需求** | select | 支持所有平台 |
| **Linux 平台高并发** | epoll | 性能最优 |

---

## 🌐 第二部分：网络架构与环境说明

### 2.1 网络拓扑

```
Docker Bridge 网络：nginx-net (10.0.7.0/24)
├── 10.0.7.1   - 网关（Docker 网桥）
├── 10.0.7.10  - Ubuntu 二进制安装 (nginx-ubuntu-apt)
├── 10.0.7.11  - Rocky 二进制安装 (nginx-rocky-yum)
├── 10.0.7.12  - Ubuntu 源码编译 (nginx-ubuntu-compile)
├── 10.0.7.13  - Rocky 源码编译 (nginx-rocky-compile)
├── 10.0.7.14  - Ubuntu 手工环境 (nginx-ubuntu-manual)
└── 10.0.7.15  - Rocky 手工环境 (nginx-rocky-manual)
```

### 2.2 Docker Compose 配置说明

```yaml
version: '3.8'

services:
  # Ubuntu 二进制安装（APT）
  nginx-ubuntu-apt:
    container_name: nginx-ubuntu-apt
    hostname: nginx-ubuntu-apt
    build:
      context: ..
      dockerfile: Dockerfile.ubuntu-apt
    networks:
      nginx-net:
        ipv4_address: 10.0.7.10

  # Rocky 二进制安装（YUM）
  nginx-rocky-yum:
    container_name: nginx-rocky-yum
    hostname: nginx-rocky-yum
    build:
      context: ..
      dockerfile: Dockerfile.rocky-yum
    networks:
      nginx-net:
        ipv4_address: 10.0.7.11

  # Ubuntu 源码编译安装
  nginx-ubuntu-compile:
    container_name: nginx-ubuntu-compile
    hostname: nginx-ubuntu-compile
    build:
      context: ..
      dockerfile: Dockerfile.ubuntu-compile
    networks:
      nginx-net:
        ipv4_address: 10.0.7.12

  # Rocky 源码编译安装
  nginx-rocky-compile:
    container_name: nginx-rocky-compile
    hostname: nginx-rocky-compile
    build:
      context: ..
      dockerfile: Dockerfile.rocky-compile
    networks:
      nginx-net:
        ipv4_address: 10.0.7.13

  # Ubuntu 手工编译环境
  nginx-ubuntu-manual:
    image: ubuntu:24.04
    container_name: nginx-ubuntu-manual
    hostname: nginx-ubuntu-manual
    stdin_open: true
    tty: true
    command: /bin/bash
    networks:
      nginx-net:
        ipv4_address: 10.0.7.14
    environment:
      - DEBIAN_FRONTEND=noninteractive

  # Rocky 手工编译环境
  nginx-rocky-manual:
    image: rockylinux:9.3.20231119
    container_name: nginx-rocky-manual
    hostname: nginx-rocky-manual
    stdin_open: true
    tty: true
    command: /bin/bash
    networks:
      nginx-net:
        ipv4_address: 10.0.7.15

networks:
  nginx-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.7.0/24
          gateway: 10.0.7.1
```

---

## 🚀 第三部分：环境启动与验证

### 3.1 启动环境

```bash
# 1. 进入项目目录
cd /root/docker-man/07.nginx/01.manual-install

# 2. 启动所有服务
docker compose up -d

# 3. 检查服务状态
docker compose ps

# 预期输出：
# NAME                   IMAGE                       STATUS
# nginx-rocky-compile    ...                         Up
# nginx-rocky-manual     rockylinux:9.3.20231119     Up
# nginx-rocky-yum        ...                         Up
# nginx-ubuntu-apt       ...                         Up
# nginx-ubuntu-compile   ...                         Up
# nginx-ubuntu-manual    ubuntu:24.04                Up

# 4. 查看网络配置
docker network inspect 01manual-install_nginx-net

# 5. 测试各个 Nginx 服务（已编译的容器）
curl http://10.0.7.10  # Ubuntu APT
curl http://10.0.7.11  # Rocky YUM
curl http://10.0.7.12  # Ubuntu 编译
curl http://10.0.7.13  # Rocky 编译
```

---

## 📦 第四部分：Ubuntu 二进制安装（APT） - 参考

**⚠️ 注意：本环境容器已预装编译版本 Nginx，以下内容仅供参考**

本部分介绍 Ubuntu 系统使用 APT 包管理器安装 Nginx 的方法。如果你需要在其他 Ubuntu 环境中安装 Nginx，可以参考以下步骤。

### 4.1 查看可用软件包（参考）

```bash
# 查看可用的 nginx 版本
apt list nginx -a

# 预期输出：
# nginx/noble-updates,noble-security,now 1.24.0-2ubuntu7.1 amd64 [已安装]
# nginx/noble 1.24.0-2ubuntu7 amd64
```

### 4.2 安装 Nginx（参考）

```bash
# ⚠️ 本环境已预装，以下为其他环境的参考安装命令

# 基础安装
apt install nginx -y

# 推荐安装（包含额外模块和文档）
apt install nginx nginx-core fcgiwrap nginx-doc -y
```

**说明**：
- 默认情况下会安装 nginx-common 软件包
- nginx-core：核心模块
- fcgiwrap：FastCGI 包装器
- nginx-doc：文档

### 4.3 APT 安装的配置文件说明（参考）

APT 方式安装的 Nginx 配置文件位置与编译安装不同：

```bash
# APT 安装的配置文件目录
ls /etc/nginx/

# 目录结构：
# conf.d/              - 额外配置目录
# koi-utf, koi-win     - 字符集映射
# modules-available/   - 可用模块
# modules-enabled/     - 已启用模块
# proxy_params         - 代理参数
# sites-available/     - 可用站点配置
# sites-enabled/       - 已启用站点配置
# snippets/            - 配置片段
# nginx.conf           - 主配置文件

# APT 安装的默认首页目录
ls /var/www/html/
# index.html  index.nginx-debian.html
```

**⚠️ 本环境使用编译安装，配置文件路径为 `/data/server/nginx/conf/`**

### 4.4 版本和服务状态

```bash
# 查看版本
nginx -V

# 查看进程状态
ps aux | grep nginx

# 查看监听端口
netstat -tnulp | grep nginx
# tcp  0  0 0.0.0.0:80  0.0.0.0:*  LISTEN  xxxx/nginx: master
# tcp6 0  0 :::80       :::*       LISTEN  xxxx/nginx: master
```

---

## 📦 第五部分：Rocky 二进制安装（YUM） - 参考

**⚠️ 注意：本环境容器已预装编译版本 Nginx，以下内容仅供参考**

本部分介绍 Rocky Linux 系统使用 YUM 包管理器安装 Nginx 的方法。如果你需要在其他 Rocky 环境中安装 Nginx，可以参考以下步骤。

### 5.1 查看可用软件包（参考）

```bash
# 查看可用的 nginx 版本
yum list nginx

# 预期输出：
# nginx.x86_64  1:1.20.1-16.el9_4.1  @appstream
```

### 5.2 安装 Nginx（参考）

```bash
# ⚠️ 本环境已预装，以下为其他环境的参考安装命令

# 安装 nginx 和核心模块
yum install nginx nginx-core -y
```

**说明**：
- 默认情况下，会安装依赖包：
  - nginx-core
  - nginx-filesystem
  - rocky-logos-httpd

### 5.3 服务管理（参考）

YUM 安装的 Nginx 使用 systemctl 管理，编译安装使用直接命令：

```bash
# YUM 安装的管理方式（参考）
systemctl is-active nginx
systemctl enable --now nginx

# 本环境编译安装的管理方式（实际使用）
nginx                    # 启动
nginx -s reload          # 重载配置
nginx -s stop            # 停止
ps aux | grep nginx      # 查看状态
```

### 5.4 YUM 安装的配置文件说明（参考）

YUM 方式安装的 Nginx 配置文件位置与编译安装不同：

```bash
# YUM 安装的配置文件目录
ls /etc/nginx/

# 目录结构：
# conf.d/                    - 额外配置目录
# default.d/                 - 默认配置
# fastcgi.conf               - FastCGI 配置
# fastcgi_params             - FastCGI 参数
# koi-utf, koi-win, win-utf  - 字符集映射
# mime.types                 - MIME 类型
# nginx.conf                 - 主配置文件
# scgi_params                - SCGI 参数
# uwsgi_params               - uWSGI 参数

# YUM 安装的默认首页目录
ls /usr/share/nginx/html/
# 404.html  50x.html  icons/  index.html
# nginx-logo.png  poweredby.png  system_noindex_logo.png
```

**⚠️ 本环境使用编译安装，配置文件路径为 `/data/server/nginx/conf/`**

### 5.5 版本和服务状态

```bash
# 查看版本
nginx -V

# 查看进程状态
ps aux | grep nginx

# 查看监听端口
netstat -tnulp | grep nginx
# tcp   0  0 0.0.0.0:80   0.0.0.0:*   LISTEN  xxxx/nginx: master
# tcp6  0  0 :::80        :::*        LISTEN  xxxx/nginx: master
```

---

## 🔧 第六部分：Ubuntu 源码编译安装（教学演示）

**✅ 本环境容器已预装编译版本，以下为编译过程的教学演示**

如果你需要在全新的 Ubuntu 环境中手工编译安装 Nginx，可以参考以下完整步骤。

### 6.1 编译环境准备

#### 6.1.1 进入手工编译容器

```bash
docker compose exec -it nginx-ubuntu-manual bash
```

#### 6.1.2 安装编译依赖

```bash
# 第一组：基础编译环境
apt update
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

# 第二组：额外功能模块依赖（默认二进制环境开启功能所依赖的库）
apt install -y \
    libxml2 \
    libxml2-dev \
    libxslt1-dev \
    php-gd \
    libgd-dev \
    geoip-database \
    libgeoip-dev
```

**依赖包说明**：

| 包名 | 作用 | 模块 |
|------|------|------|
| **build-essential** | 编译工具集（gcc, g++, make 等） | 必需 |
| **libpcre3-dev** | Perl 兼容正则表达式库 | rewrite 模块 |
| **libssl-dev** | SSL/TLS 加密库 | SSL 模块 |
| **libsystemd-dev** | systemd 集成库 | systemd 支持 |
| **zlib1g-dev** | gzip 压缩库 | gzip 模块 |
| **libxml2-dev** | XML 解析库 | XML 处理 |
| **libxslt1-dev** | XSLT 转换库 | XSLT 模块 |
| **libgd-dev** | 图像处理库 | Image Filter 模块 |
| **libgeoip-dev** | GeoIP 数据库 | GeoIP 模块 |

#### 6.1.3 创建运行用户

```bash
useradd -r -s /usr/sbin/nologin nginx
```

### 6.2 下载并解压源码

```bash
# 下载 Nginx 源码
wget https://nginx.org/download/nginx-1.22.1.tar.gz

# 如果出现 "无法解析主机地址 'nginx.org'"，重新尝试下载即可

# 解压
tar xf nginx-1.22.1.tar.gz
cd nginx-1.22.1/
```

### 6.3 编译配置

#### 6.3.1 查看帮助

```bash
./configure --help
```

#### 6.3.2 定制配置

```bash
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

| 选项 | 说明 | 用途 |
|------|------|------|
| **--prefix** | 安装路径 | /data/server/nginx |
| **--user/--group** | 运行用户/组 | nginx |
| **--with-http_ssl_module** | HTTPS 支持 | SSL/TLS 加密 |
| **--with-http_v2_module** | HTTP/2 协议 | 性能优化 |
| **--with-http_realip_module** | 真实 IP | 反向代理场景 |
| **--with-http_stub_status_module** | 状态监控 | 性能监控 |
| **--with-http_gzip_static_module** | 静态 gzip | 预压缩文件 |
| **--with-pcre** | 正则表达式 | URL 重写 |
| **--with-stream** | TCP/UDP 代理 | 四层负载均衡 |
| **--with-stream_ssl_module** | Stream SSL | 四层 SSL 代理 |
| **--with-stream_realip_module** | Stream 真实 IP | 四层代理场景 |

### 6.4 编译和安装

```bash
# 编译（该过程需要持续 1 分钟左右）
make && make install

# 修改目录属主属组
chown -R nginx:nginx /data/server/nginx/

# 查看目录结构
ls -l /data/server/nginx/
# total 16
# drwxr-xr-x 2 nginx nginx 4096 conf/     # 配置文件目录
# drwxr-xr-x 2 nginx nginx 4096 html/     # 网站文件根目录
# drwxr-xr-x 2 nginx nginx 4096 logs/     # 日志文件目录
# drwxr-xr-x 2 nginx nginx 4096 sbin/     # 二进制程序目录
```

### 6.5 环境收尾

#### 6.5.1 创建软链接

```bash
ln -sv /data/server/nginx/sbin/nginx /usr/sbin/nginx
# '/usr/sbin/nginx' -> '/data/server/nginx/sbin/nginx'
```

#### 6.5.2 查看版本

```bash
nginx -v
# nginx version: nginx/1.22.1
```

#### 6.5.3 导入 man 手册

```bash
# 复制 man 手册
cp man/nginx.8 /usr/share/man/man8/

# 构建数据库
mandb

# 确认效果
whereis nginx
man nginx
```

### 6.6 定制服务管理文件

#### 6.6.1 创建 PID 目录

```bash
mkdir /data/server/nginx/run
chown -R nginx:nginx /data/server/nginx/run
```

#### 6.6.2 修改配置文件，设置 PID 文件路径

```bash
# 编辑配置文件
vim /data/server/nginx/conf/nginx.conf

# 在文件开头添加（第一行之后）：
pid     /data/server/nginx/run/nginx.pid;
```

#### 6.6.3 创建 nginx 服务脚本

```bash
cat > /usr/lib/systemd/system/nginx.service <<'EOF'
[Unit]
Description=nginx - high performance web server
Documentation=http://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/data/server/nginx/run/nginx.pid
ExecStart=/data/server/nginx/sbin/nginx -c /data/server/nginx/conf/nginx.conf
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s TERM $MAINPID
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
```

**服务文件说明**：

| 配置项 | 说明 |
|--------|------|
| **Type=forking** | Nginx 会 fork 出子进程 |
| **PIDFile** | PID 文件路径（必须与 nginx.conf 一致） |
| **ExecStart** | 启动命令 |
| **ExecReload** | 重载命令（SIGHUP 信号） |
| **ExecStop** | 停止命令（SIGTERM 信号） |
| **LimitNOFILE** | 最大文件描述符数 |

**信号作用**：
- **SIGHUP (1)**: 挂起信号。收到此信号的进程通常会终止，但一些守护进程可能会用它来重新加载配置文件
- **SIGKILL (9)**: 强制终止信号。用于立即结束进程，不能被捕获、忽略或阻塞
- **SIGTERM (15)**: 终止请求信号。用于请求进程优雅地终止运行。进程可以捕获此信号并进行清理工作

#### 6.6.4 启动 Nginx

```bash
# 启动 nginx（容器环境直接使用二进制命令）
nginx

# 或使用绝对路径
/data/server/nginx/sbin/nginx

# 查看进程状态
ps aux | grep nginx

# 查看监听端口
netstat -tnulp | grep nginx
# tcp  0  0 0.0.0.0:80  0.0.0.0:*  LISTEN  xxxx/nginx: master
```

**注意**：
- 容器环境中直接使用 `nginx` 命令启动
- systemd 服务文件主要用于非容器环境的生产部署

---

## 🔧 第七部分：Rocky 源码编译安装（教学演示）

**✅ 本环境容器已预装编译版本，以下为编译过程的教学演示**

如果你需要在全新的 Rocky Linux 环境中手工编译安装 Nginx，可以参考以下完整步骤。

### 7.1 编译环境准备

#### 7.1.1 进入手工编译容器

```bash
docker compose exec -it nginx-rocky-manual bash
```

#### 7.1.2 安装编译依赖

```bash
# 第一组：基础编译环境
yum install -y \
    gcc \
    make \
    gcc-c++ \
    glibc \
    glibc-devel \
    pcre \
    pcre-devel \
    openssl \
    openssl-devel \
    systemd-devel \
    zlib-devel

# 第二组：额外功能模块依赖（默认二进制环境开启功能所依赖的库）
yum install -y \
    libxml2 \
    libxml2-devel \
    libxslt \
    libxslt-devel \
    php-gd \
    gd-devel
```

**注意**：
- 第二条编译环境内容是默认二进制环境开启功能所依赖的库环境

#### 7.1.3 创建运行用户

```bash
useradd -r -s /usr/sbin/nologin nginx
```

### 7.2 下载并解压源码

```bash
# 创建软件目录
mkdir /softs
cd /softs

# 下载 Nginx 源码
wget https://nginx.org/download/nginx-1.23.0.tar.gz

# 解压
tar xf nginx-1.23.0.tar.gz
cd nginx-1.23.0/
```

### 7.3 编译配置

#### 7.3.1 查看帮助

```bash
./configure --help
```

#### 7.3.2 定制配置

```bash
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

### 7.4 编译和安装

```bash
# 编译
make

# 安装
make install

# 修改文件属性
chown -R nginx:nginx /data/server/nginx/
```

### 7.5 启动应用

```bash
# 启动 nginx
/data/server/nginx/sbin/nginx

# 检查效果
/data/server/nginx/sbin/nginx -V

# 浏览器访问
curl http://localhost/
```

### 7.6 环境收尾

#### 7.6.1 配置环境变量

```bash
# 将 nginx 加入 PATH
echo "export PATH=/data/server/nginx/sbin:\$PATH" >> /etc/bashrc
source /etc/bashrc
```

#### 7.6.2 导入 man 手册

```bash
cd /softs/nginx-1.23.0/
cp man/nginx.8 /usr/share/man/man8/
man nginx
```

### 7.7 定制服务管理文件

#### 7.7.1 创建 PID 目录

```bash
mkdir /data/server/nginx/run
chown -R nginx:nginx /data/server/nginx/run
```

#### 7.7.2 修改配置文件

```bash
# 编辑配置文件
vim /data/server/nginx/conf/nginx.conf

# 在文件开头添加：
pid     /data/server/nginx/run/nginx.pid;
```

#### 7.7.3 创建 nginx 服务脚本

```bash
cat > /usr/lib/systemd/system/nginx.service <<'EOF'
[Unit]
Description=nginx - high performance web server
Documentation=http://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/data/server/nginx/run/nginx.pid
ExecStart=/data/server/nginx/sbin/nginx -c /data/server/nginx/conf/nginx.conf
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s TERM $MAINPID
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
```

**注意**：
- 如果 PID 文件路径不一样，会导致 nginx 服务无法启动

#### 7.7.4 启动 Nginx

```bash
# 启动 nginx（容器环境直接使用二进制命令）
nginx

# 或使用绝对路径
/data/server/nginx/sbin/nginx

# 查看进程状态
ps aux | grep nginx

# 查看监听端口
netstat -tnulp | grep nginx
# tcp  0  0 0.0.0.0:80  0.0.0.0:*  LISTEN  xxxx/nginx: master
```

**注意**：
- 容器环境中直接使用 `nginx` 命令启动
- systemd 服务文件主要用于非容器环境的生产部署

### 7.8 定制服务管理样式 2（不使用 PID 文件）

```bash
cat > /tmp/nginx.service <<'EOF'
[Unit]
Description=nginx - high performance web server
Documentation=http://nginx.org/en/docs/
After=network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
ExecStartPre=/data/server/nginx/sbin/nginx -t
ExecStart=/data/server/nginx/sbin/nginx
ExecReload=/data/server/nginx/sbin/nginx -s reload
ExecStop=/data/server/nginx/sbin/nginx -s stop
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOF
```

---

## 🔧 第八部分：Nginx 命令详解

### 8.1 命令帮助

**注意**：以 Ubuntu 系统下，apt 方式安装 nginx 的环境演示

```bash
nginx -h
```

**输出**：
```
nginx version: nginx/1.24.0 (Ubuntu)
Usage: nginx [-?hvVtTq] [-s signal] [-p prefix]
             [-e filename] [-c filename] [-g directives]
```

### 8.2 常用选项

| 选项 | 说明 | 示例 |
|------|------|------|
| **-v** | 显示版本信息 | `nginx -v` |
| **-V** | 显示版本信息和编译项 | `nginx -V` |
| **-t** | 检查并测试配置文件 | `nginx -t` |
| **-T** | 检查并测试配置文件，且输出配置文件内容 | `nginx -T` |
| **-q** | 在配置文件测试期间禁止显示非错误消息 | `nginx -t -q` |
| **-?/-h** | 显示帮助信息 | `nginx -h` |

### 8.3 高级选项

| 选项 | 说明 | 示例 |
|------|------|------|
| **-s signal** | 发送信号：stop\|quit\|reopen\|reload | `nginx -s reload` |
| **-p prefix** | 指定运行目录，默认是 /usr/share/nginx/ | `nginx -p /path/to/nginx` |
| **-c filename** | 指定配置文件，默认是 /etc/nginx/nginx.conf | `nginx -c /path/to/nginx.conf` |
| **-g directive** | 启动时指定一些全局配置项，而不用修改配置文件 | `nginx -g "daemon off;"` |

### 8.4 信号说明

| 信号 | 说明 | 等价命令 |
|------|------|---------|
| **stop** | 立即停止，没处理完的请求也会被立即断开 | `kill -SIGTERM $MAINPID` |
| **quit** | 优雅退出，不再接收新的请求，但已建立的连接不受影响 | `kill -SIGQUIT $MAINPID` |
| **reopen** | 重开一个新的日志文件，日志内容写新文件 | `kill -SIGUSR1 $MAINPID` |
| **reload** | 重新加载配置文件，不中断正在处理的请求 | `nginx -s reload` |
| **SIGUSR2** | 平滑升级二进制文件 | 适用于版本升级 |
| **SIGWINCH** | 优雅的停止工作进程 | 适用于版本升级 |

### 8.5 配置文件检测

```bash
# 检查配置文件语法，并测试配置文件
nginx -t

# 输出（编译安装版本）：
# nginx: the configuration file /data/server/nginx/conf/nginx.conf syntax is ok
# nginx: configuration file /data/server/nginx/conf/nginx.conf test is successful

# 检查退出码
echo $?
# 0

# 检查配置文件语法，并测试配置文件，仅输出错误信息
nginx -t -q
echo $?
# 0
```

---

## 🔧 第九部分：故障排除

### 9.1 Rocky 环境定制服务文件无法启动

在 Rocky 环境下，经常会遇到定制的服务文件都是正常的，但是无法启动，经常会有以下原因导致：

#### 9.1.1 配置问题

**问题 1**：nginx 配置语法有问题

```bash
# 检查 Nginx 配置文件语法
nginx -t

# 错误示例：
# nginx: [emerg] directive "pid" is not terminated by ";" in
# /data/server/nginx/conf/nginx.conf:12
# nginx: configuration file /data/server/nginx/conf/nginx.conf test failed
```

**解决方法**：
- 一般情况下，都是因为缺少配置的结尾符号导致的
- 检查配置文件，确保每个指令都以分号 `;` 结尾

---

#### 9.1.2 权限问题

**问题 2**：nginx 环境的配置文件权限问题

**解决方法**：
```bash
# 系统服务以特定用户身份运行，所以要确保 Nginx 可执行文件和配置文件对该用户有足够的权限

# 修改目录权限
chown -R nginx:nginx /data/server/nginx/run

# 确保可执行权限
chmod +x /data/server/nginx/sbin/nginx
```

---

#### 9.1.3 SELinux 问题

**问题 3**：SELinux 阻止服务运行

```bash
# 检查 SELinux 状态
sestatus

# 若 SELinux 处于 enforcing 状态，可以临时将其设置为 permissive 模式来进行测试
setenforce 0

# 永久禁用 SELinux（需要重启系统使配置生效）
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
```

---

#### 9.1.4 防火墙问题

**问题 4**：防火墙阻止端口访问（容器环境通常无此问题）

```bash
# 容器环境注意事项：
# 1. Docker 容器默认通过网络隔离，防火墙规则由 Docker 管理
# 2. 确保 compose.yml 中正确暴露了端口
# 3. 宿主机防火墙需要允许 Docker 流量

# 如果在物理服务器上部署，可以使用以下命令：

# 方法 1：开放 Nginx 默认的 80 和 443 端口
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# 方法 2：临时禁用防火墙（仅用于测试）
# systemctl disable --now firewalld  # 不推荐在生产环境使用
```

---

## 📋 第十部分：测试检查清单

### 10.1 基础知识

- [ ] 理解 Nginx 的事件驱动架构
- [ ] 理解 select、poll、epoll 三种 IO 多路复用模型的区别
- [ ] 掌握 epoll 的工作原理和优势
- [ ] 理解 Nginx 与 Apache 的区别

### 10.2 二进制安装（Ubuntu） - 参考

- [ ] 理解 APT 安装与编译安装的区别
- [ ] 了解 nginx-core、fcgiwrap、nginx-doc 的作用
- [ ] 熟悉 Ubuntu nginx 的配置文件目录结构（`/etc/nginx/`）
- [ ] 对比编译安装的配置文件结构（`/data/server/nginx/conf/`）
- [ ] 理解不同安装方式的服务管理方法

### 10.3 二进制安装（Rocky） - 参考

- [ ] 理解 YUM 安装与编译安装的区别
- [ ] 了解 nginx-core、nginx-filesystem 的作用
- [ ] 熟悉 Rocky nginx 的配置文件目录结构（`/etc/nginx/`）
- [ ] 对比编译安装的配置文件结构（`/data/server/nginx/conf/`）
- [ ] 理解不同安装方式的服务管理方法

### 10.4 源码编译（Ubuntu） - 教学演示

- [ ] 理解编译依赖的作用和安装方法
- [ ] 理解各个依赖包对应的 Nginx 模块
- [ ] 掌握 `./configure` 的常用编译选项
- [ ] 理解编译选项的含义（SSL、HTTP/2、Stream 等）
- [ ] 了解 `make && make install` 的编译流程
- [ ] 创建运行用户和 PID 目录的作用
- [ ] 理解编译安装的目录结构
- [ ] 掌握使用 nginx 命令启动服务

### 10.5 源码编译（Rocky） - 教学演示

- [ ] 理解编译依赖的作用和安装方法
- [ ] 掌握 Rocky 和 Ubuntu 依赖包的对应关系
- [ ] 掌握 `./configure` 的常用编译选项
- [ ] 了解 `make && make install` 的编译流程
- [ ] 理解环境变量配置（PATH）的作用
- [ ] 理解 systemd 服务文件的配置（生产环境参考）
- [ ] 掌握使用 nginx 命令启动服务

### 10.6 Nginx 命令

- [ ] 掌握 `nginx -v` 和 `nginx -V` 的区别
- [ ] 使用 `nginx -t` 测试配置文件
- [ ] 使用 `nginx -s` 发送信号（reload、stop、quit）
- [ ] 理解各种信号的作用和区别
- [ ] 使用 `nginx -g` 指定全局配置项

### 10.7 故障排除

- [ ] 能够诊断配置语法错误
- [ ] 能够诊断权限问题
- [ ] 能够诊断 SELinux 问题
- [ ] 能够诊断防火墙问题
- [ ] 使用 `nginx -t` 快速定位配置错误

---

## ❓ 第十一部分：常见问题

### Q1: Ubuntu 和 Rocky 编译依赖包的对应关系是什么？

**答**：

| Ubuntu | Rocky | 说明 |
|--------|-------|------|
| build-essential | gcc, make, gcc-c++ | 编译工具集 |
| libc6-dev | glibc-devel | C 标准库开发包 |
| libpcre3-dev | pcre-devel | PCRE 开发包 |
| libssl-dev | openssl-devel | SSL 开发包 |
| zlib1g-dev | zlib-devel | zlib 开发包 |
| libxml2-dev | libxml2-devel | XML 开发包 |
| libxslt1-dev | libxslt-devel | XSLT 开发包 |
| libgd-dev | gd-devel | GD 开发包 |
| libgeoip-dev | GeoIP-devel | GeoIP 开发包 |

---

### Q2: 为什么 PID 文件路径很重要？

**答**：
- PID 文件用于记录 Nginx 主进程的进程 ID
- 如果使用 systemd 服务管理，服务文件中的 `PIDFile` 必须与 nginx.conf 中的 `pid` 配置一致
- 路径不一致会导致进程管理失败
- 容器环境中通常直接使用 `nginx` 命令，不强制要求 PID 文件

**正确示例**：
```bash
# nginx.conf
pid /data/server/nginx/run/nginx.pid;

# nginx.service（如果使用 systemd）
PIDFile=/data/server/nginx/run/nginx.pid

# 容器环境中验证 PID
cat /data/server/nginx/run/nginx.pid
ps aux | grep `cat /data/server/nginx/run/nginx.pid`
```

---

### Q3: reload 和 restart 的区别是什么？

**答**：

| 操作 | 行为 | 已有连接 | 新连接 | 停机时间 |
|------|------|---------|--------|---------|
| **reload** | 重新加载配置 | 按旧配置处理 | 按新配置处理 | 无 |
| **restart** | 重启服务 | 立即断开 | 等待重启完成 | 有（短暂） |

**推荐**：
- 修改配置后使用 `nginx -s reload`（平滑重载）
- 不推荐使用 `nginx -s stop && nginx`（会断开所有连接）

---

### Q4: 如何实现 Nginx 平滑升级？

**答**：

```bash
# 1. 备份旧的二进制文件
cp /data/server/nginx/sbin/nginx /data/server/nginx/sbin/nginx.old

# 2. 替换新的二进制文件
cp /path/to/new/nginx /data/server/nginx/sbin/nginx

# 3. 测试新的二进制文件
/data/server/nginx/sbin/nginx -t

# 4. 发送 USR2 信号，启动新的 master 进程
kill -USR2 `cat /data/server/nginx/run/nginx.pid`

# 5. 发送 WINCH 信号，优雅关闭旧的 worker 进程
kill -WINCH `cat /data/server/nginx/run/nginx.pid.oldbin`

# 6. 验证新进程运行正常后，关闭旧的 master 进程
kill -QUIT `cat /data/server/nginx/run/nginx.pid.oldbin`
```

---

### Q5: 如何查看 Nginx 的编译选项？

**答**：

```bash
nginx -V
```

**输出示例**：
```
nginx version: nginx/1.22.1
built by gcc 11.4.0 (Ubuntu 11.4.0-1ubuntu1~22.04)
built with OpenSSL 3.0.2 15 Mar 2022
TLS SNI support enabled
configure arguments: --prefix=/data/server/nginx --user=nginx --group=nginx
--with-http_ssl_module --with-http_v2_module --with-http_realip_module
--with-http_stub_status_module --with-http_gzip_static_module --with-pcre
--with-stream --with-stream_ssl_module --with-stream_realip_module
```

---

### Q6: 如何修改 worker 进程数量？

**答**：

```bash
# 编辑配置文件（编译安装路径）
vim /data/server/nginx/conf/nginx.conf

# 修改 worker_processes 配置
worker_processes auto;  # 自动（推荐）
# 或
worker_processes 4;     # 固定数量

# 重新加载配置
nginx -s reload

# 验证
ps aux | grep nginx
```

---

## 🎓 第十二部分：学习总结

通过本环境的学习，你应该掌握：

### 核心概念

1. **IO 多路复用模型**：select、poll、epoll 的工作原理和性能差异
2. **Nginx 架构**：事件驱动、master-worker 模型
3. **编译选项**：各种功能模块的作用和使用场景
4. **服务管理**：systemd 服务文件的配置和管理

### 安装技能

1. **二进制安装**：Ubuntu (apt) 和 Rocky (yum) 的安装方式
2. **源码编译**：编译依赖、配置选项、编译安装的完整流程
3. **服务配置**：PID 文件、systemd 服务文件的配置
4. **环境管理**：用户创建、权限设置、环境变量配置

### 故障排除

1. **配置错误** → 使用 `nginx -t` 检查语法
2. **权限问题** → 检查文件和目录权限
3. **SELinux 问题** → 临时或永久禁用
4. **防火墙问题** → 开放端口或禁用防火墙
5. **服务启动失败** → 检查 PID 文件路径一致性

### 实战应用

1. **静态网站部署**：快速部署静态网站
2. **反向代理**：作为后端应用的反向代理
3. **负载均衡**：分发流量到多个后端服务器
4. **SSL/TLS 终止**：处理 HTTPS 请求
5. **四层代理**：TCP/UDP 协议代理

---

## 🧹 清理环境

```bash
# 1. 停止所有容器
docker compose down

# 2. 删除构建的镜像（可选）
docker compose down --rmi all

# 3. 完全清理
docker compose down --rmi all --volumes
```

---

## 📖 参考资料

- **Nginx 官方文档**: https://nginx.org/en/docs/
- **Nginx 源码下载**: https://nginx.org/en/download.html
- **Nginx 配置参考**: https://nginx.org/en/docs/dirindex.html
- **Nginx 模块参考**: https://nginx.org/en/docs/ngx_core_module.html
- **systemd 文档**: https://www.freedesktop.org/software/systemd/man/

---

## 🔗 相关项目

- **07.nginx/01.manual-install**: 本项目（Nginx 安装实践）
- **07.nginx/02.manual-basic**: Nginx 基础配置
- **07.nginx/03.manual-security**: Nginx 安全配置
- **07.nginx/04.manual-optimization**: Nginx 性能优化
- **07.nginx/05.manual-rewrite**: Nginx URL 重写
- **07.nginx/06.manual-proxy**: Nginx 反向代理
- **07.nginx/07.manual-loadbalance**: Nginx 负载均衡
- **07.nginx/08.manual-layer4**: Nginx 四层代理
- **07.nginx/09.manual-fastcgi**: Nginx FastCGI

---

**完成时间**: 2025-10-10
**文档版本**: v1.0
**维护者**: docker-man 项目组
