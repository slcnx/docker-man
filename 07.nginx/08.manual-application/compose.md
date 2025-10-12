# Docker Compose Nginx 应用集成完整实践指南

## 📚 第一部分:基础知识

### 1.1 应用场景概述

本项目涵盖 Nginx 在企业生产环境中的多种应用场景,包括:

| 应用类型 | 技术栈 | 应用场景 | 复杂度 |
|---------|--------|---------|--------|
| **Discuz论坛** | PHP + MySQL + Nginx | 社区论坛、讨论系统 | ⭐⭐⭐ |
| **Redis模块** | Nginx + Redis | 缓存加速、会话管理 | ⭐⭐⭐⭐ |
| **FLV模块** | Nginx + FLV | 视频流媒体服务 | ⭐⭐ |
| **一致性哈希** | Nginx + Consistent Hash | 分布式负载均衡 | ⭐⭐⭐⭐ |
| **Tengine** | Tengine (阿里定制) | 高并发Web服务 | ⭐⭐⭐ |
| **OpenResty** | Nginx + Lua | 动态Web平台 | ⭐⭐⭐⭐ |
| **Django项目** | Python + Django + uWSGI + Nginx | Web应用部署 | ⭐⭐⭐⭐ |

---

### 1.2 Discuz论坛简介

**Discuz!** 是康盛创想(Comsenz)推出的社区论坛软件系统,全球成熟度最高、覆盖率最大的论坛软件之一。

#### 技术特点

- **开发语言**: PHP
- **数据库**: MySQL/MariaDB
- **Web服务器**: Nginx/Apache
- **缓存**: 支持Memcached、Redis

#### 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                         客户端浏览器                          │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ HTTP 请求
┌──────────────────┴──────────────────────────────────────────┐
│                      Nginx Web 服务器                         │
│  - 静态文件服务 (CSS/JS/图片)                                 │
│  - FastCGI 转发 PHP 请求                                      │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ FastCGI 协议
┌──────────────────┴──────────────────────────────────────────┐
│                       PHP-FPM 进程池                          │
│  - 执行 Discuz PHP 代码                                       │
│  - 处理业务逻辑                                               │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ MySQL 协议
┌──────────────────┴──────────────────────────────────────────┐
│                      MySQL 数据库                             │
│  - 存储用户数据、帖子、配置                                    │
└─────────────────────────────────────────────────────────────┘
```

---

### 1.3 第三方模块简介

#### 1.3.1 Redis模块 (ngx_http_redis2_module)

**功能**: 允许 Nginx 直接与 Redis 交互,实现缓存加速和动态内容服务。

**主要特性**:
- **缓存加速**: Nginx 直接从 Redis 读取缓存数据
- **动态内容服务**: 获取会话信息、配置数据
- **负载均衡**: 结合 Redis 实现灵活的分发策略

**代码地址**: https://github.com/agentzh/redis2-nginx-module.git

**工作流程**:
```
客户端 → Nginx → Redis 服务器 → 返回数据 → Nginx → 客户端
```

#### 1.3.2 FLV模块 (ngx_http_flv_module)

**功能**: 支持 FLV 视频的伪流式传输。

**主要特性**:
- **伪流式传输**: 无需下载完整文件即可播放
- **随机播放**: 支持快进、快退操作
- **提高播放体验**: 减少等待时间

**适用场景**:
- 小型视频网站
- 内部视频培训系统
- 视频会议系统

#### 1.3.3 一致性哈希模块 (ngx_http_upstream_consistent_hash_module)

**功能**: 为 Nginx 负载均衡引入一致性哈希算法。

**主要特性**:
- **服务器变动影响小**: 后端服务器增减时,仅少量请求受影响
- **灵活的哈希键**: 可基于客户端IP、URI等属性
- **提高缓存命中率**: 相同请求分发到同一服务器

**代码地址**: https://github.com/replay/ngx_http_consistent_hash.git

**工作原理**:
```
哈希环: 0 → 2^32-1 (形成闭环)
         ↓
    服务器节点映射到环上
         ↓
    请求哈希后顺时针查找最近节点
```

---

### 1.4 二次开发版本简介

#### 1.4.1 Tengine

**简介**: 阿里巴巴基于 Nginx 定制的高性能Web服务器。

**主要特点**:
- **起源**: 淘宝网内部需求
- **性能优化**: 针对高并发场景优化
- **动态模块加载**: 运行时加载/卸载模块
- **WebSocket支持**: 内置 WebSocket 协议支持

**版本**: Tengine/3.1.0 (nginx/1.24.0)

**官网**: https://tengine.taobao.org/

#### 1.4.2 OpenResty

**简介**: 基于 Nginx 与 Lua 的高性能 Web 平台。

**主要特点**:
- **Lua脚本**: 使用 Lua 编写业务逻辑
- **非阻塞I/O**: 充分利用 Nginx 异步特性
- **高并发**: 支持 10K+ 并发连接
- **丰富的库**: 集成大量 Lua 库和第三方模块

**版本**: openresty/1.25.3.1

**官网**: https://openresty.org/cn/

---

### 1.5 Django项目简介

**Django** 是基于 Python 的高级 Web 框架,鼓励快速开发和简洁实用的设计。

#### 生产环境部署架构

```
┌─────────────────────────────────────────────────────────────┐
│                         客户端浏览器                          │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ HTTP 请求
┌──────────────────┴──────────────────────────────────────────┐
│                         Nginx                                │
│  - 处理静态文件 (CSS/JS/图片)                                 │
│  - 反向代理动态请求到 uWSGI                                   │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ uwsgi 协议 (socket 通信)
┌──────────────────┴──────────────────────────────────────────┐
│                         uWSGI                                │
│  - WSGI 服务器                                               │
│  - 管理多个 worker 进程                                       │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ WSGI 协议
┌──────────────────┴──────────────────────────────────────────┐
│                      Django 应用                              │
│  - 处理业务逻辑                                               │
│  - ORM 数据库访问                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 核心组件

| 组件 | 作用 | 说明 |
|------|------|------|
| **Nginx** | Web服务器 | 处理静态文件、反向代理 |
| **uWSGI** | WSGI服务器 | Python应用与Web服务器之间的桥梁 |
| **Django** | Web框架 | 业务逻辑、ORM、模板引擎 |

---

## 🌐 第二部分:网络架构与环境说明

### 2.1 网络拓扑

```
Docker Bridge 网络: nginx-app-net (10.0.7.0/24)
├── 10.0.7.1   - 网关 (Docker 网桥)
├── 10.0.7.80  - nginx-app (Nginx + PHP-FPM + Discuz)
│   ├── 端口: 80 (HTTP)
│   └── Volume: nginx-web:/data/server/nginx
├── 10.0.7.81  - mysql-server (MySQL 8.0)
│   ├── 端口: 3306 (MySQL)
│   └── Volume: mysql-data:/var/lib/mysql
├── 10.0.7.82  - redis-server (Redis)
│   ├── 端口: 6379 (Redis)
│   └── Volume: redis-data:/data
├── 10.0.7.83  - tengine-server (Tengine)
│   ├── 端口: 8083 (HTTP)
│   └── Volume: tengine-data:/data/server/tengine
├── 10.0.7.84  - openresty-server (OpenResty)
│   ├── 端口: 8084 (HTTP)
│   └── Volume: openresty-data:/data/server/openresty
└── 10.0.7.85  - django-app (Django + uWSGI)
    ├── 端口: 8085 (HTTP), 8000 (Django Dev)
    └── Volume: django-data:/data
```

### 2.2 Docker Compose 配置说明

```yaml
version: '3.8'

services:
  # Nginx + PHP-FPM + Discuz 应用服务器
  nginx-app:
    container_name: nginx-app
    hostname: nginx-app
    networks:
      nginx-app-net:
        ipv4_address: 10.0.7.80
    privileged: true
    volumes:
      - nginx-web:/data/server/nginx
    ports:
      - "80:80"

  # MySQL 数据库服务器
  mysql-server:
    container_name: mysql-server
    hostname: mysql-server
    networks:
      nginx-app-net:
        ipv4_address: 10.0.7.81
    volumes:
      - mysql-data:/var/lib/mysql
    ports:
      - "3306:3306"
    environment:
      - MYSQL_ROOT_PASSWORD=123456

  # Redis 服务器
  redis-server:
    container_name: redis-server
    hostname: redis-server
    networks:
      nginx-app-net:
        ipv4_address: 10.0.7.82
    volumes:
      - redis-data:/data
    ports:
      - "6379:6379"

  # Tengine 服务器
  tengine-server:
    container_name: tengine-server
    hostname: tengine-server
    networks:
      nginx-app-net:
        ipv4_address: 10.0.7.83
    volumes:
      - tengine-data:/data/server/tengine
    ports:
      - "8083:80"

  # OpenResty 服务器
  openresty-server:
    container_name: openresty-server
    hostname: openresty-server
    networks:
      nginx-app-net:
        ipv4_address: 10.0.7.84
    volumes:
      - openresty-data:/data/server/openresty
    ports:
      - "8084:80"

  # Django 应用服务器
  django-app:
    container_name: django-app
    hostname: django-app
    networks:
      nginx-app-net:
        ipv4_address: 10.0.7.85
    volumes:
      - django-data:/data
    ports:
      - "8085:80"
      - "8000:8000"

networks:
  nginx-app-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.7.0/24
          gateway: 10.0.7.1

volumes:
  nginx-web:
    driver: local
  mysql-data:
    driver: local
  redis-data:
    driver: local
  tengine-data:
    driver: local
  openresty-data:
    driver: local
  django-data:
    driver: local
```

---

## 🚀 第三部分:环境启动

### 3.1 启动所有服务

```bash
# 1. 进入项目目录
cd /home/www/docker-man/07.nginx/08.manual-application

# 2. 启动所有服务
docker compose up -d

# 3. 检查服务状态
docker compose ps

# 4. 查看网络配置
docker network inspect 08manual-application_nginx-app-net

# 5. 验证所有容器运行正常
docker compose logs --tail=20
```

### 3.2 检查服务端口

```bash
# 检查所有服务端口
docker compose ps

# 预期输出:
# NAME              PORTS
# nginx-app         0.0.0.0:80->80/tcp
# mysql-server      0.0.0.0:3306->3306/tcp
# redis-server      0.0.0.0:6379->6379/tcp
# tengine-server    0.0.0.0:8083->80/tcp
# openresty-server  0.0.0.0:8084->80/tcp
# django-app        0.0.0.0:8000->8000/tcp, 0.0.0.0:8085->80/tcp
```

---

## 📝 第四部分:Discuz论坛部署完整实践

### 4.1 模块环境准备

#### 4.1.1 进入容器

```bash
docker compose exec -it nginx-app bash
```

#### 4.1.2 安装 PHP 模块

```bash
# 安装必需的 PHP 模块
apt update
apt install -y php-fpm php-mysqlnd php-json php-gd php-xml php-mbstring php-zip

# Ubuntu 环境说明:
# php-mysqlnd 和 php-mysqli 都会转换为 php8.3-mysql

# 验证安装
php -m | grep -E 'mysqli|gd|mbstring|xml|zip'
```

**必需模块说明**:

| 模块 | 作用 | 必需性 |
|------|------|--------|
| **php-fpm** | FastCGI 进程管理器 | ✅ 必需 |
| **php-mysqlnd** | MySQL Native Driver | ✅ 必需 |
| **php-json** | JSON 数据处理 | ✅ 必需 |
| **php-gd** | 图像处理 (验证码、缩略图) | ✅ 必需 |
| **php-xml** | XML 解析 | ✅ 必需 |
| **php-mbstring** | 多字节字符串处理 | ✅ 必需 |
| **php-zip** | ZIP 文件处理 | ✅ 必需 |

---

### 4.2 Discuz软件准备

#### 4.2.1 获取 Discuz 软件

```bash
# 下载 Discuz X3.5
cd /tmp
wget https://gitee.com/Discuz/DiscuzX/attach_files/1773967/download -O Discuz_X3.5_SC_UTF8_20240520.zip

# 如果下载失败,可以从备用源下载或本地上传
```

#### 4.2.2 解压文件

```bash
# 创建临时目录
mkdir -p /tmp/discuz

# 解压文件
unzip Discuz_X3.5_SC_UTF8_20240520.zip -d /tmp/discuz/

# 查看解压结果
ls -l /tmp/discuz/
# 输出: upload/ utility/ readme/
```

#### 4.2.3 转移文件和设置权限

```bash
# 清理原有文件
rm -rf /data/server/nginx/web1/*

# 转移 Discuz 文件
mv /tmp/discuz/upload/* /data/server/nginx/web1/

# 设置文件所有者和权限
chown -R www-data:www-data /data/server/nginx/web1/
chmod -R 755 /data/server/nginx/web1/

# 特殊目录需要写权限
chmod -R 777 /data/server/nginx/web1/data
chmod -R 777 /data/server/nginx/web1/config
chmod -R 777 /data/server/nginx/web1/uc_server/data
chmod -R 777 /data/server/nginx/web1/uc_client/data

# 验证文件结构
ls -l /data/server/nginx/web1/
# 预期输出: admin.php  api/  config/  data/  install/  source/  static/  ...
```

---

### 4.3 数据库环境配置

#### 4.3.1 进入 MySQL 容器

```bash
# 在宿主机执行
docker compose exec -it mysql-server bash
```

#### 4.3.2 创建数据库和用户

```bash
# 登录 MySQL
mysql -uroot -p123456

# 执行以下 SQL 命令
```

```sql
-- 创建 Discuz 数据库
CREATE DATABASE discuz CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建 Discuz 用户并设置密码
CREATE USER 'discuzer'@'10.0.7.%' IDENTIFIED BY '123456';

-- 授予所有权限
GRANT ALL PRIVILEGES ON discuz.* TO 'discuzer'@'10.0.7.%';

-- 刷新权限
FLUSH PRIVILEGES;

-- 验证用户和数据库
SELECT User, Host FROM mysql.user WHERE User='discuzer';
SHOW DATABASES LIKE 'discuz';

-- 退出
EXIT;
```

**预期输出**:
```
+----------+---------+
| User     | Host    |
+----------+---------+
| discuzer | 10.0.7.% |
+----------+---------+

+----------------+
| Database       |
+----------------+
| discuz         |
+----------------+
```

#### 4.3.3 测试数据库连接

```bash
# 在 nginx-app 容器中安装 MySQL 客户端
docker compose exec -it nginx-app bash

apt install -y mysql-client

# 测试连接
mysql -h 10.0.7.81 -u discuzer -p123456 -e "SHOW DATABASES;"

# 预期输出:
# +--------------------+
# | Database           |
# +--------------------+
# | discuz             |
# | information_schema |
# | performance_schema |
# +--------------------+
```

---

### 4.4 Web界面安装

#### 4.4.1 访问安装页面

浏览器访问: `http://宿主机IP/install/`

例如: `http://10.0.0.13/install/`

#### 4.4.2 安装步骤

**步骤1: 许可协议**
- 阅读用户许可协议
- 点击"我同意"

**步骤2: 环境检查**

系统会自动检查以下项目:

| 检查项 | 要求 | 说明 |
|-------|------|------|
| PHP版本 | >= 7.4 | 建议 8.x |
| 磁盘空间 | >= 100MB | 用于上传文件 |
| 附件上传 | upload_max_filesize | 建议 >= 8MB |
| GD库 | 已安装 | 图像处理 |
| MySQL扩展 | mysqli | 数据库连接 |

所有项目都应显示 ✅ (绿色对勾)。

**步骤3: 目录权限检查**

以下目录必须可写:

```
./config/             - 配置文件目录
./data/               - 数据目录
./uc_server/data/     - UCenter数据目录
./uc_client/data/     - UCenter客户端数据目录
```

如果显示不可写,执行:
```bash
chmod -R 777 /data/server/nginx/web1/config
chmod -R 777 /data/server/nginx/web1/data
chmod -R 777 /data/server/nginx/web1/uc_server/data
chmod -R 777 /data/server/nginx/web1/uc_client/data
```

**步骤4: 数据库配置**

填写以下信息:

| 配置项 | 值 | 说明 |
|-------|---|------|
| 数据库服务器 | `10.0.7.81` | MySQL容器IP |
| 数据库端口 | `3306` | 默认端口 |
| 数据库名 | `discuz` | 已创建的数据库 |
| 数据库用户名 | `discuzer` | 已创建的用户 |
| 数据库密码 | `123456` | 用户密码 |
| 数据表前缀 | `pre_` | 默认即可 |

**步骤5: 管理员账号设置**

| 配置项 | 示例值 | 说明 |
|-------|-------|------|
| 管理员账号 | `admin` | 登录用户名 |
| 管理员密码 | `Admin@123` | 强密码 |
| 重复密码 | `Admin@123` | 确认密码 |
| 管理员邮箱 | `admin@example.com` | 接收通知 |

**步骤6: 安装完成**

- 安装完成后,会显示成功页面
- 记录管理员账号和密码
- 点击"您的论坛已完成安装,点此访问"

#### 4.4.3 首次访问

```bash
# 浏览器访问论坛首页
http://10.0.0.13/

# 访问管理后台
http://10.0.0.13/admin.php
```

#### 4.4.4 安全建议

安装完成后,删除或重命名 install 目录:

```bash
docker compose exec -it nginx-app bash

# 方式1: 删除
rm -rf /data/server/nginx/web1/install/

# 方式2: 重命名
mv /data/server/nginx/web1/install/ /data/server/nginx/web1/install.bak/
```

---

### 4.5 Discuz功能测试

#### 4.5.1 前台测试

```bash
# 1. 注册新用户
浏览器访问: http://10.0.0.13/member.php?mod=register

# 2. 发布帖子
登录后 → 进入版块 → 点击"发帖"

# 3. 上传附件
发帖时 → 点击"添加附件" → 选择文件上传

# 4. 个人资料
点击用户名 → 个人资料 → 修改头像
```

#### 4.5.2 后台测试

```bash
# 访问管理后台
http://10.0.0.13/admin.php

# 测试功能:
# - 全局设置
# - 用户管理
# - 版块管理
# - 插件管理
# - 模板管理
```

---

## 🔧 第五部分:第三方模块实践

### 5.1 Redis模块集成

#### 5.1.1 环境准备

```bash
# 进入nginx-app容器
docker compose exec -it nginx-app bash

# 安装编译依赖
apt update
apt install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev openssl libssl-dev git
```

#### 5.1.2 获取 Redis 模块

```bash
# 创建目录结构
mkdir -p /data/{softs,codes}

# 克隆 Redis 模块
cd /data/codes
git clone https://github.com/agentzh/redis2-nginx-module.git

# 验证
ls -l redis2-nginx-module/
```

#### 5.1.3 编译 Nginx with Redis 模块

```bash
# 下载 Nginx 源码
cd /data/softs
wget https://nginx.org/download/nginx-1.27.5.tar.gz
tar xf nginx-1.27.5.tar.gz
cd nginx-1.27.5/

# 配置编译选项
./configure \
  --prefix=/data/server/nginx-redis \
  --add-module=/data/codes/redis2-nginx-module

# 编译安装
make && make install

# 验证模块
/data/server/nginx-redis/sbin/nginx -V 2>&1 | grep redis2-nginx-module
# 输出: configure arguments: --prefix=/data/server/nginx-redis --add-module=/data/codes/redis2-nginx-module
```

#### 5.1.4 配置 Redis 服务器

```bash
# Redis 服务器已由 docker compose 启动
# 添加测试数据

# 进入 redis-server 容器
docker compose exec -it redis-server bash

# 使用 redis-cli 添加数据
redis-cli
127.0.0.1:6379> SET key1 value1
OK
127.0.0.1:6379> SET key2 value2
OK
127.0.0.1:6379> SET key3 value3
OK
127.0.0.1:6379> GET key1
"value1"
127.0.0.1:6379> EXIT
```

#### 5.1.5 配置 Nginx

```bash
# 回到 nginx-app 容器
docker compose exec -it nginx-app bash

# 创建配置目录
mkdir -p /data/server/nginx-redis/conf.d

# 修改主配置文件
cat > /data/server/nginx-redis/conf/nginx.conf <<'EOF'
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    include /data/server/nginx-redis/conf.d/*.conf;
}
EOF

# 创建 Redis 配置
cat > /data/server/nginx-redis/conf.d/redis.conf <<'EOF'
upstream redis_backend {
    server 10.0.7.82:6379;
}

server {
    listen 8081;
    server_name localhost;

    location /redis {
        # 设置默认类型
        default_type text/html;

        # 从 URL 参数获取 key
        set $redis_key $arg_key;

        # Redis 查询命令
        redis2_query get $redis_key;

        # 连接 Redis 后端
        redis2_pass redis_backend;
    }
}
EOF

# 检查配置
/data/server/nginx-redis/sbin/nginx -t
```

#### 5.1.6 启动并测试

```bash
# 启动 Nginx
/data/server/nginx-redis/sbin/nginx

# 检查端口
netstat -tnlp | grep 8081
# 输出: tcp  0  0  0.0.0.0:8081  0.0.0.0:*  LISTEN  12345/nginx

# 测试 Redis 查询
apt install -y curl

curl "http://localhost:8081/redis?key=key1"
# 输出:
# $6
# value1

curl "http://localhost:8081/redis?key=key2"
# 输出:
# $6
# value2

curl "http://localhost:8081/redis?key=key3"
# 输出:
# $6
# value3

curl "http://localhost:8081/redis?key=nonexist"
# 输出:
# $-1
```

**Redis 协议说明**:

| 返回格式 | 含义 | 示例 |
|---------|------|------|
| `$6\nvalue1` | 字符串,长度6字节 | `$6\nvalue1` |
| `$-1` | 键不存在 | `$-1` |
| `$0\n` | 空字符串 | `$0\n` |

#### 5.1.7 停止服务

```bash
/data/server/nginx-redis/sbin/nginx -s stop
```

---

### 5.2 FLV模块实践

#### 5.2.1 环境准备

```bash
# 进入nginx-app容器
docker compose exec -it nginx-app bash

# Nginx 源码已下载,FLV 模块是内置模块
cd /data/softs/nginx-1.27.5

# 查看 FLV 模块
./configure --help | grep flv
# 输出: --with-http_flv_module  enable ngx_http_flv_module
```

#### 5.2.2 编译 Nginx with FLV 模块

```bash
# 清理之前的编译
make clean

# 重新配置
./configure \
  --prefix=/data/server/nginx-flv \
  --with-http_flv_module

# 编译安装
make && make install

# 验证模块
/data/server/nginx-flv/sbin/nginx -V 2>&1 | grep flv
# 输出: configure arguments: --prefix=/data/server/nginx-flv --with-http_flv_module
```

#### 5.2.3 准备 FLV 视频文件

```bash
# 创建视频目录
mkdir -p /data/server/nginx-flv/html/videos

# 下载测试视频
cd /data/server/nginx-flv/html/videos
wget https://sample-videos.com/video123/flv/720/big_buck_bunny_720p_1mb.flv

# 如果下载失败,可从浏览器下载后上传

# 重命名
mv big_buck_bunny_720p_1mb.flv big.flv

# 验证
ls -lh
# 输出: -rw-r--r-- 1 root root 1.0M Oct 18 10:00 big.flv
```

#### 5.2.4 配置 Nginx

```bash
# 创建配置目录
mkdir -p /data/server/nginx-flv/conf.d

# 修改主配置
cat > /data/server/nginx-flv/conf/nginx.conf <<'EOF'
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    include /data/server/nginx-flv/conf.d/*.conf;
}
EOF

# 创建 FLV 配置
cat > /data/server/nginx-flv/conf.d/flv.conf <<'EOF'
server {
    listen 8082;
    server_name localhost;

    # 配置 FLV 伪流式传输
    location /flv/ {
        # 启用 FLV 模块
        flv;

        # 视频文件目录
        alias /data/server/nginx-flv/html/;
    }
}
EOF

# 检查配置
/data/server/nginx-flv/sbin/nginx -t
```

#### 5.2.5 启动并测试

```bash
# 启动 Nginx
/data/server/nginx-flv/sbin/nginx

# 检查端口
netstat -tnlp | grep 8082

# 测试下载
curl -I http://localhost:8082/flv/videos/big.flv
# 输出:
# HTTP/1.1 200 OK
# Server: nginx/1.27.5
# Content-Type: video/x-flv
# Content-Length: 1048576
```

**浏览器测试**:

在宿主机浏览器访问:
```
http://10.0.0.13:8082/flv/videos/big.flv
```

可以使用以下播放器测试:
- 迅雷看看
- VLC Media Player
- PotPlayer

#### 5.2.6 停止服务

```bash
/data/server/nginx-flv/sbin/nginx -s stop
```

---

### 5.3 一致性哈希模块实践

#### 5.3.1 环境准备

```bash
# 进入nginx-app容器
docker compose exec -it nginx-app bash

# 克隆一致性哈希模块
cd /data/codes
git clone https://github.com/replay/ngx_http_consistent_hash.git

# 验证
ls -l ngx_http_consistent_hash/
```

#### 5.3.2 编译 Nginx with 一致性哈希模块

```bash
cd /data/softs/nginx-1.27.5

# 清理之前的编译
make clean

# 配置编译选项
./configure \
  --prefix=/data/server/nginx-lb \
  --add-module=/data/codes/ngx_http_consistent_hash

# 编译安装
make && make install

# 验证模块
/data/server/nginx-lb/sbin/nginx -V 2>&1 | grep consistent
# 输出: configure arguments: --prefix=/data/server/nginx-lb --add-module=/data/codes/ngx_http_consistent_hash
```

#### 5.3.3 配置后端 Web 服务

```bash
# 创建配置目录
mkdir -p /data/server/nginx-lb/conf.d

# 修改主配置
cat > /data/server/nginx-lb/conf/nginx.conf <<'EOF'
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    include /data/server/nginx-lb/conf.d/*.conf;
}
EOF

# 创建后端 Web 页面
mkdir -p /data/server/nginx/web{1..3}
echo "nginx web1" > /data/server/nginx/web1/index.html
echo "nginx web2" > /data/server/nginx/web2/index.html
echo "nginx web3" > /data/server/nginx/web3/index.html

# 创建后端 Web 配置
cat > /data/server/nginx-lb/conf.d/web.conf <<'EOF'
server {
    listen 80 default_server;
    server_name www.a.com;
    root /data/server/nginx/web1;
    access_log /data/server/nginx/web1/web1.log;
}

server {
    listen 80;
    server_name www.b.com;
    root /data/server/nginx/web2;
    access_log /data/server/nginx/web2/web2.log;
}

server {
    listen 80;
    server_name www.c.com;
    root /data/server/nginx/web3;
    access_log /data/server/nginx/web3/web3.log;
}
EOF
```

#### 5.3.4 配置一致性哈希负载均衡

```bash
cat > /data/server/nginx-lb/conf.d/lb.conf <<'EOF'
upstream backend {
    consistent_hash $request_uri;
    server 127.0.0.1:80;
}

server {
    listen 8083;
    server_name localhost;

    location / {
        proxy_pass http://backend;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

# 检查配置
/data/server/nginx-lb/sbin/nginx -t
```

#### 5.3.5 启动并测试

```bash
# 启动 Nginx
/data/server/nginx-lb/sbin/nginx

# 检查端口
netstat -tnlp | grep nginx

# 简单测试
for i in {1..10}; do
    curl http://localhost:8083
done
# 输出: 会看到 web1/web2/web3 的分布情况
```

#### 5.3.6 Python 脚本测试

创建测试脚本:

```bash
cat > /tmp/nginx_hash_test.py <<'EOF'
#!/usr/bin/env python3
"""
Nginx 一致性哈希负载均衡测试脚本
"""
import requests
from collections import defaultdict

# 测试配置
NGINX_URL = "http://10.0.7.80:8083"
TOTAL_REQUESTS = 100

def test_distribution(servers):
    """测试请求分发情况"""
    distribution = defaultdict(int)

    for i in range(TOTAL_REQUESTS):
        headers = {'Host': 'www.a.com' if i % 3 == 0 else
                          'www.b.com' if i % 3 == 1 else 'www.c.com'}
        try:
            response = requests.get(NGINX_URL, headers=headers, timeout=2)
            backend = response.text.strip()
            distribution[backend] += 1
        except Exception as e:
            print(f"请求失败: {e}")

    print("\n请求分发情况:")
    for backend, count in sorted(distribution.items()):
        print(f"{backend}: {count} 次请求")

    return distribution

def main():
    print("=" * 50)
    print("Nginx 一致性哈希负载均衡测试")
    print("=" * 50)

    # 初始测试
    servers = ['www.a.com', 'www.b.com', 'www.c.com']
    test_distribution(servers)

    # 模拟移除一台服务器
    print("\n模拟移除 www.b.com 服务器...")
    servers.remove('www.b.com')
    test_distribution(servers)

    # 模拟恢复服务器
    print("\n模拟恢复 www.b.com 服务器...")
    servers.append('www.b.com')
    test_distribution(servers)

if __name__ == "__main__":
    main()
EOF

chmod +x /tmp/nginx_hash_test.py
```

运行测试:

```bash
# 安装 requests 库
apt install -y python3-pip
pip3 install requests

# 运行测试
python3 /tmp/nginx_hash_test.py
```

**预期输出**:
```
==================================================
Nginx 一致性哈希负载均衡测试
==================================================

请求分发情况:
www.a.com: 34 次请求
www.b.com: 35 次请求
www.c.com: 31 次请求

模拟移除 www.b.com 服务器...

请求分发情况:
www.a.com: 57 次请求
www.c.com: 58 次请求

模拟恢复 www.b.com 服务器...

请求分发情况:
www.a.com: 69 次请求
www.c.com: 72 次请求
www.b.com: 24 次请求
```

#### 5.3.7 停止服务

```bash
/data/server/nginx-lb/sbin/nginx -s stop
```

---

## 🔥 第六部分:Tengine实践

### 6.1 Tengine简介

**Tengine** 是阿里巴巴基于 Nginx 定制的高性能Web服务器。

**主要特点**:
- 起源于淘宝网内部需求
- 针对高并发场景优化
- 支持动态模块加载
- 内置 WebSocket 支持

**官网**: https://tengine.taobao.org/

---

### 6.2 编译环境准备

#### 6.2.1 进入容器

```bash
docker compose exec -it tengine-server bash
```

#### 6.2.2 安装编译依赖

```bash
apt update
apt install -y gcc libssl-dev libpcre3-dev zlib1g-dev make wget
```

#### 6.2.3 创建软件用户

```bash
# 创建 nginx 用户组和用户
groupadd -g 888 nginx
useradd -r -g nginx -u 888 -s /sbin/nologin nginx

# 验证
id nginx
# 输出: uid=888(nginx) gid=888(nginx) groups=888(nginx)
```

---

### 6.3 编译安装 Tengine

#### 6.3.1 获取源码

```bash
cd /tmp
wget https://tengine.taobao.org/download/tengine-3.1.0.tar.gz

# 解压
tar xf tengine-3.1.0.tar.gz
cd tengine-3.1.0/
```

#### 6.3.2 配置编译选项

```bash
./configure \
  --prefix=/data/server/tengine \
  --user=nginx \
  --group=nginx \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-http_realip_module \
  --with-http_stub_status_module \
  --with-http_gzip_static_module \
  --with-pcre

# 查看配置摘要
# Configuration summary
#   + using system PCRE library
#   + using system OpenSSL library
#   + using system zlib library
```

#### 6.3.3 编译安装

```bash
# 编译
make

# 安装
make install

# 验证安装
ls -l /data/server/tengine/
# 输出: conf/  html/  logs/  modules/  sbin/
```

#### 6.3.4 检查版本

```bash
/data/server/tengine/sbin/nginx -v
# 输出:
# Tengine version: Tengine/3.1.0
# nginx version: nginx/1.24.0

/data/server/tengine/sbin/nginx -V
# 输出: 编译参数详情
```

---

### 6.4 配置和启动 Tengine

#### 6.4.1 基础配置

```bash
# Tengine 默认配置已经可用
cat /data/server/tengine/conf/nginx.conf

# 检查配置
/data/server/tengine/sbin/nginx -t
# 输出:
# nginx: the configuration file /data/server/tengine/conf/nginx.conf syntax is ok
# nginx: configuration file /data/server/tengine/conf/nginx.conf test is successful
```

#### 6.4.2 启动 Tengine

```bash
# 启动
/data/server/tengine/sbin/nginx

# 检查进程
ps aux | grep nginx
# 输出:
# nginx    12345  master process /data/server/tengine/sbin/nginx
# nginx    12346  worker process

# 检查端口
netstat -tnlp | grep 80
# 输出: tcp  0  0  0.0.0.0:80  0.0.0.0:*  LISTEN  12345/nginx
```

#### 6.4.3 测试访问

```bash
# 容器内测试
curl http://localhost -I
# 输出:
# HTTP/1.1 200 OK
# Server: Tengine/3.1.0
# Date: ...
# Content-Type: text/html
# Content-Length: 612

# 查看完整内容
curl http://localhost
# 输出:
# <!DOCTYPE html>
# <html>
# <head>
# <title>Welcome to tengine!</title>
# ...
```

**宿主机浏览器访问**:
```
http://10.0.0.13:8083
```

**预期页面**:
```
Welcome to tengine!

If you see this page, the tengine web server is successfully
installed and working. Further configuration is required.

For online documentation and support please refer to tengine.taobao.org.

Thank you for using tengine.
```

---

### 6.5 Tengine 特性演示

#### 6.5.1 动态模块加载示例

```bash
# Tengine 支持动态模块加载
# 查看可用模块
ls /data/server/tengine/modules/

# 在配置中加载模块
cat >> /data/server/tengine/conf/nginx.conf <<'EOF'
# 动态加载模块示例
# load_module modules/ngx_http_xxx_module.so;
EOF
```

#### 6.5.2 健康检查示例

Tengine 内置健康检查功能:

```bash
cat > /data/server/tengine/conf/conf.d/healthcheck.conf <<'EOF'
upstream backend {
    server 10.0.7.80:80;
    server 10.0.7.81:80;

    # 健康检查配置
    check interval=3000 rise=2 fall=5 timeout=1000 type=http;
    check_http_send "HEAD / HTTP/1.0\r\n\r\n";
    check_http_expect_alive http_2xx http_3xx;
}

server {
    listen 8084;

    location / {
        proxy_pass http://backend;
    }

    location /status {
        check_status;
        access_log off;
    }
}
EOF

# 重载配置
/data/server/tengine/sbin/nginx -s reload

# 查看健康检查状态
curl http://localhost:8084/status
```

---

### 6.6 停止 Tengine

```bash
# 优雅停止
/data/server/tengine/sbin/nginx -s quit

# 快速停止
/data/server/tengine/sbin/nginx -s stop
```

---

## 🌟 第七部分:OpenResty实践

### 7.1 OpenResty简介

**OpenResty** 是基于 Nginx 与 Lua 的高性能 Web 平台。

**核心特性**:
- 集成 LuaJIT 2.1
- 丰富的 Lua 库
- 非阻塞 I/O
- 支持 10K+ 并发

**官网**: https://openresty.org/cn/

---

### 7.2 编译环境准备

#### 7.2.1 进入容器

```bash
docker compose exec -it openresty-server bash
```

#### 7.2.2 安装编译依赖

```bash
apt update
apt install -y gcc libssl-dev libpcre3-dev zlib1g-dev make wget
```

#### 7.2.3 创建软件用户

```bash
groupadd -g 888 nginx
useradd -r -g nginx -u 888 -s /sbin/nologin nginx
```

---

### 7.3 编译安装 OpenResty

#### 7.3.1 获取源码

```bash
cd /tmp
wget https://openresty.org/download/openresty-1.25.3.1.tar.gz

# 解压
tar xf openresty-1.25.3.1.tar.gz
cd openresty-1.25.3.1/
```

#### 7.3.2 配置编译选项

```bash
./configure \
  --prefix=/data/server/openresty \
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

#### 7.3.3 编译安装

```bash
# 编译(时间较长,约5-10分钟)
make

# 安装
make install

# 验证安装
ls -l /data/server/openresty/
# 输出: bin/  COPYRIGHT  luajit/  lualib/  nginx/  pod/  resty.index  site/
```

#### 7.3.4 检查版本

```bash
/data/server/openresty/nginx/sbin/nginx -v
# 输出: nginx version: openresty/1.25.3.1

# 查看 LuaJIT 版本
/data/server/openresty/luajit/bin/luajit -v
# 输出: LuaJIT 2.1.0-beta3 -- Copyright (C) 2005-2017 Mike Pall.
```

---

### 7.4 配置和启动 OpenResty

#### 7.4.1 启动服务

```bash
# 检查配置
/data/server/openresty/nginx/sbin/nginx -t

# 启动
/data/server/openresty/nginx/sbin/nginx

# 检查进程
ps aux | grep nginx

# 检查端口
netstat -tnlp | grep 80
```

#### 7.4.2 测试访问

```bash
# 容器内测试
curl http://localhost -I
# 输出:
# HTTP/1.1 200 OK
# Server: openresty/1.25.3.1
```

**宿主机浏览器访问**:
```
http://10.0.0.13:8084
```

---

### 7.5 Lua 脚本测试

#### 7.5.1 创建 Lua 脚本目录

```bash
mkdir -p /data/server/openresty/lua
cd /data/server/openresty/lua
```

#### 7.5.2 创建测试脚本

```bash
# 创建 test.lua
cat > test.lua <<'EOF'
ngx.say("Hello, OpenResty with Lua!")
EOF
```

#### 7.5.3 配置 Nginx 支持 Lua

```bash
cat > /data/server/openresty/nginx/conf/nginx.conf <<'EOF'
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    # Lua模块配置
    lua_package_path "/data/server/openresty/lua/?.lua;;";
    lua_shared_dict my_cache 10m;

    server {
        listen 80;
        server_name localhost;

        # 使用外部Lua文件
        location /test {
            default_type text/html;
            content_by_lua_file /data/server/openresty/lua/test.lua;
        }

        # 使用内联Lua代码
        location /lua {
            default_type text/html;
            content_by_lua_block {
                ngx.say("<p>hello, world with lua</p>")
            }
        }

        # Lua计算示例
        location /calc {
            default_type text/html;
            content_by_lua_block {
                local a = tonumber(ngx.var.arg_a) or 0
                local b = tonumber(ngx.var.arg_b) or 0
                ngx.say("<h1>Calculator</h1>")
                ngx.say("<p>a = ", a, "</p>")
                ngx.say("<p>b = ", b, "</p>")
                ngx.say("<p>a + b = ", a + b, "</p>")
                ngx.say("<p>a * b = ", a * b, "</p>")
            }
        }

        # Redis交互示例
        location /redis-test {
            default_type text/html;
            content_by_lua_block {
                local redis = require "resty.redis"
                local red = redis:new()

                red:set_timeout(1000)

                local ok, err = red:connect("10.0.7.82", 6379)
                if not ok then
                    ngx.say("Failed to connect to Redis: ", err)
                    return
                end

                ok, err = red:set("test_key", "Hello from Lua!")
                if not ok then
                    ngx.say("Failed to set key: ", err)
                    return
                end

                local res, err = red:get("test_key")
                if not res then
                    ngx.say("Failed to get key: ", err)
                    return
                end

                ngx.say("<h1>Redis Test</h1>")
                ngx.say("<p>Value: ", res, "</p>")

                red:close()
            }
        }
    }
}
EOF
```

#### 7.5.4 重载配置

```bash
/data/server/openresty/nginx/sbin/nginx -s reload
```

#### 7.5.5 测试 Lua 功能

```bash
# 测试外部Lua文件
curl http://localhost/test
# 输出: Hello, OpenResty with Lua!

# 测试内联Lua代码
curl http://localhost/lua
# 输出: <p>hello, world with lua</p>

# 测试计算功能
curl "http://localhost/calc?a=10&b=20"
# 输出:
# <h1>Calculator</h1>
# <p>a = 10</p>
# <p>b = 20</p>
# <p>a + b = 30</p>
# <p>a * b = 200</p>

# 测试Redis交互
curl http://localhost/redis-test
# 输出:
# <h1>Redis Test</h1>
# <p>Value: Hello from Lua!</p>
```

---

### 7.6 高级 Lua 示例

#### 7.6.1 JSON API 示例

```bash
cat > /data/server/openresty/lua/api.lua <<'EOF'
-- 导入cjson库
local cjson = require "cjson"

-- 设置响应类型
ngx.header.content_type = "application/json"

-- 构造响应数据
local response = {
    status = "success",
    code = 200,
    data = {
        message = "Hello from Lua API",
        timestamp = ngx.now(),
        request_uri = ngx.var.request_uri,
        request_method = ngx.var.request_method
    }
}

-- 输出JSON
ngx.say(cjson.encode(response))
EOF

# 添加路由配置
cat >> /data/server/openresty/nginx/conf/nginx.conf <<'EOF'
location /api {
    content_by_lua_file /data/server/openresty/lua/api.lua;
}
EOF

# 重载
/data/server/openresty/nginx/sbin/nginx -s reload

# 测试
curl http://localhost/api
# 输出: {"status":"success","code":200,"data":{...}}
```

---

### 7.7 停止 OpenResty

```bash
/data/server/openresty/nginx/sbin/nginx -s quit
```

---

## 🐍 第八部分:Django项目部署

### 8.1 Python环境准备

#### 8.1.1 进入容器

```bash
docker compose exec -it django-app bash
```

#### 8.1.2 安装Python和依赖

```bash
apt update
apt install -y python3 python3-pip python3-dev python3.12-venv \
               build-essential nginx
```

#### 8.1.3 创建Python虚拟环境

```bash
# 创建虚拟环境
python3 -m venv /data/myprojectenv

# 激活虚拟环境
source /data/myprojectenv/bin/activate

# 验证
which python
# 输出: /data/myprojectenv/bin/python

python --version
# 输出: Python 3.12.x
```

---

### 8.2 Django环境配置

#### 8.2.1 配置pip源

```bash
# 配置国内镜像源(豆瓣源)
pip config set global.index-url https://pypi.doubanio.com/simple
pip config set install.trusted-host pypi.doubanio.com

# 验证配置
pip config list
# 输出:
# global.index-url='https://pypi.doubanio.com/simple'
# install.trusted-host='pypi.doubanio.com'
```

#### 8.2.2 安装Django

```bash
# 安装Django
pip install django

# 验证安装
python -m django --version
# 输出: 5.2
```

---

### 8.3 创建Django项目

#### 8.3.1 创建项目

```bash
cd /data

# 创建项目
django-admin startproject myproject

# 查看项目结构
cd myproject
tree .
# 输出:
# .
# ├── manage.py
# └── myproject
#     ├── __init__.py
#     ├── asgi.py
#     ├── settings.py
#     ├── urls.py
#     └── wsgi.py
```

#### 8.3.2 配置Django设置

```bash
# 编辑settings.py
vim /data/myproject/myproject/settings.py

# 修改以下配置:
```

```python
# ALLOWED_HOSTS 配置
ALLOWED_HOSTS = ['10.0.7.85', '10.0.0.13', 'localhost', '127.0.0.1']

# 静态文件配置
import os
STATIC_URL = '/static/'
STATIC_ROOT = os.path.join(BASE_DIR, 'static')

# 数据库配置(使用默认SQLite)
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}
```

---

### 8.4 Django项目初始化

#### 8.4.1 数据库迁移

```bash
cd /data/myproject

# 生成迁移文件
python manage.py makemigrations
# 输出: No changes detected

# 执行迁移
python manage.py migrate
# 输出:
# Operations to perform:
#   Apply all migrations: admin, auth, contenttypes, sessions
# Running migrations:
#   Applying contenttypes.0001_initial... OK
#   Applying auth.0001_initial... OK
#   ...
#   Applying sessions.0001_initial... OK
```

#### 8.4.2 创建超级用户

```bash
python manage.py createsuperuser

# 按提示输入:
# Username: admin
# Email address: admin@qq.com
# Password: 123456
# Password (again): 123456
# Bypass password validation and create user anyway? [y/N]: y
# Superuser created successfully.
```

---

### 8.5 收集静态文件

```bash
# 收集静态文件
python manage.py collectstatic

# 输出:
# 127 static files copied to '/data/myproject/static'.

# 验证
ls -l /data/myproject/static/
# 输出: admin/  (Django管理后台的静态文件)
```

---

### 8.6 测试Django开发服务器

```bash
# 启动开发服务器
python manage.py runserver 0.0.0.0:8000

# 输出:
# Watching for file changes with StatReloader
# Performing system checks...
#
# System check identified no issues (0 silenced).
# October 18, 2025 - 12:58:39
# Django version 5.2, using settings 'myproject.settings'
# Starting development server at http://0.0.0.0:8000/
# Quit the server with CONTROL-C.
```

**浏览器访问**:
```
http://10.0.0.13:8000
```

**预期页面**:
- Django默认欢迎页面
- 访问 `http://10.0.0.13:8000/admin` 进入管理后台
- 使用 admin/123456 登录

**测试完成后按 Ctrl+C 停止开发服务器**。

---

### 8.7 部署uWSGI

#### 8.7.1 安装uWSGI

```bash
# 确保在虚拟环境中
source /data/myprojectenv/bin/activate

# 安装uWSGI
pip install uwsgi

# 验证安装
which uwsgi
# 输出: /data/myprojectenv/bin/uwsgi

uwsgi --version
# 输出: 2.0.29
```

#### 8.7.2 创建uWSGI配置文件

```bash
cd /data/myproject

cat > uwsgi.ini <<'EOF'
[uwsgi]
# Django-related settings
# Django项目的根目录
chdir = /data/myproject

# Django的wsgi文件
module = myproject.wsgi:application

# Python虚拟环境路径
home = /data/myprojectenv

# 进程管理
master = true
processes = 5
threads = 2

# Socket文件(用于Nginx通信)
socket = /data/myproject/myproject.sock
chmod-socket = 666

# 日志文件
logto = /data/myproject/uwsgi.log

# 运行用户
uid = www-data
gid = www-data

# 退出时清理环境
vacuum = true
EOF
```

**配置说明**:

| 配置项 | 值 | 说明 |
|-------|---|------|
| **chdir** | /data/myproject | 项目根目录 |
| **module** | myproject.wsgi:application | WSGI应用 |
| **home** | /data/myprojectenv | 虚拟环境路径 |
| **processes** | 5 | worker进程数 |
| **threads** | 2 | 每个进程的线程数 |
| **socket** | myproject.sock | Unix socket文件 |
| **chmod-socket** | 666 | socket文件权限 |
| **uid/gid** | www-data | 运行用户 |

#### 8.7.3 创建www-data用户

```bash
# 创建www-data用户(如果不存在)
id www-data || useradd -r -s /bin/false www-data

# 设置项目权限
chown -R www-data:www-data /data/myproject
chmod -R 755 /data/myproject
```

#### 8.7.4 测试uWSGI

```bash
# 前台运行测试
uwsgi --ini /data/myproject/uwsgi.ini

# 输出:
# *** WARNING: you are running uWSGI as root !!! (use the --uid flag) ***
# Python main interpreter initialized at 0x...
# python threads support enabled
# your server socket listen backlog is limited to 100 connections
# your mercy for graceful operations on workers is 60 seconds
# mapped 437520 bytes (427 KB) for 5 cores
# *** Operational MODE: preforking ***
# WSGI app 0 (mountpoint='') ready in 1 seconds on interpreter 0x... pid: 12345 (default app)
# *** uWSGI is running in multiple interpreter mode ***
# spawned uWSGI master process (pid: 12345)
# spawned uWSGI worker 1 (pid: 12346, cores: 1)
# spawned uWSGI worker 2 (pid: 12347, cores: 1)
# spawned uWSGI worker 3 (pid: 12348, cores: 1)
# spawned uWSGI worker 4 (pid: 12349, cores: 1)
# spawned uWSGI worker 5 (pid: 12350, cores: 1)

# 如果没有报错,按 Ctrl+C 停止
```

⚠️ **注意**: 此时浏览器访问 `http://10.0.0.13:8000` 无法访问,因为uWSGI使用的是Unix socket,不是TCP端口。

---

### 8.8 配置systemd服务

#### 8.8.1 创建uWSGI服务文件

```bash
cat > /etc/systemd/system/uwsgi.service <<'EOF'
[Unit]
Description=uWSGI Emperor service
After=syslog.target network.target

[Service]
ExecStart=/data/myprojectenv/bin/uwsgi --ini /data/myproject/uwsgi.ini
Restart=always
KillSignal=SIGQUIT
Type=notify
NotifyAccess=all

[Install]
WantedBy=multi-user.target
EOF
```

#### 8.8.2 启动uWSGI服务

```bash
# 重载systemd配置
systemctl daemon-reload

# 启动服务
systemctl start uwsgi.service

# 查看状态
systemctl status uwsgi.service
# 输出:
# ● uwsgi.service - uWSGI Emperor service
#    Loaded: loaded (/etc/systemd/system/uwsgi.service; disabled)
#    Active: active (running) since ...
#    ...

# 设置开机自启
systemctl enable uwsgi.service

# 检查socket文件
ls -l /data/myproject/myproject.sock
# 输出: srw-rw-rw- 1 www-data www-data 0 Oct 18 10:00 myproject.sock
```

---

### 8.9 配置Nginx反向代理

#### 8.9.1 创建Nginx配置

```bash
cat > /etc/nginx/sites-available/django <<'EOF'
upstream django {
    server unix:///data/myproject/myproject.sock;
}

server {
    listen 80;
    server_name 10.0.7.85 10.0.0.13;
    charset utf-8;

    # 最大上传大小
    client_max_body_size 75M;

    # 静态文件
    location /static {
        alias /data/myproject/static;
    }

    # 媒体文件
    location /media {
        alias /data/myproject/media;
    }

    # 动态请求转发到Django
    location / {
        uwsgi_pass django;
        include /etc/nginx/uwsgi_params;
    }
}
EOF

# 创建软链接
ln -sf /etc/nginx/sites-available/django /etc/nginx/sites-enabled/

# 删除默认配置
rm -f /etc/nginx/sites-enabled/default

# 测试配置
nginx -t
# 输出:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful
```

#### 8.9.2 启动Nginx

```bash
# 启动Nginx
systemctl start nginx

# 查看状态
systemctl status nginx

# 检查端口
netstat -tnlp | grep :80
# 输出: tcp  0  0  0.0.0.0:80  0.0.0.0:*  LISTEN  12345/nginx
```

---

### 8.10 访问测试

#### 8.10.1 浏览器访问

```bash
# 访问Django应用
http://10.0.0.13

# 访问管理后台
http://10.0.0.13/admin
```

#### 8.10.2 curl测试

```bash
# 测试首页
curl -I http://localhost
# 输出:
# HTTP/1.1 200 OK
# Server: nginx
# Content-Type: text/html; charset=utf-8

# 测试静态文件
curl -I http://localhost/static/admin/css/base.css
# 输出:
# HTTP/1.1 200 OK
# Content-Type: text/css
```

---

### 8.11 Django部署检查清单

- [ ] Python虚拟环境创建并激活
- [ ] Django安装并配置ALLOWED_HOSTS
- [ ] 数据库迁移完成
- [ ] 超级用户创建成功
- [ ] 静态文件收集完成
- [ ] uWSGI配置文件正确
- [ ] uWSGI服务启动正常
- [ ] Nginx配置正确
- [ ] Nginx服务启动正常
- [ ] 浏览器可以访问应用
- [ ] 管理后台可以登录

---

## 🌈 第九部分:Flask项目部署

### 9.1 Flask简介

**Flask** 是基于 Python 的轻量级 Web 框架,以简洁和灵活著称。

#### 生产环境部署架构

```
┌─────────────────────────────────────────────────────────────┐
│                         客户端浏览器                          │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ HTTP 请求
┌──────────────────┴──────────────────────────────────────────┐
│                         Nginx                                │
│  - 处理静态文件                                               │
│  - 反向代理动态请求到 Gunicorn                                │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ HTTP 协议
┌──────────────────┴──────────────────────────────────────────┐
│                       Gunicorn                               │
│  - WSGI 服务器                                               │
│  - 管理多个 worker 进程                                       │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ WSGI 协议
┌──────────────────┴──────────────────────────────────────────┐
│                      Flask 应用                               │
│  - 处理业务逻辑                                               │
│  - 路由分发                                                   │
└─────────────────────────────────────────────────────────────┘
```

#### 核心组件

| 组件 | 作用 | 说明 |
|------|------|------|
| **Nginx** | Web服务器 | 处理静态文件、反向代理 |
| **Gunicorn** | WSGI服务器 | Python应用与Web服务器之间的桥梁 |
| **Flask** | Web框架 | 轻量级、灵活的Web框架 |

---

### 9.2 环境准备

#### 9.2.1 进入容器

```bash
# 在宿主机执行
docker compose exec -it nginx-app bash
```

#### 9.2.2 安装Python环境

```bash
apt update
apt install -y python3 python3-pip nginx build-essential python3-dev python3.12-venv
```

#### 9.2.3 创建Python虚拟环境

```bash
# 创建虚拟环境
cd /data
python3 -m venv myflaskenv

# 激活虚拟环境
source /data/myflaskenv/bin/activate

# 验证环境
which python
# 输出: /data/myflaskenv/bin/python

python --version
# 输出: Python 3.12.x
```

---

### 9.3 Flask应用开发

#### 9.3.1 配置pip源

```bash
# 方法1: 手工指定源方式
pip install flask --index-url https://mirrors.aliyun.com/pypi/simple/

# 方法2: 配置默认源(推荐)
pip config set global.index-url https://pypi.doubanio.com/simple
pip config set install.trusted-host pypi.doubanio.com

# 验证配置
pip config list
# 输出:
# global.index-url='https://pypi.doubanio.com/simple'
# install.trusted-host='pypi.doubanio.com'
```

#### 9.3.2 安装Flask

```bash
pip install flask

# 验证安装
python -c "import flask; print(flask.__version__)"
# 输出: 3.0.x
```

#### 9.3.3 创建Flask应用

```bash
# 创建项目目录
mkdir -p /data/flaskapp
cd /data/flaskapp

# 创建应用文件
cat > app.py <<'EOF'
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello_world():
    return 'Hello, World!'

if __name__ == '__main__':
    app.run()
EOF
```

#### 9.3.4 测试运行

```bash
# 设置FLASK_APP环境变量
export FLASK_APP=app.py

# 启动开发服务器
flask run --host=0.0.0.0 --port=5000

# 输出:
# Serving Flask app 'app.py'
# Debug mode: off
# WARNING: This is a development server. Do not use it in a production deployment.
# Use a production WSGI server instead.
# * Running on all addresses (0.0.0.0)
# * Running on http://127.0.0.1:5000
# * Running on http://10.0.7.80:5000
# Press CTRL+C to quit

# ⚠️ 页面会阻塞,另起一个终端测试
```

**另起终端测试**:

```bash
docker compose exec -it nginx-app bash

curl localhost:5000
# 输出: Hello, World!

# 测试完成后,按 Ctrl+C 终止Flask应用
```

---

### 9.4 Gunicorn部署

#### 9.4.1 安装Gunicorn

```bash
# 确保在虚拟环境中
source /data/myflaskenv/bin/activate

# 安装Gunicorn
pip install gunicorn

# 验证安装
which gunicorn
# 输出: /data/myflaskenv/bin/gunicorn

gunicorn --version
# 输出: gunicorn (version 23.0.0)
```

#### 9.4.2 创建Gunicorn配置文件

```bash
cd /data/flaskapp

cat > gunicorn.conf.py <<'EOF'
# 绑定的地址和端口
bind = '10.0.7.80:5000'

# 工作进程数量
# 推荐: (2 * CPU核心数) + 1
workers = 4

# 工作模式
# - sync: 同步worker(默认)
# - gevent: 异步worker(需要安装gevent)
# - eventlet: 异步worker(需要安装eventlet)
worker_class = 'sync'

# 每个工作进程处理的最大请求数
# 超过此数量会重启工作进程,防止内存泄漏
max_requests = 1000

# 日志文件路径
accesslog = '/var/log/gunicorn/access.log'
errorlog = '/var/log/gunicorn/error.log'

# 日志级别
# - debug: 调试信息
# - info: 一般信息
# - warning: 警告信息
# - error: 错误信息
# - critical: 严重错误
loglevel = 'info'
EOF
```

**配置参数详解**:

| 参数 | 说明 | 推荐值 | 备注 |
|------|------|--------|------|
| **bind** | 绑定地址和端口 | IP:PORT | 生产环境使用内网IP |
| **workers** | worker进程数 | (2 * CPU) + 1 | 根据CPU核心数调整 |
| **worker_class** | worker类型 | sync/gevent/eventlet | 同步场景用sync |
| **max_requests** | 最大请求数 | 1000 | 防止内存泄漏 |
| **accesslog** | 访问日志路径 | /var/log/... | 需要创建目录 |
| **errorlog** | 错误日志路径 | /var/log/... | 需要创建目录 |
| **loglevel** | 日志级别 | info | 生产环境用info |

#### 9.4.3 启动Gunicorn

```bash
# 创建日志目录
mkdir -p /var/log/gunicorn/

# 启动Gunicorn(前台运行)
gunicorn -c gunicorn.conf.py app:app

# 输出:
# [INFO] Starting gunicorn 23.0.0
# [INFO] Listening at: http://10.0.7.80:5000 (12345)
# [INFO] Using worker: sync
# [INFO] Booting worker with pid: 12346
# [INFO] Booting worker with pid: 12347
# [INFO] Booting worker with pid: 12348
# [INFO] Booting worker with pid: 12349

# ⚠️ 页面出现阻塞现象,另起终端测试
```

**另起终端测试**:

```bash
docker compose exec -it nginx-app bash

# 检查端口(只能通过IP访问,因为bind限制)
netstat -tnulp | grep 5000
# 输出: tcp  0  0  10.0.7.80:5000  0.0.0.0:*  LISTEN  12345/python3

# 测试访问
curl 10.0.7.80:5000
# 输出: Hello, World!

# 尝试localhost访问(会失败)
curl localhost:5000
# 输出: curl: (7) Failed to connect to localhost port 5000 after 0 ms: Couldn't connect to server

# 测试完成后,返回原终端按 Ctrl+C 停止Gunicorn
```

#### 9.4.4 配置systemd服务

⚠️ **注意**: Docker容器环境通常不运行systemd,以下配置仅供参考。在生产环境中使用宿主机或虚拟机时可以配置。

```bash
cat > /etc/systemd/system/gunicorn.service <<'EOF'
[Unit]
Description=Gunicorn instance to serve Flask app
After=network.target

[Service]
# 工作目录
WorkingDirectory=/data/flaskapp

# 虚拟环境PATH
Environment="PATH=/data/myflaskenv/bin"

# 启动命令
ExecStart=/data/myflaskenv/bin/gunicorn -c /data/flaskapp/gunicorn.conf.py app:app

# 自动重启
Restart=always

[Install]
WantedBy=multi-user.target
EOF
```

**配置说明**:

| 配置项 | 值 | 说明 |
|-------|---|------|
| **WorkingDirectory** | /data/flaskapp | Flask项目根目录 |
| **Environment** | PATH=... | 虚拟环境的PATH |
| **ExecStart** | gunicorn命令 | 完整的启动命令 |
| **Restart** | always | 失败时自动重启 |

**启动服务**(在支持systemd的环境中):

```bash
# 重载systemd配置
systemctl daemon-reload

# 启动服务
systemctl start gunicorn.service

# 查看状态
systemctl is-active gunicorn.service
# 输出: active

# 设置开机自启
systemctl enable gunicorn.service

# 测试访问
curl 10.0.7.80:5000
# 输出: Hello, World!
```

---

### 9.5 Nginx反向代理

#### 9.5.1 安装Nginx

```bash
# Nginx通常已安装,如未安装:
apt install -y nginx
```

#### 9.5.2 清理默认配置

```bash
rm -f /etc/nginx/sites-enabled/default
```

#### 9.5.3 创建Flask反向代理配置

```bash
cat > /etc/nginx/conf.d/flaskapp.conf <<'EOF'
server {
    listen 5001;
    server_name 10.0.7.80;

    location / {
        # 反向代理到Gunicorn
        proxy_pass http://10.0.7.80:5000;

        # 传递原始请求头
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
```

**配置说明**:

| 配置项 | 说明 | 作用 |
|-------|------|------|
| **proxy_pass** | 后端地址 | 转发到Gunicorn |
| **Host** | 主机头 | 保持原始Host信息 |
| **X-Real-IP** | 客户端真实IP | 记录真实来源IP |
| **X-Forwarded-For** | IP转发链 | 记录代理链路 |
| **X-Forwarded-Proto** | 协议类型 | 记录原始协议(http/https) |

#### 9.5.4 测试配置

```bash
# 检测配置文件语法
nginx -t

# 输出:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful
```

#### 9.5.5 启动Nginx

```bash
# 启动Nginx服务
systemctl start nginx.service

# 查看状态
systemctl is-active nginx.service
# 输出: active

# 检查端口
netstat -tnlp | grep nginx
# 输出:
# tcp  0  0  0.0.0.0:5001  0.0.0.0:*  LISTEN  12345/nginx
# tcp  0  0  0.0.0.0:80    0.0.0.0:*  LISTEN  12345/nginx
```

#### 9.5.6 访问测试

```bash
# 容器内测试
curl http://10.0.7.80:5001
# 输出: Hello, World!

# 宿主机浏览器访问
# http://宿主机IP:5001
# 例如: http://10.0.0.13:5001
```

---

## 🚀 第十部分:FastAPI项目部署

### 10.1 FastAPI和ASGI简介

#### 10.1.1 ASGI简介

**ASGI (Asynchronous Server Gateway Interface)** 是异步服务器网关接口,是WSGI的异步版本。

**主要特点**:
- **异步支持**: 处理高并发的I/O操作
- **WebSocket支持**: 原生支持WebSocket协议
- **HTTP/2支持**: 支持HTTP/2协议
- **长连接支持**: 适合实时应用

**ASGI vs WSGI**:

| 特性 | WSGI | ASGI |
|------|------|------|
| **同步/异步** | 同步 | 异步 |
| **并发模型** | 多进程/多线程 | 事件循环 |
| **WebSocket** | 不支持 | 支持 |
| **HTTP/2** | 不支持 | 支持 |
| **适用场景** | 传统Web应用 | 实时应用、高并发 |

#### 10.1.2 FastAPI简介

**FastAPI** 是基于Python 3.6+ 类型提示的现代、快速(高性能) Web框架。

**核心特点**:
- **快速**: 性能媲美NodeJS和Go
- **类型检查**: 基于Python类型提示
- **自动文档**: 自动生成OpenAPI和JSON Schema
- **异步支持**: 原生支持async/await

#### 10.1.3 Uvicorn简介

**Uvicorn** 是基于uvloop和httptools的轻量级ASGI服务器。

**主要特点**:
- **高性能**: 使用uvloop(libuv的Python绑定)
- **ASGI支持**: 完整的ASGI协议支持
- **简单易用**: 配置简单,易于部署

#### 10.1.4 生产环境部署架构

```
┌─────────────────────────────────────────────────────────────┐
│                         客户端浏览器                          │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ HTTP 请求
┌──────────────────┴──────────────────────────────────────────┐
│                         Nginx                                │
│  - 处理静态文件                                               │
│  - 反向代理动态请求到 Uvicorn                                 │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ HTTP 协议
┌──────────────────┴──────────────────────────────────────────┐
│                       Uvicorn                                │
│  - ASGI 服务器                                               │
│  - 异步事件循环                                               │
└──────────────────┬──────────────────────────────────────────┘
                   ↓ ASGI 协议
┌──────────────────┴──────────────────────────────────────────┐
│                     FastAPI 应用                              │
│  - 异步请求处理                                               │
│  - 路由分发                                                   │
└─────────────────────────────────────────────────────────────┘
```

---

### 10.2 环境准备

#### 10.2.1 进入容器

```bash
# 在宿主机执行
docker compose exec -it nginx-app bash
```

#### 10.2.2 安装Python环境

```bash
apt update
apt install -y python3 python3-pip nginx build-essential python3-dev python3.12-venv
```

#### 10.2.3 创建Python虚拟环境

```bash
# 创建虚拟环境
cd /data
python3 -m venv myasgienv

# 激活虚拟环境
source /data/myasgienv/bin/activate

# 验证环境
which python
# 输出: /data/myasgienv/bin/python

python --version
# 输出: Python 3.12.x
```

---

### 10.3 FastAPI应用开发

#### 10.3.1 配置pip源

```bash
# 方法1: 手工指定源方式
pip install fastapi --index-url https://mirrors.aliyun.com/pypi/simple/

# 方法2: 配置默认源(推荐)
pip config set global.index-url https://pypi.doubanio.com/simple
pip config set install.trusted-host pypi.doubanio.com

# 验证配置
pip config list
# 输出:
# global.index-url='https://pypi.doubanio.com/simple'
# install.trusted-host='pypi.doubanio.com'
```

#### 10.3.2 安装FastAPI和Uvicorn

```bash
pip install fastapi uvicorn

# 验证安装
python -c "import fastapi; print(fastapi.__version__)"
# 输出: 0.115.x

python -c "import uvicorn; print(uvicorn.__version__)"
# 输出: 0.34.x
```

#### 10.3.3 创建基础FastAPI应用

```bash
# 创建项目目录
mkdir -p /data/fastapp
cd /data/fastapp

# 创建应用文件
cat > main.py <<'EOF'
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
async def read_root():
    return {"Hello": "World"}

@app.get("/items/{item_id}")
async def read_item(item_id: int, q: str = None):
    return {"item_id": item_id, "q": q}
EOF
```

**代码说明**:

| 代码 | 说明 |
|------|------|
| `async def` | 异步函数定义 |
| `@app.get("/")` | 路由装饰器,处理GET请求 |
| `{item_id}` | 路径参数,自动类型转换 |
| `q: str = None` | 查询参数,可选 |

#### 10.3.4 测试运行

```bash
# 启动开发服务器(默认监听127.0.0.1:8000)
uvicorn main:app --reload

# 输出:
# INFO:     Will watch for changes in these directories: ['/data/fastapp']
# INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
# INFO:     Started reloader process [12345] using WatchFiles
# INFO:     Started server process [12346]
# INFO:     Waiting for application startup.
# INFO:     Application startup complete.

# ⚠️ 页面会阻塞,另起一个终端测试
```

**命令参数说明**:

| 参数 | 说明 |
|------|------|
| `main:app` | main.py文件中的app对象 |
| `--reload` | 代码修改后自动重启(仅开发环境使用) |
| `--host` | 监听地址(默认127.0.0.1) |
| `--port` | 监听端口(默认8000) |

**另起终端测试**:

```bash
docker compose exec -it nginx-app bash

# 测试根路径
curl http://127.0.0.1:8000
# 输出: {"Hello":"World"}

# 测试带参数的路径
curl "http://127.0.0.1:8000/items/5?q=test"
# 输出: {"item_id":5,"q":"test"}

# 尝试访问非监听端口(会失败)
curl http://10.0.7.80:8000
# 输出: curl: (7) Failed to connect to 10.0.7.80 port 8000 after 0 ms: Couldn't connect to server

# 测试完成后,返回原终端按 Ctrl+C 停止应用
```

#### 10.3.5 指定监听地址

```bash
# 监听指定IP和端口
uvicorn main:app --host 10.0.7.80 --port 8000

# 输出:
# INFO:     Started server process [12347]
# INFO:     Waiting for application startup.
# INFO:     Application startup complete.
# INFO:     Uvicorn running on http://10.0.7.80:8000 (Press CTRL+C to quit)

# 现在可以通过IP访问
curl http://10.0.7.80:8000
# 输出: {"Hello":"World"}
```

---

### 10.4 异步功能升级

#### 10.4.1 安装异步模块

```bash
# 激活虚拟环境
source /data/myasgienv/bin/activate

# 安装asyncio
pip install asyncio

# 验证安装
python -c "import asyncio; print('asyncio module installed')"
```

#### 10.4.2 添加异步路由

```bash
cat > main.py <<'EOF'
from fastapi import FastAPI
import asyncio

app = FastAPI()

@app.get("/")
async def read_root():
    return {"Hello": "World"}

@app.get("/items/{item_id}")
async def read_item(item_id: int, q: str = None):
    return {"item_id": item_id, "q": q}

@app.get("/db")
async def read_db():
    """模拟异步数据库查询"""
    # 模拟耗时操作(例如数据库查询)
    await asyncio.sleep(0.5)
    return {"message": "Data from database"}
EOF
```

**异步代码说明**:

| 代码 | 说明 |
|------|------|
| `async def` | 定义异步函数 |
| `await` | 等待异步操作完成 |
| `asyncio.sleep()` | 异步休眠,不阻塞事件循环 |

#### 10.4.3 启动服务

```bash
uvicorn main:app --host 10.0.7.80 --port 8000

# 测试异步路由
curl http://10.0.7.80:8000/db
# 输出: {"message":"Data from database"}
# (响应时间约0.5秒)
```

---

### 10.5 httpie测试工具

#### 10.5.1 安装httpie

```bash
# 激活虚拟环境
source /data/myasgienv/bin/activate

# 安装httpie
pip install httpie

# 验证安装
http --version
# 输出: 3.x.x
```

**httpie vs curl**:

| 特性 | curl | httpie |
|------|------|--------|
| **输出格式** | 原始文本 | 彩色格式化 |
| **JSON支持** | 需要手动解析 | 自动解析和高亮 |
| **请求头** | 需要-H参数 | 自动设置 |
| **易用性** | 命令复杂 | 命令简洁 |

#### 10.5.2 测试根路径

```bash
http http://10.0.7.80:8000

# 输出:
# HTTP/1.1 200 OK
# content-length: 17
# content-type: application/json
# date: Thu, 12 Oct 2025 14:52:14 GMT
# server: uvicorn
#
# {
#     "Hello": "World"
# }
```

#### 10.5.3 测试带参数的路径

```bash
http http://10.0.7.80:8000/items/5 q==test

# 输出:
# HTTP/1.1 200 OK
# content-length: 25
# content-type: application/json
# date: Thu, 12 Oct 2025 14:53:20 GMT
# server: uvicorn
#
# {
#     "item_id": 5,
#     "q": "test"
# }
```

**httpie参数说明**:

| 参数 | 说明 | 示例 |
|------|------|------|
| `q==test` | 查询参数 | ?q=test |
| `key=value` | JSON字段(POST) | {"key":"value"} |
| `key:=123` | JSON数字(POST) | {"key":123} |
| `Header:Value` | 请求头 | -H "Header: Value" |

---

### 10.6 异步并发测试

#### 10.6.1 使用xargs并发测试

```bash
# 发送10个并发请求到异步路由
time seq 10 | xargs -I{} -P 10 http GET http://10.0.7.80:8000/db

# 输出(部分):
# HTTP/1.1 200 OK
# content-length: 32
# content-type: application/json
# date: Thu, 12 Oct 2025 01:42:00 GMT
# server: uvicorn
#
# {
#     "message": "Data from database"
# }
# ...
#
# real    0m5.301s
# user    0m3.260s
# sys     0m1.379s
```

**命令解析**:

| 部分 | 说明 |
|------|------|
| `seq 10` | 生成1-10的序列 |
| `xargs -I{}` | 替换占位符 |
| `-P 10` | 并行执行10个进程 |
| `http GET` | httpie GET请求 |

**时间分析**:

| 时间类型 | 值 | 说明 |
|---------|---|------|
| **real** | 5.301s | 实际执行时间 |
| **user** | 3.260s | 用户态CPU时间 |
| **sys** | 1.379s | 内核态CPU时间 |

⚠️ **注意**: 实际时间(real)大于理论时间(10 * 0.5s / 10 = 0.5s),原因包括:
- httpie进程启动开销
- 网络延迟
- 系统调度开销

#### 10.6.2 Shell脚本并发测试

```bash
cat > /tmp/async_test.sh <<'EOF'
#!/bin/bash

# 并发请求测试脚本
URL="http://10.0.7.80:8000/db"
CONCURRENT=10

echo "开始并发测试: $CONCURRENT 个并发请求"
time {
    for i in $(seq 1 $CONCURRENT); do
        curl -s $URL > /dev/null &
    done
    wait
}
EOF

chmod +x /tmp/async_test.sh
/tmp/async_test.sh

# 输出:
# 开始并发测试: 10 个并发请求
#
# real    0m0.512s
# user    0m0.010s
# sys     0m0.015s
```

---

### 10.7 Uvicorn配置文件部署

#### 10.7.1 创建配置文件

```bash
cd /data/fastapp

cat > uvicorn_config.py <<'EOF'
import uvicorn

# 配置参数
config = uvicorn.Config(
    "main:app",              # 应用的导入路径,格式为"模块名:应用实例名"
    host="10.0.7.80",        # 监听的主机地址
    port=8000,               # 监听的端口号
    log_level="info"         # 日志级别: debug, info, warning, error, critical
)

# 创建服务器实例
server = uvicorn.Server(config)

# 启动服务器
if __name__ == "__main__":
    server.run()
EOF
```

**配置参数详解**:

| 参数 | 说明 | 可选值 | 推荐值 |
|------|------|--------|--------|
| **app** | 应用导入路径 | "模块:实例" | "main:app" |
| **host** | 监听地址 | IP地址 | 0.0.0.0(生产) |
| **port** | 监听端口 | 1-65535 | 8000 |
| **log_level** | 日志级别 | debug/info/warning/error | info |
| **reload** | 自动重载 | True/False | False(生产) |
| **workers** | worker进程数 | 整数 | CPU核心数 |

#### 10.7.2 启动Uvicorn

```bash
python uvicorn_config.py

# 输出:
# INFO:     Started server process [12348]
# INFO:     Waiting for application startup.
# INFO:     Application startup complete.
# INFO:     Uvicorn running on http://10.0.7.80:8000 (Press CTRL+C to quit)

# ⚠️ 页面出现阻塞现象,另起终端测试
```

**另起终端测试**:

```bash
docker compose exec -it nginx-app bash

# 检查端口
netstat -tnlp | grep 8000
# 输出: tcp  0  0  10.0.7.80:8000  0.0.0.0:*  LISTEN  12348/python

# 测试访问
curl -s http://10.0.7.80:8000
# 输出: {"Hello":"World"}

curl -s http://10.0.7.80:8000/db
# 输出: {"message":"Data from database"}

# 测试完成后,返回原终端按 Ctrl+C 停止应用
```

---

### 10.8 配置systemd服务

⚠️ **注意**: Docker容器环境通常不运行systemd,以下配置仅供参考。

#### 10.8.1 创建服务文件

```bash
cat > /etc/systemd/system/uvicorn.service <<'EOF'
[Unit]
Description=FastAPI application running with Uvicorn
After=network.target

[Service]
# 应用所在的工作目录
WorkingDirectory=/data/fastapp

# 虚拟环境的路径
Environment="PATH=/data/myasgienv/bin"

# 启动命令
ExecStart=/data/myasgienv/bin/python /data/fastapp/uvicorn_config.py

# 自动重启
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

**配置说明**:

| 配置项 | 值 | 说明 |
|-------|---|------|
| **WorkingDirectory** | /data/fastapp | FastAPI项目根目录 |
| **Environment** | PATH=... | 虚拟环境的PATH |
| **ExecStart** | python命令 | 完整的启动命令 |
| **Restart** | always | 失败时自动重启 |
| **RestartSec** | 5 | 重启间隔(秒) |

#### 10.8.2 启动服务

```bash
# 重载systemd配置
systemctl daemon-reload

# 启动服务
systemctl start uvicorn.service

# 查看状态
systemctl status uvicorn.service

# 输出:
# ● uvicorn.service - FastAPI application running with Uvicorn
#    Loaded: loaded (/etc/systemd/system/uvicorn.service; disabled)
#    Active: active (running) since Thu 2025-10-12 10:38:53 CST; 3s ago
#    Main PID: 12349 (python)
#    Tasks: 1 (limit: 4558)
#    Memory: 29.0M
#    CPU: 404ms
#    CGroup: /system.slice/uvicorn.service
#            └─12349 /data/myasgienv/bin/python /data/fastapp/uvicorn_config.py

# 设置开机自启
systemctl enable uvicorn.service

# 测试访问
curl 10.0.7.80:8000
# 输出: {"Hello":"World"}
```

---

### 10.9 Nginx反向代理

#### 10.9.1 安装Nginx

```bash
# Nginx通常已安装,如未安装:
apt install -y nginx
```

#### 10.9.2 清理默认配置

```bash
rm -f /etc/nginx/sites-enabled/default
```

#### 10.9.3 创建FastAPI反向代理配置

```bash
cat > /etc/nginx/conf.d/fastapi.conf <<'EOF'
server {
    listen 8001;
    server_name 10.0.7.80;

    location / {
        # 反向代理到Uvicorn
        proxy_pass http://10.0.7.80:8000;

        # 传递原始请求头
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
```

#### 10.9.4 测试配置

```bash
# 检测配置文件语法
nginx -t

# 输出:
# nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
# nginx: configuration file /etc/nginx/nginx.conf test is successful
```

#### 10.9.5 启动Nginx

```bash
# 启动Nginx服务
systemctl start nginx.service

# 查看状态
systemctl is-active nginx.service
# 输出: active

# 检查端口
netstat -tnlp | grep nginx
# 输出:
# tcp  0  0  0.0.0.0:8001  0.0.0.0:*  LISTEN  12350/nginx
# tcp  0  0  0.0.0.0:80    0.0.0.0:*  LISTEN  12350/nginx
```

#### 10.9.6 访问测试

```bash
# 容器内测试
curl http://10.0.7.80:8001
# 输出: {"Hello":"World"}

curl http://10.0.7.80:8001/items/5?q=test
# 输出: {"item_id":5,"q":"test"}

curl http://10.0.7.80:8001/db
# 输出: {"message":"Data from database"}

# 宿主机浏览器访问
# http://宿主机IP:8001
# 例如: http://10.0.0.13:8001
```

---

## ✅ 第十一部分:测试检查清单

### 11.1 Discuz论坛检查清单

#### 11.1.1 环境检查

- [ ] nginx-app容器运行正常
- [ ] mysql-server容器运行正常
- [ ] PHP-FPM服务运行正常
- [ ] MySQL服务运行正常

#### 9.1.2 软件安装检查

- [ ] PHP模块安装完整(php-fpm, php-mysqlnd, php-gd等)
- [ ] Discuz文件解压到正确位置
- [ ] 文件权限设置正确(www-data:www-data)
- [ ] 特殊目录写权限设置正确(data/, config/, uc_server/data/)

#### 9.1.3 数据库检查

- [ ] discuz数据库创建成功
- [ ] discuzer用户创建并授权成功
- [ ] 客户端可以连接MySQL服务器

#### 9.1.4 Web界面检查

- [ ] 安装向导可以访问
- [ ] 环境检查全部通过
- [ ] 目录权限检查全部通过
- [ ] 数据库连接测试成功
- [ ] 安装完成
- [ ] 前台可以访问
- [ ] 后台可以登录
- [ ] install目录已删除或重命名

---

### 11.2 第三方模块检查清单

#### 9.2.1 Redis模块

- [ ] redis2-nginx-module克隆成功
- [ ] Nginx编译安装成功(包含Redis模块)
- [ ] Redis服务运行正常
- [ ] Redis测试数据添加成功
- [ ] Nginx配置正确(redis2_query, redis2_pass)
- [ ] curl测试返回正确(key1, key2, key3)
- [ ] 不存在的key返回$-1

#### 9.2.2 FLV模块

- [ ] Nginx编译安装成功(包含FLV模块)
- [ ] FLV视频文件下载成功
- [ ] Nginx配置正确(flv指令)
- [ ] 浏览器可以下载视频文件
- [ ] 视频可以正常播放

#### 9.2.3 一致性哈希模块

- [ ] ngx_http_consistent_hash克隆成功
- [ ] Nginx编译安装成功(包含一致性哈希模块)
- [ ] 后端Web服务配置正确
- [ ] 一致性哈希配置正确
- [ ] curl测试显示请求分发
- [ ] Python脚本测试成功
- [ ] 服务器增减时请求分发变化符合预期

---

### 11.3 二次开发版本检查清单

#### 9.3.1 Tengine

- [ ] 编译依赖安装完整
- [ ] nginx用户创建成功
- [ ] Tengine源码下载成功
- [ ] 编译配置正确
- [ ] 编译安装成功
- [ ] Tengine版本显示正确(Tengine/3.1.0)
- [ ] Nginx版本显示正确(nginx/1.24.0)
- [ ] 服务启动正常
- [ ] curl测试返回Tengine标识
- [ ] 浏览器可以访问欢迎页面

#### 9.3.2 OpenResty

- [ ] 编译依赖安装完整
- [ ] nginx用户创建成功
- [ ] OpenResty源码下载成功
- [ ] 编译配置正确
- [ ] 编译安装成功(耗时较长)
- [ ] OpenResty版本显示正确(openresty/1.25.3.1)
- [ ] LuaJIT版本显示正确
- [ ] 服务启动正常
- [ ] Lua脚本目录创建成功
- [ ] Lua配置正确(lua_package_path)
- [ ] /test路径测试成功(外部Lua文件)
- [ ] /lua路径测试成功(内联Lua代码)
- [ ] /calc路径测试成功(计算功能)
- [ ] /redis-test路径测试成功(Redis交互)
- [ ] JSON API测试成功

---

### 11.4 Django项目检查清单

#### 9.4.1 Python环境

- [ ] Python 3安装成功
- [ ] pip安装成功
- [ ] python3-venv安装成功
- [ ] 虚拟环境创建成功
- [ ] 虚拟环境激活成功

#### 9.4.2 Django环境

- [ ] pip源配置成功
- [ ] Django安装成功
- [ ] Django版本显示正确

#### 9.4.3 项目配置

- [ ] Django项目创建成功
- [ ] ALLOWED_HOSTS配置正确
- [ ] STATIC_ROOT配置正确
- [ ] 数据库迁移成功
- [ ] 超级用户创建成功
- [ ] 静态文件收集成功
- [ ] 开发服务器测试成功

#### 9.4.4 uWSGI配置

- [ ] uWSGI安装成功
- [ ] uwsgi.ini配置正确
- [ ] www-data用户创建成功
- [ ] 项目权限设置正确
- [ ] uWSGI前台测试成功
- [ ] systemd服务文件创建成功
- [ ] uWSGI服务启动成功
- [ ] socket文件创建成功

#### 9.4.5 Nginx配置

- [ ] Nginx配置文件创建成功
- [ ] 静态文件路径配置正确
- [ ] uwsgi_pass配置正确
- [ ] Nginx配置测试通过
- [ ] Nginx服务启动成功

#### 9.4.6 访问测试

- [ ] 浏览器可以访问首页
- [ ] 管理后台可以访问
- [ ] 管理后台可以登录
- [ ] 静态文件正常加载
- [ ] curl测试返回200

---

### 11.5 Flask项目检查清单

#### 11.5.1 Python环境

- [ ] Python 3安装成功
- [ ] pip安装成功
- [ ] python3-venv安装成功
- [ ] 虚拟环境创建成功(/data/myflaskenv)
- [ ] 虚拟环境激活成功

#### 11.5.2 Flask环境

- [ ] pip源配置成功
- [ ] Flask安装成功
- [ ] Flask版本显示正确

#### 11.5.3 应用开发

- [ ] Flask应用文件创建成功(app.py)
- [ ] 开发服务器测试成功
- [ ] curl测试返回"Hello, World!"

#### 11.5.4 Gunicorn配置

- [ ] Gunicorn安装成功
- [ ] gunicorn.conf.py配置正确
- [ ] 日志目录创建成功
- [ ] Gunicorn前台测试成功
- [ ] 端口监听正确(10.0.7.80:5000)
- [ ] systemd服务文件创建成功(如适用)
- [ ] Gunicorn服务启动成功(如适用)

#### 11.5.5 Nginx配置

- [ ] Nginx配置文件创建成功
- [ ] proxy_pass配置正确
- [ ] proxy_set_header配置正确
- [ ] Nginx配置测试通过
- [ ] Nginx服务启动成功

#### 11.5.6 访问测试

- [ ] 容器内curl测试成功
- [ ] 宿主机浏览器可以访问

---

### 11.6 FastAPI项目检查清单

#### 11.6.1 Python环境

- [ ] Python 3安装成功
- [ ] pip安装成功
- [ ] python3-venv安装成功
- [ ] 虚拟环境创建成功(/data/myasgienv)
- [ ] 虚拟环境激活成功

#### 11.6.2 FastAPI环境

- [ ] pip源配置成功
- [ ] FastAPI安装成功
- [ ] Uvicorn安装成功
- [ ] FastAPI版本显示正确
- [ ] Uvicorn版本显示正确

#### 11.6.3 应用开发

- [ ] FastAPI应用文件创建成功(main.py)
- [ ] 根路径路由测试成功(/)
- [ ] 带参数路由测试成功(/items/{item_id})
- [ ] curl测试返回JSON格式数据

#### 11.6.4 异步功能

- [ ] asyncio模块安装成功
- [ ] 异步路由添加成功(/db)
- [ ] 异步路由测试成功
- [ ] 响应时间符合预期(约0.5秒)

#### 11.6.5 httpie测试

- [ ] httpie安装成功
- [ ] httpie版本显示正确
- [ ] 根路径测试成功
- [ ] 带参数路径测试成功
- [ ] JSON格式化输出正常

#### 11.6.6 并发测试

- [ ] xargs并发测试成功
- [ ] Shell脚本并发测试成功
- [ ] 时间统计正确(real/user/sys)

#### 11.6.7 Uvicorn配置

- [ ] uvicorn_config.py配置正确
- [ ] Uvicorn前台测试成功
- [ ] 端口监听正确(10.0.7.80:8000)
- [ ] systemd服务文件创建成功(如适用)
- [ ] Uvicorn服务启动成功(如适用)

#### 11.6.8 Nginx配置

- [ ] Nginx配置文件创建成功
- [ ] proxy_pass配置正确
- [ ] proxy_set_header配置正确
- [ ] Nginx配置测试通过
- [ ] Nginx服务启动成功

#### 11.6.9 访问测试

- [ ] 容器内curl测试成功(所有路由)
- [ ] 宿主机浏览器可以访问
- [ ] /items路由参数传递正确
- [ ] /db异步路由正常工作

---

## ❓ 第十二部分:常见问题

### 12.1 Discuz部署问题

#### Q1: PHP模块安装后仍提示缺少扩展?

**答**: 重启PHP-FPM服务:

```bash
systemctl restart php8.3-fpm
# 或
service php-fpm restart
```

#### Q2: 数据库连接失败?

**答**: 检查以下项:

```bash
# 1. MySQL服务是否运行
docker compose ps mysql-server

# 2. 防火墙是否阻止
# 容器环境通常无需检查防火墙

# 3. 用户权限是否正确
mysql -h 10.0.7.81 -u discuzer -p123456 -e "SHOW GRANTS;"

# 4. IP地址是否在授权范围内
# 确保使用 10.0.7.% 而不是 10.0.0.%
```

#### Q3: 安装时提示目录不可写?

**答**: 设置正确的权限:

```bash
chown -R www-data:www-data /data/server/nginx/web1/
chmod -R 777 /data/server/nginx/web1/data
chmod -R 777 /data/server/nginx/web1/config
chmod -R 777 /data/server/nginx/web1/uc_server/data
chmod -R 777 /data/server/nginx/web1/uc_client/data
```

---

### 12.2 Redis模块问题

#### Q1: 编译时提示找不到redis2-nginx-module?

**答**: 检查模块路径:

```bash
ls -l /data/codes/redis2-nginx-module/

# 如果目录不存在,重新克隆
cd /data/codes
git clone https://github.com/agentzh/redis2-nginx-module.git
```

#### Q2: curl测试返回502 Bad Gateway?

**答**: 检查Redis服务:

```bash
# 1. Redis服务是否运行
docker compose ps redis-server

# 2. Redis端口是否监听
docker compose exec redis-server netstat -tnlp | grep 6379

# 3. 网络连通性
docker compose exec nginx-app ping 10.0.7.82

# 4. Nginx配置中upstream地址是否正确
cat /data/server/nginx-redis/conf.d/redis.conf | grep server
```

#### Q3: 返回的数据格式是什么?

**答**: Redis协议格式:

```
$6        ← $ 表示字符串,$后的数字表示字节长度
value1    ← 实际的值

$-1       ← 表示键不存在
```

---

### 12.3 FLV模块问题

#### Q1: 视频下载失败?

**答**: 检查文件路径和权限:

```bash
# 1. 文件是否存在
ls -l /data/server/nginx-flv/html/videos/big.flv

# 2. 文件权限是否正确
chmod 644 /data/server/nginx-flv/html/videos/big.flv

# 3. Nginx配置中alias路径是否正确
cat /data/server/nginx-flv/conf.d/flv.conf | grep alias
```

#### Q2: 视频无法播放?

**答**:

1. 确认视频文件是否完整
2. 使用专业播放器测试(VLC, PotPlayer)
3. 检查浏览器控制台错误信息

---

### 12.4 一致性哈希模块问题

#### Q1: 请求始终分发到同一台服务器?

**答**: 检查哈希键配置:

```bash
# 当前配置
upstream backend {
    consistent_hash $request_uri;
    ...
}

# $request_uri 对于相同的URI会返回相同的哈希值
# 可以改用其他变量:
# - $remote_addr (客户端IP)
# - $arg_id (URL参数)
# - $cookie_session (Cookie)
```

#### Q2: Python测试脚本运行失败?

**答**: 安装requests库:

```bash
apt install -y python3-pip
pip3 install requests
```

---

### 12.5 Tengine/OpenResty问题

#### Q1: 编译时报错缺少依赖?

**答**: 安装完整的编译依赖:

```bash
apt update
apt install -y gcc g++ make libssl-dev libpcre3-dev zlib1g-dev
```

#### Q2: 启动时提示端口被占用?

**答**: 检查端口占用:

```bash
# 查看80端口占用
netstat -tnlp | grep :80

# 停止占用端口的服务
systemctl stop nginx
# 或
/data/server/nginx/sbin/nginx -s stop
```

#### Q3: OpenResty Lua脚本报错?

**答**: 检查以下项:

```bash
# 1. lua_package_path配置是否正确
cat /data/server/openresty/nginx/conf/nginx.conf | grep lua_package_path

# 2. Lua文件是否存在
ls -l /data/server/openresty/lua/test.lua

# 3. Nginx错误日志
tail -f /data/server/openresty/nginx/logs/error.log
```

---

### 12.6 Django项目问题

#### Q1: uWSGI无法启动?

**答**: 检查以下项:

```bash
# 1. 虚拟环境路径是否正确
cat /data/myproject/uwsgi.ini | grep home
ls -l /data/myprojectenv/

# 2. 项目路径是否正确
cat /data/myproject/uwsgi.ini | grep chdir

# 3. www-data用户是否存在
id www-data

# 4. 查看详细错误日志
tail -f /data/myproject/uwsgi.log
```

#### Q2: Nginx 502 Bad Gateway?

**答**: 检查uWSGI:

```bash
# 1. uWSGI服务是否运行
systemctl status uwsgi

# 2. socket文件是否存在
ls -l /data/myproject/myproject.sock

# 3. socket文件权限是否正确
chmod 666 /data/myproject/myproject.sock

# 4. Nginx错误日志
tail -f /var/log/nginx/error.log
```

#### Q3: 静态文件404?

**答**:

```bash
# 1. 确认静态文件已收集
ls -l /data/myproject/static/

# 2. Nginx配置中alias路径是否正确
cat /etc/nginx/sites-available/django | grep static

# 3. 静态文件权限是否正确
chmod -R 755 /data/myproject/static/
```

#### Q4: 管理后台样式丢失?

**答**:

```bash
# 1. 确认settings.py中配置正确
cat /data/myproject/myproject/settings.py | grep STATIC

# 2. 重新收集静态文件
source /data/myprojectenv/bin/activate
cd /data/myproject
python manage.py collectstatic --noinput

# 3. 清除浏览器缓存
```

---

### 12.7 Flask项目问题

#### Q1: Gunicorn监听端口无法访问?

**答**: 检查bind配置:

```bash
# 1. 查看配置文件中的bind参数
cat /data/flaskapp/gunicorn.conf.py | grep bind

# 2. 如果bind限制了IP,只能通过该IP访问
# 例如: bind = '10.0.7.80:5000'
# 只能: curl 10.0.7.80:5000 ✅
# 不能: curl localhost:5000 ❌

# 3. 如果需要监听所有地址,修改为:
# bind = '0.0.0.0:5000'

# 4. 重启Gunicorn
systemctl restart gunicorn.service
```

#### Q2: Gunicorn启动报错"No module named 'app'"?

**答**: 检查工作目录和虚拟环境:

```bash
# 1. 确认app.py文件存在
ls -l /data/flaskapp/app.py

# 2. 确认虚拟环境路径正确
cat /data/flaskapp/gunicorn.conf.py | grep -A5 "^bind"

# 3. 确认systemd服务配置正确
cat /etc/systemd/system/gunicorn.service | grep WorkingDirectory

# 4. 手动测试
source /data/myflaskenv/bin/activate
cd /data/flaskapp
gunicorn -c gunicorn.conf.py app:app
```

#### Q3: Nginx返回502 Bad Gateway?

**答**: 检查Gunicorn服务状态:

```bash
# 1. 检查Gunicorn是否运行
systemctl status gunicorn.service

# 2. 检查端口监听
netstat -tnlp | grep 5000

# 3. 检查Nginx配置中的proxy_pass地址
cat /etc/nginx/conf.d/flaskapp.conf | grep proxy_pass

# 4. 测试Gunicorn直接访问
curl 10.0.7.80:5000

# 5. 查看Nginx错误日志
tail -f /var/log/nginx/error.log
```

#### Q4: Gunicorn日志无法写入?

**答**: 检查日志目录权限:

```bash
# 1. 检查日志目录是否存在
ls -ld /var/log/gunicorn/

# 2. 创建日志目录
mkdir -p /var/log/gunicorn/

# 3. 设置权限
chmod 755 /var/log/gunicorn/

# 4. 如果使用www-data用户,设置所有者
chown www-data:www-data /var/log/gunicorn/
```

---

### 12.8 FastAPI项目问题

#### Q1: FastAPI异步路由不工作?

**答**: 检查asyncio模块和async/await语法:

```bash
# 1. 确认asyncio已安装
python -c "import asyncio; print('OK')"

# 2. 检查函数定义是否使用async
cat /data/fastapp/main.py | grep "async def"

# 3. 检查是否正确使用await
cat /data/fastapp/main.py | grep "await"

# 4. 测试异步路由
curl http://10.0.7.80:8000/db
```

#### Q2: httpie和curl返回结果不同?

**答**: httpie默认发送JSON Content-Type:

```bash
# httpie特点:
# - 默认Content-Type: application/json
# - 自动解析JSON
# - 彩色输出

# curl特点:
# - 原始文本输出
# - 需要-H指定Content-Type

# 两者等价示例:
http http://10.0.7.80:8000/items/5 q==test
curl "http://10.0.7.80:8000/items/5?q=test"

# httpie POST示例:
http POST http://10.0.7.80:8000/api name=test age:=20
# 等价于:
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"test","age":20}' http://10.0.7.80:8000/api
```

#### Q3: Uvicorn无法访问自动文档?

**答**: FastAPI自动生成的文档路径:

```bash
# 1. Swagger UI文档
http://10.0.7.80:8000/docs

# 2. ReDoc文档
http://10.0.7.80:8000/redoc

# 3. OpenAPI JSON
http://10.0.7.80:8000/openapi.json

# 4. 如果无法访问,检查Uvicorn是否正常运行
curl http://10.0.7.80:8000
```

#### Q4: 并发测试时间异常?

**答**: 理解real/user/sys时间含义:

```bash
# time命令输出:
# real 0m5.301s  ← 实际执行时间(墙钟时间)
# user 0m3.260s  ← 用户态CPU时间
# sys  0m1.379s  ← 内核态CPU时间

# 分析:
# 1. real > user + sys: 说明有等待时间(I/O、网络等)
# 2. real ≈ user + sys: 说明CPU密集型任务
# 3. user + sys > real: 说明多核并行执行

# 并发测试影响因素:
# - 进程启动开销
# - 网络延迟
# - 系统调度
# - httpie初始化时间
```

#### Q5: uvicorn_config.py配置不生效?

**答**: 检查配置语法和参数:

```bash
# 1. 检查配置文件语法
python -m py_compile /data/fastapp/uvicorn_config.py

# 2. 确认Config对象参数正确
cat /data/fastapp/uvicorn_config.py | grep "uvicorn.Config"

# 3. 常见配置参数:
# - app: 应用导入路径 "main:app"
# - host: 监听地址 "0.0.0.0"
# - port: 监听端口 8000
# - log_level: 日志级别 "info"
# - reload: 自动重载 True/False

# 4. 手动测试配置
python /data/fastapp/uvicorn_config.py
```

#### Q6: Nginx代理FastAPI后返回400?

**答**: 检查Host头配置:

```bash
# FastAPI可能对Host头敏感
# Nginx配置需要正确传递Host头

cat /etc/nginx/conf.d/fastapi.conf

# 确保包含:
# proxy_set_header Host $host;
# proxy_set_header X-Real-IP $remote_addr;
# proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
# proxy_set_header X-Forwarded-Proto $scheme;

# 测试配置
nginx -t

# 重载Nginx
nginx -s reload
```

---

## 📖 参考资料

### 官方文档

- **Nginx官方文档**: https://nginx.org/en/docs/
- **Discuz官方文档**: https://www.discuz.net/
- **Tengine官方文档**: https://tengine.taobao.org/documentation.html
- **OpenResty官方文档**: https://openresty.org/cn/
- **Django官方文档**: https://docs.djangoproject.com/
- **Flask官方文档**: https://flask.palletsprojects.com/
- **Gunicorn官方文档**: https://docs.gunicorn.org/
- **FastAPI官方文档**: https://fastapi.tiangolo.com/
- **Uvicorn官方文档**: https://www.uvicorn.org/

### 模块仓库

- **redis2-nginx-module**: https://github.com/agentzh/redis2-nginx-module
- **ngx_http_consistent_hash**: https://github.com/replay/ngx_http_consistent_hash

### 下载地址

- **Nginx源码**: https://nginx.org/download/
- **Tengine**: https://tengine.taobao.org/download.html
- **OpenResty**: https://openresty.org/cn/download.html
- **Discuz**: https://gitee.com/Discuz/DiscuzX

---

## 🔚 清理环境

```bash
# 停止所有服务
docker compose down

# 删除所有数据卷(⚠️ 会删除所有数据)
docker compose down --volumes

# 完全清理(包括镜像)
docker compose down --volumes --rmi all
```

---

**完成时间**: 2025-10-12
**文档版本**: v1.0
**维护者**: docker-man 项目组
