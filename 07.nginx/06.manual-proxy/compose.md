# sudo docker compose Nginx 反向代理与高级功能实践指南

## 📚 第一部分：基础知识

### 1.1 本章内容概览

本章将深入讲解 Nginx 的反向代理和高级功能，包括：

| 功能模块 | 应用场景 | 难度 |
|---------|---------|------|
| **防盗链** | 防止资源被盗用、保护带宽 | ⭐⭐ |
| **Rewrite URL 重写** | URL 美化、路由重定向 | ⭐⭐⭐ |
| **反向代理** | 负载均衡、隐藏后端服务器 | ⭐⭐⭐ |
| **动静分离** | 性能优化、职责分离 | ⭐⭐⭐ |
| **代理缓存** | 减少后端压力、加速响应 | ⭐⭐⭐⭐ |
| **IP 透传** | 获取真实客户端 IP | ⭐⭐ |

---

### 1.2 防盗链原理

#### 1.2.1 什么是防盗链

防盗链（Anti-Leech）是一种防止其他网站直接链接您的资源（图片、视频、文件等）的技术，通过检查 HTTP Referer 头来判断请求来源是否合法。

**盗链场景示例**：
```
合法访问：
用户 → 访问 www.mysite.com/page.html → 加载 www.mysite.com/images/logo.png

盗链访问：
用户 → 访问 www.othersite.com/page.html → 盗链 www.mysite.com/images/logo.png
                                           (消耗您的带宽)
```

#### 1.2.2 Referer 检查机制

| HTTP Referer 值 | 说明 | 是否允许访问 |
|----------------|------|-------------|
| `http://www.mysite.com/*` | 来自本站 | ✅ 允许 |
| `http://www.trusted.com/*` | 来自可信站点 | ✅ 允许 |
| `空 Referer` | 直接访问（地址栏输入） | ⚙️ 可配置 |
| `http://www.badsite.com/*` | 来自其他站点 | ❌ 拒绝 |

---

### 1.3 Rewrite URL 重写原理

#### 1.3.1 Rewrite 指令语法

```nginx
rewrite regex replacement [flag];
```

| 参数 | 说明 |
|------|------|
| **regex** | 正则表达式匹配 URI |
| **replacement** | 替换后的 URI |
| **flag** | 标志位（last/break/redirect/permanent） |

#### 1.3.2 Rewrite 标志位

| 标志位 | 说明 | 状态码 | 是否停止 |
|-------|------|--------|---------|
| **last** | 停止当前 rewrite，重新匹配 location | 内部 | 继续匹配 |
| **break** | 停止所有 rewrite，继续处理请求 | 内部 | 停止匹配 |
| **redirect** | 临时重定向（可更改） | 302 | 返回客户端 |
| **permanent** | 永久重定向（浏览器缓存） | 301 | 返回客户端 |

---

### 1.4 反向代理原理

#### 1.4.1 正向代理 vs 反向代理

```
正向代理（客户端代理）：
客户端 → 代理服务器 → 目标服务器
(客户端知道最终访问的服务器地址)

反向代理（服务器端代理）：
客户端 → 代理服务器 → 后端服务器1/2/3
(客户端不知道后端服务器地址)
```

#### 1.4.2 反向代理优势

| 优势 | 说明 |
|------|------|
| **负载均衡** | 将请求分发到多台后端服务器 |
| **隐藏后端** | 客户端无法直接访问后端服务器 |
| **SSL 卸载** | 在代理层处理 HTTPS 加密解密 |
| **缓存加速** | 缓存后端响应，减少重复请求 |
| **安全防护** | 统一入口，便于防火墙、限流等 |

---

### 1.5 动静分离原理

#### 1.5.1 什么是动静分离

动静分离是将静态资源（CSS、JS、图片）和动态请求（API、数据库查询）分别由不同的服务器处理。

```
传统架构（所有请求都到应用服务器）：
客户端 → Web 服务器 → 应用服务器（PHP/Java）
                     ↓
                  数据库

动静分离架构：
客户端 → Nginx 代理
        ├─ 静态资源 → 静态文件服务器（Nginx）
        └─ 动态请求 → 应用服务器（PHP/Java）→ 数据库
```

#### 1.5.2 动静分离优势

| 优势 | 说明 |
|------|------|
| **性能提升** | 静态资源由 Nginx 直接返回，速度快 |
| **减轻负载** | 应用服务器只处理动态请求 |
| **易于扩展** | 静态服务器和应用服务器独立扩容 |
| **CDN 友好** | 静态资源可以轻松接入 CDN |

---

### 1.6 代理缓存原理

#### 1.6.1 缓存架构

```
客户端 → Nginx 代理（缓存层）
        ├─ 缓存命中 → 直接返回缓存内容
        └─ 缓存未命中 → 后端服务器 → 缓存结果 → 返回客户端
```

#### 1.6.2 缓存关键概念

| 概念 | 说明 |
|------|------|
| **缓存键（Cache Key）** | 用于标识缓存内容的唯一键（通常是 URL） |
| **缓存过期时间** | 缓存有效期（X-Accel-Expires 或 Cache-Control） |
| **缓存命中率** | 从缓存返回的请求比例 |
| **缓存穿透** | 请求不在缓存中，直接访问后端 |

---

## 🌐 第二部分：网络架构与环境说明

### 2.1 网络拓扑

```
Docker Bridge 网络：nginx-net (10.0.7.0/24)
├── 10.0.7.1   - 网关（Docker 网桥）
├── 10.0.7.60  - Nginx 代理服务器（nginx-proxy）
│   ├── 端口：8060:80, 8061:443
│   ├── 功能：反向代理、缓存、负载均衡、防盗链
│   └── 缓存目录：/tmp/nginx/cache
├── 10.0.7.61  - 后端 Web 服务器 1（nginx-backend-1）
│   ├── 端口：8062:80
│   └── 功能：动态内容处理
├── 10.0.7.62  - 后端 Web 服务器 2（nginx-backend-2）
│   ├── 端口：8063:80
│   └── 功能：动态内容处理（负载均衡）
└── 10.0.7.63  - 静态资源服务器（nginx-static）
    ├── 端口：8064:80
    └── 功能：静态资源托管（图片、CSS、JS）
```

### 2.2 sudo docker compose 配置说明

```yaml
version: '3.8'

services:
  nginx-proxy:
    # 代理服务器（Ubuntu 编译版）
    container_name: nginx-proxy
    hostname: nginx-proxy
    networks:
      nginx-net:
        ipv4_address: 10.0.7.60
    ports:
      - "8060:80"      # HTTP 端口
      - "8061:443"     # HTTPS 端口
    build:
      context: ..
      dockerfile: Dockerfile.ubuntu-compile

  nginx-backend-1:
    # 后端服务器 1（Rocky 编译版）
    container_name: nginx-backend-1
    hostname: nginx-backend-1
    networks:
      nginx-net:
        ipv4_address: 10.0.7.61
    ports:
      - "8062:80"

  nginx-backend-2:
    # 后端服务器 2（Ubuntu 编译版）
    container_name: nginx-backend-2
    hostname: nginx-backend-2
    networks:
      nginx-net:
        ipv4_address: 10.0.7.62
    ports:
      - "8063:80"

  nginx-static:
    # 静态资源服务器（Rocky 编译版）
    container_name: nginx-static
    hostname: nginx-static
    networks:
      nginx-net:
        ipv4_address: 10.0.7.63
    ports:
      - "8064:80"

networks:
  nginx-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.7.0/24
          gateway: 10.0.7.1
```

---

## 🚀 第三部分：环境启动与初始化

### 3.1 启动环境

```bash
# 1. 进入项目目录
cd /home/www/docker-man/07.nginx/06.manual-proxy

# 2. 启动所有服务
sudo docker compose up -d

# 3. 检查服务状态
sudo docker compose ps

# 预期输出：
# NAME                IMAGE              STATUS    PORTS
# nginx-proxy         ...                Up        0.0.0.0:8060->80/tcp, 0.0.0.0:8061->443/tcp
# nginx-backend-1     ...                Up        0.0.0.0:8062->80/tcp
# nginx-backend-2     ...                Up        0.0.0.0:8063->80/tcp
# nginx-static        ...                Up        0.0.0.0:8064->80/tcp

# 4. 查看网络配置
docker network inspect 06manual-proxy_nginx-net | grep -A 3 "IPv4Address"
```

### 3.2 初始化所有服务器

#### 3.2.1 初始化代理服务器

```bash
# 进入代理服务器容器
sudo docker compose exec -it nginx-proxy bash

# 创建必要目录
mkdir -p /data/server/nginx/conf/conf.d
mkdir -p /data/server/nginx/logs
mkdir -p /data/server/nginx/html
mkdir -p /tmp/nginx/cache

# 启动 Nginx（如未启动）
/data/server/nginx/sbin/nginx

# 检查 Nginx 状态
ps aux | grep nginx
```

#### 3.2.2 初始化后端服务器 1

```bash
# 进入后端服务器 1 容器
sudo docker compose exec -it nginx-backend-1 bash

# 创建测试内容
mkdir -p /data/wwwroot/backend-1
cat > /data/wwwroot/backend-1/index.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>Backend Server 1</title>
</head>
<body>
    <h1>Backend Server 1</h1>
    <p>Server: nginx-backend-1 (10.0.7.61)</p>
    <p>Time: <script>document.write(new Date().toLocaleString());</script></p>
</body>
</html>
EOF

# 配置 Nginx
cat > /data/server/nginx/conf/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /data/wwwroot/backend-1;

    location / {
        index index.html;
    }

    location /api/ {
        default_type application/json;
        return 200 '{
            "server": "backend-1",
            "ip": "10.0.7.61",
            "time": "$time_iso8601",
            "request_uri": "$request_uri"
        }\n';
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx

# 测试
curl http://127.0.0.1/api/test
```

#### 3.2.3 初始化后端服务器 2

```bash
# 进入后端服务器 2 容器
sudo docker compose exec -it nginx-backend-2 bash

# 创建测试内容
mkdir -p /data/wwwroot/backend-2
cat > /data/wwwroot/backend-2/index.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>Backend Server 2</title>
</head>
<body>
    <h1>Backend Server 2</h1>
    <p>Server: nginx-backend-2 (10.0.7.62)</p>
    <p>Time: <script>document.write(new Date().toLocaleString());</script></p>
</body>
</html>
EOF

# 配置 Nginx
cat > /data/server/nginx/conf/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /data/wwwroot/backend-2;

    location / {
        index index.html;
    }

    location /api/ {
        default_type application/json;
        return 200 '{
            "server": "backend-2",
            "ip": "10.0.7.62",
            "time": "$time_iso8601",
            "request_uri": "$request_uri"
        }\n';
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx

# 测试
curl http://127.0.0.1/api/test
```

#### 3.2.4 初始化静态资源服务器

```bash
# 进入静态资源服务器容器
sudo docker compose exec -it nginx-static bash

# 创建静态资源目录
mkdir -p /data/wwwroot/nginx-static/static/{images,css,js}

# 创建测试图片（模拟）
echo "Test Image Data" > /data/wwwroot/nginx-static/static/images/logo.png
echo "Test Image Data" > /data/wwwroot/nginx-static/static/images/banner.jpg

# 创建测试 CSS
cat > /data/wwwroot/nginx-static/static/css/style.css <<'EOF'
/* Test CSS File */
body {
    font-family: Arial, sans-serif;
    background-color: #f0f0f0;
}
h1 {
    color: #333;
}
EOF

# 创建测试 JS
cat > /data/wwwroot/nginx-static/static/js/app.js <<'EOF'
// Test JavaScript File
console.log('Static JS loaded from nginx-static');
EOF

# 配置 Nginx
cat > /data/server/nginx/conf/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /data/wwwroot/nginx-static;

    location /static/ {
        alias /data/wwwroot/nginx-static/static/;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx

# 测试
curl http://127.0.0.1/static/images/logo.png
curl http://127.0.0.1/static/css/style.css
```

### 3.3 验证各服务器连通性

```bash
# 在代理服务器中测试各后端服务器
sudo docker compose exec -it nginx-proxy bash

# 测试后端服务器 1
curl http://10.0.7.61/api/test

# 预期输出：
# {
#     "server": "backend-1",
#     "ip": "10.0.7.61",
#     ...
# }

# 测试后端服务器 2
curl http://10.0.7.62/api/test

# 测试静态资源服务器
curl http://10.0.7.63/static/css/style.css

# 预期输出：CSS 文件内容
```

---

## 🛡️ 第四部分：防盗链配置与测试

### 4.1 valid_referers 指令详解

#### 4.1.1 语法

```nginx
valid_referers none | blocked | server_names | string ...;
```

| 参数 | 说明 |
|------|------|
| **none** | 允许空 Referer（直接访问） |
| **blocked** | 允许被防火墙或代理移除的 Referer |
| **server_names** | 允许与 server_name 匹配的 Referer |
| **字符串** | 允许指定的域名（支持通配符 `*.example.com`） |

#### 4.1.2 原理

```nginx
valid_referers none blocked server_names *.example.com;
if ($invalid_referer) {
    return 403;  # Referer 不合法，返回 403
}
```

变量 `$invalid_referer`：
- `0`：Referer 合法
- `1`：Referer 不合法

---

### 4.2 配置防盗链（静态资源服务器）

```bash
# 在静态资源服务器中配置防盗链
sudo docker compose exec -it nginx-static bash

# 删除原有的 default.conf（避免冲突）
rm -f /data/server/nginx/conf/conf.d/default.conf

# 配置防盗链
cat > /data/server/nginx/conf/conf.d/anti-leech.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /data/wwwroot/nginx-static;

    # 防盗链保护（仅对图片）
    location ~* \.(gif|jpg|jpeg|png|bmp|webp)$ {
        # 定义合法的 Referer
        valid_referers none blocked server_names
                       *.example.com
                       10.0.7.60;  # 允许代理服务器

        # 不合法的 Referer 返回 403
        if ($invalid_referer) {
            return 403 "Access Denied: Invalid Referer\n";
        }

        root /data/wwwroot/nginx-static;
        expires 30d;
    }

    # 其他静态资源（不做防盗链）
    location ~* \.(css|js)$ {
        root /data/wwwroot/nginx-static;
        expires 7d;
    }

    # 默认 location
    location / {
        return 200 "Static Server\n";
    }
}
EOF

# 重载 Nginx
nginx -s reload
```

### 4.3 测试防盗链

#### 4.3.1 测试空 Referer（直接访问）

```bash
# 在静态资源服务器中测试
curl http://127.0.0.1/static/images/logo.png

# 预期输出：Test Image Data（允许访问）
```

#### 4.3.2 测试合法 Referer

```bash
# 带合法 Referer 访问
curl -H "Referer: http://www.example.com/page.html" \
     http://127.0.0.1/static/images/logo.png

# 预期输出：Test Image Data（允许访问）
```

#### 4.3.3 测试非法 Referer（盗链）

```bash
# 带非法 Referer 访问
curl -H "Referer: http://badsite.com/steal.html" \
     http://127.0.0.1/static/images/logo.png

# 预期输出：
# Access Denied: Invalid Referer（403 错误）

# 查看状态码
curl -I -H "Referer: http://badsite.com/" \
     http://127.0.0.1/static/images/logo.png

# 输出：
# HTTP/1.1 403 Forbidden
```

#### 4.3.4 测试通配符域名

```bash
# 添加 *.mysite.com 到 valid_referers
# 修改配置：
valid_referers none blocked *.mysite.com;

# 重载 Nginx
nginx -s reload

# 测试 www.mysite.com
curl -H "Referer: http://www.mysite.com/" \
     http://127.0.0.1/static/images/logo.png
# 允许访问

# 测试 blog.mysite.com
curl -H "Referer: http://blog.mysite.com/" \
     http://127.0.0.1/static/images/logo.png
# 允许访问

# 测试 other.com
curl -H "Referer: http://other.com/" \
     http://127.0.0.1/static/images/logo.png
# 拒绝访问（403）
```

### 4.4 返回默认图片（替代 403）

```bash
# 删除之前的防盗链配置（避免冲突）
rm -f /data/server/nginx/conf/conf.d/anti-leech.conf

# 修改防盗链配置，返回默认图片而非 403
cat > /data/server/nginx/conf/conf.d/anti-leech-default.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /data/wwwroot/nginx-static;

    location ~* \.(gif|jpg|jpeg|png|bmp|webp)$ {
        valid_referers none blocked server_names *.example.com;

        if ($invalid_referer) {
            # 返回默认图片（替代原图）
            rewrite ^.*$ /static/images/hotlink-denied.png break;
        }

        root /data/wwwroot/nginx-static;
        expires 30d;
    }
}
EOF

# 创建默认图片
echo "Hotlink Denied" > /data/wwwroot/nginx-static/static/images/hotlink-denied.png

# 重载 Nginx
nginx -s reload

# 测试盗链
curl -H "Referer: http://badsite.com/" \
     http://127.0.0.1/static/images/logo.png

# 预期输出：Hotlink Denied（默认图片内容）
```

---

## 🔄 第五部分：Rewrite URL 重写实践

### 5.1 Rewrite 基础示例

#### 5.1.1 配置 DNS 解析（支持域名测试）

```bash
# 配置 test.com 域名解析（*.test.com 会解析到 nginx-proxy 10.0.7.60）
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns

# 主服务器添加 test.com 域名（包括 rewrite.test.com、last.test.com 等所有子域名）
sudo docker compose exec -it dns-master /usr/local/bin/setup-dns-master.sh test.com 10.0.7.60 10.0.0.13 10.0.0.15

# 从服务器同步 test.com 域名
sudo docker compose exec -it dns-slave /usr/local/bin/setup-dns-slave.sh test.com 10.0.0.13

# 验证 DNS 解析
sudo docker compose exec -it client dig @10.0.0.13 rewrite.test.com
sudo docker compose exec -it client dig @10.0.0.13 last.test.com
sudo docker compose exec -it client dig @10.0.0.13 www.test.com
sudo iptables -F -t raw; sudo iptables -F DOCKER ; sudo iptables -F  DOCKER-ISOLATION-STAGE-2; sudo iptables -P FORWARD ACCEPT
# 预期输出：所有 *.test.com 域名都解析到 10.0.7.60
```

#### 5.1.2 简单重写（内部）

**PCRE 正则表达式元字符**

Rewrite 模块使用 PCRE（Perl Compatible Regular Expressions）风格的正则表达式，以下是常用元字符：

| 元字符 | 说明 | 示例 |
|--------|------|------|
| `.` | 匹配除换行符外的任意字符 | `a.c` 匹配 abc, a1c |
| `\w` | 匹配字母、数字、下划线 | `\w+` 匹配 user123 |
| `\W` | 匹配非字母数字下划线 | `\W` 匹配空格、标点 |
| `\s` | 匹配任意空白字符（空格、制表符） | `\s+` 匹配多个空格 |
| `\d` | 匹配任意数字，相当于 `[0-9]` | `\d{3}` 匹配 123 |
| `\D` | 匹配非数字字符 | `\D+` 匹配 abc |
| `\b` | 匹配单词边界 | `\bword\b` 匹配独立单词 word |
| `[abc]` | 匹配括号内的任意一个字符 | `[abc]` 匹配 a 或 b 或 c |
| `[^abc]` | 匹配除括号内字符之外的任意字符 | `[^abc]` 匹配除 a、b、c 外的字符 |
| `[a-z]` | 匹配 a 到 z 的任意字符 | `[a-z]+` 匹配小写字母 |
| `[0-9]` | 匹配 0 到 9 的任意数字 | `[0-9]{2}` 匹配两位数字 |
| `^` | 匹配字符串开始位置 | `^/api` 匹配以 /api 开头 |
| `$` | 匹配字符串结束位置 | `\.html$` 匹配以 .html 结尾 |
| `*` | 匹配前面的字符零次或多次 | `a*` 匹配空字符串、a、aa |
| `+` | 匹配前面的字符一次或多次 | `a+` 匹配 a、aa、aaa |
| `?` | 匹配前面的字符零次或一次 | `colou?r` 匹配 color 或 colour |
| `{n}` | 匹配前面的字符恰好 n 次 | `\d{3}` 匹配 123 |
| `{n,}` | 匹配前面的字符至少 n 次 | `\d{3,}` 匹配 123、1234 |
| `{n,m}` | 匹配前面的字符 n 到 m 次 | `\d{2,4}` 匹配 12、123、1234 |
| `\|` | 或，指定多个备选项 | `jpg\|png` 匹配 jpg 或 png |
| `()` | 分组，捕获匹配的文本 | `(jpg\|png)$` 捕获文件扩展名 |
| `\1` | 反向引用第 1 个捕获组 | `(a)\1` 匹配 aa |

**示例说明**：
```nginx
# 匹配数字 ID
location ~* ^/user/(\d+)$ {
    # \d+ 匹配一个或多个数字
    # () 捕获数字，可以通过 $1 引用
}

# 匹配静态文件
location ~* \.(jpg|jpeg|png|gif)$ {
    # \. 转义点号
    # (jpg|jpeg|png|gif) 匹配多种扩展名
    # $ 确保扩展名在末尾
}

# 匹配路径并捕获
rewrite ^/old/(.*)$ /new/$1 last;
# ^/old/ 匹配以 /old/ 开头
# (.*) 捕获 /old/ 后面的所有内容
# $1 引用捕获的内容
```

---
注意添加echo模块
[echo模块添加](../03.manual-upgrade/compose.md)

```bash
# 返回 Nginx 项目目录
cd /home/www/docker-man/07.nginx/06.manual-proxy

# 在代理服务器中配置
sudo docker compose exec -it nginx-proxy bash



cat > /data/server/nginx/conf/conf.d/rewrite-basic.conf <<'EOF'
server {
    listen 80;
    server_name rewrite.test.com;

    # 示例 1：演示 rewrite + break（break 后 rewrite 模块指令不执行，但其他模块仍执行）
    location /old/ {
        root /data/wwwroot/nginx-proxy;  # 设置根目录（标准路径）
        set $var1 "before-rewrite";
        # 使用 add_header 演示（headers 模块不受 break 影响）
        add_header X-Before "$var1" always;
        add_header X-Original-URI "$request_uri" always;
        rewrite ^/old/(.*)$ /new/$1 break;  # break 后停止 rewrite 模块指令
        # break 之后，ngx_http_rewrite_module 模块的指令不再执行
        set $var2 "after-break";        # 不会执行（rewrite 模块）
        # 但 headers 模块的指令仍会执行（不属于 rewrite 模块）
        add_header X-After "$var2" always;       # 会执行，但 $var2 为空（set 未执行）
        add_header X-Rewritten-URI "$uri" always;  # 会执行，显示重写后的 URI
        return 200 "This will NOT execute\n";  # 不会执行（rewrite 模块）
        # break 后，Nginx 继续处理请求，查找 root + $uri 对应的文件
        # 即查找 /data/wwwroot/nginx-proxy/new/path/file.txt
    }

    # 示例 2：对比示例 - 不使用 break
    location /nobreak/ {
        set $var1 "magedu";
        set $var2 "1234";
        echo "$var1 $var2";
        return 200 "hello nobreak\n";  # 这行会执行，返回 200
    }

    # 示例 3：将 /user/123 重写为 /user-detail?id=123（真实重写）
    location ~* ^/user/(\d+)$ {
        rewrite ^/user/(\d+)$ /user-detail?id=$1 last;
    }

    location /user-detail {
        return 200 "User ID: $arg_id\n";
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 创建测试文件（用于演示 break 后的文件查找）
mkdir -p /data/wwwroot/nginx-proxy/new/path
echo "This is the rewritten file content" > /data/wwwroot/nginx-proxy/new/path/file.txt

# 测试示例 1（演示 break）- 查看完整响应
curl -i -H "Host: rewrite.test.com" http://127.0.0.1/old/path/file.txt
# 输出：
# HTTP/1.1 200 OK
# Server: nginx/1.24.0
# Content-Type: text/plain
# X-Before: before-rewrite
# X-Original-URI: /old/path/file.txt
# X-After:
# X-Rewritten-URI: /new/path/file.txt
#
# This is the rewritten file content
#
# 说明：
# 1. break 之前的 set 和 add_header 执行了
#    - X-Before: before-rewrite（$var1 有值）
#    - X-Original-URI: /old/path/file.txt（$request_uri 不变）
# 2. rewrite 执行，URI 被重写为 /new/path/file.txt
# 3. break 停止 rewrite 模块指令：set $var2 不执行（所以 $var2 为空）
# 4. 但 headers 模块不受影响，add_header 仍然执行：
#    - X-After: （空值，因为 set $var2 未执行）
#    - X-Rewritten-URI: /new/path/file.txt（$uri 已改变）
# 5. return 200 不执行（rewrite 模块）
# 6. break 后，Nginx 继续处理请求：
#    - 查找文件：root + $uri = /data/wwwroot/nginx-proxy/new/path/file.txt
#    - 文件存在，返回文件内容："This is the rewritten file content"
# 7. 最终响应包含：响应头（add_header 添加）+ 文件内容

# 只查看响应体
curl -H "Host: rewrite.test.com" http://127.0.0.1/old/path/file.txt
# 输出：
# This is the rewritten file content

# 测试不存在的文件（演示 404）
curl -i -H "Host: rewrite.test.com" http://127.0.0.1/old/path/notfound.txt
# 输出：
# HTTP/1.1 404 Not Found
# Server: nginx/1.24.0
# Content-Type: text/html
# X-Before: before-rewrite
# X-Original-URI: /old/path/notfound.txt
# X-After:
# X-Rewritten-URI: /new/path/notfound.txt
#
# <html>
# <head><title>404 Not Found</title></head>
# <body>
# <center><h1>404 Not Found</h1></center>
# </body>
# </html>
#
# 说明：
# - add_header 仍然执行（响应头中包含 X-Before, X-After 等）
# - 文件 /data/wwwroot/nginx-proxy/new/path/notfound.txt 不存在
# - Nginx 返回 404 错误页面

# 测试示例 2（不使用 break 的对比）
curl -H "Host: rewrite.test.com" http://127.0.0.1/nobreak/
# 输出：
# hello nobreak
# 说明：
# 1. set 指令执行（rewrite 阶段）
# 2. echo 指令不执行（因为 return 在 rewrite 阶段就终止了请求）
# 3. return 200 执行，返回 "hello nobreak"（没有 break 阻止，return 正常执行）

# 查看状态码
curl -I -H "Host: rewrite.test.com" http://127.0.0.1/nobreak/
# 输出：
# HTTP/1.1 200 OK
# Content-Type: application/octet-stream
# Content-Length: 14

# 测试示例 3（真实重写）
curl -H "Host: rewrite.test.com" http://127.0.0.1/user/123
# 输出：User ID: 123
```

**⚠️ 重要知识点：break 只影响 rewrite 模块**

`break` 指令只会停止 **ngx_http_rewrite_module** 模块的指令执行，不影响其他模块！

| 模块 | 指令 | break 后是否执行 | 说明 |
|------|------|----------------|------|
| **rewrite 模块** | `rewrite`, `return`, `set`, `if` | ❌ 不执行 | break 后停止处理 |
| **headers 模块** | `add_header`, `expires` | ✅ 仍执行 | 不属于 rewrite 模块 |
| **access 模块** | `allow`, `deny` | ✅ 仍执行 | 不属于 rewrite 模块 |
| **echo 模块** | `echo`, `echo_sleep` | ✅ 仍执行 | 第三方模块，不受影响 |
| **content 阶段** | 文件查找、返回内容 | ✅ 继续处理 | break 后继续处理请求 |

**变量区别**：

| 变量 | 说明 | rewrite 后的值 |
|------|------|---------------|
| `$request_uri` | 原始请求 URI | `/old/path/file.txt`（不变） |
| `$uri` | 当前处理的 URI | `/new/path/file.txt`（改变） |
| `$document_uri` | 同 `$uri` | `/new/path/file.txt`（改变） |

---

### 5.3 last vs break 区别

#### 5.3.1 last 标志（重新匹配 location）

```bash
cat > /data/server/nginx/conf/conf.d/rewrite-last.conf <<'EOF'
server {
    listen 80;
    server_name last.test.com;

    location /test-last/ {
        rewrite ^/test-last/(.*)$ /final/$1 last;  # last 标志
        return 200 "This will NOT execute\n";
    }

    location /final/ {
        return 200 "Final location: $uri\n";
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试
curl -H "Host: last.test.com" http://127.0.0.1/test-last/abc

# 输出：Final location: /final/abc
# 说明：rewrite 后重新匹配 location，命中 /final/
```

#### 5.3.2 break 标志（停止重写）

```bash
cat > /data/server/nginx/conf/conf.d/rewrite-break.conf <<'EOF'
server {
    listen 80;
    server_name break.test.com;
    root /data/wwwroot/nginx-proxy;  # 标准路径

    location /test-break/ {
        rewrite ^/test-break/(.*)$ /final/$1 break;  # break 标志
        return 200 "This will NOT execute\n";
    }

    location /final/ {
        return 200 "Final location (will NOT execute)\n";
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 创建测试文件
mkdir -p /data/wwwroot/nginx-proxy/final
echo "Final file content" > /data/wwwroot/nginx-proxy/final/abc

# 测试
curl -H "Host: break.test.com" http://127.0.0.1/test-break/abc

# 输出：Final file content
# 说明：rewrite 后不再匹配 location，直接查找文件 /data/wwwroot/nginx-proxy/final/abc
```

### 5.4 redirect vs permanent 区别

#### 5.4.1 临时重定向（302 redirect）

```bash
cat > /data/server/nginx/conf/conf.d/rewrite-redirect.conf <<'EOF'
server {
    listen 80;
    server_name redirect.test.com;

    location /temp-redirect {
        rewrite ^.*$ http://www.example.com redirect;  # 302 临时重定向
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试
curl -I -H "Host: redirect.test.com" http://127.0.0.1/temp-redirect

# 输出：
# HTTP/1.1 302 Moved Temporarily
# Location: http://www.example.com
```

#### 5.4.2 永久重定向（301 permanent）

```bash
cat > /data/server/nginx/conf/conf.d/rewrite-permanent.conf <<'EOF'
server {
    listen 80;
    server_name permanent.test.com;

    location /old-page {
        rewrite ^.*$ http://www.example.com/new-page permanent;  # 301 永久重定向
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试
curl -I -H "Host: permanent.test.com" http://127.0.0.1/old-page

# 输出：
# HTTP/1.1 301 Moved Permanently
# Location: http://www.example.com/new-page
```

### 5.5 if 条件判断

#### 5.5.1 if 语法

```nginx
if (condition) {
    # 执行语句
}
```

**支持的条件**：

| 条件 | 说明 | 示例 |
|------|------|------|
| `=` | 字符串相等 | `if ($request_method = POST)` |
| `!=` | 字符串不等 | `if ($request_method != GET)` |
| `~` | 正则匹配（区分大小写） | `if ($uri ~ "\.php$")` |
| `~*` | 正则匹配（不区分大小写） | `if ($http_user_agent ~* "mobile")` |
| `!~` | 正则不匹配 | `if ($uri !~ "\.jpg$")` |
| `-f` | 文件存在 | `if (-f $request_filename)` |
| `!-f` | 文件不存在 | `if (!-f $request_filename)` |
| `-d` | 目录存在 | `if (-d $request_filename)` |
| `!-d` | 目录不存在 | `if (!-d $request_filename)` |
| `-e` | 文件或目录存在 | `if (-e $request_filename)` |
| `!-e` | 文件或目录不存在 | `if (!-e $request_filename)` |
| `-x` | 文件可执行 | `if (-x $request_filename)` |
| `!-x` | 文件不可执行 | `if (!-x $request_filename)` |

#### 5.5.2 if 实践示例

```bash
cat > /data/server/nginx/conf/conf.d/rewrite-if.conf <<'EOF'
server {
    listen 80;
    server_name if.test.com;

    # 示例 1：禁止 POST 请求
    location /no-post {
        if ($request_method = POST) {
            return 405 "POST method not allowed\n";
        }
        return 200 "GET request success\n";
    }

    # 示例 2：移动设备重定向
    location /mobile-check {
        if ($http_user_agent ~* "(mobile|android|iphone)") {
            rewrite ^.*$ /mobile-page redirect;
        }
        return 200 "Desktop Page\n";
    }

    location /mobile-page {
        return 200 "Mobile Page\n";
    }

    # 示例 3：文件不存在则重定向
    location /check-file {
        root /data/wwwroot/nginx-proxy;  # 标准路径
        if (!-f $request_filename) {
            rewrite ^.*$ /404.html break;
        }
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试禁止 POST
curl -X POST -H "Host: if.test.com" http://127.0.0.1/no-post
# 输出：POST method not allowed（405）

curl -H "Host: if.test.com" http://127.0.0.1/no-post
# 输出：GET request success

# 测试移动设备检测
root@client data]# curl -L -I -A  "Mozilla/5.0 (iPhone)" -H "Host: if.test.com" http://if.test.com/mobile-check
# HTTP/1.1 302 Moved Temporarily
# Server: nginx/1.24.0
# Date: Thu, 16 Oct 2025 06:57:19 GMT
# Content-Type: text/html
# Content-Length: 145
# Location: http://if.test.com/mobile-page
# Connection: keep-alive

# HTTP/1.1 200 OK
# Server: nginx/1.24.0
# Date: Thu, 16 Oct 2025 06:57:19 GMT
# Content-Type: application/octet-stream
# Content-Length: 12
# Connection: keep-alive

[root@client data]# curl -I   http://if.test.com/mobile-check
# HTTP/1.1 200 OK
# Server: nginx/1.24.0
# Date: Thu, 16 Oct 2025 06:57:22 GMT
# Content-Type: application/octet-stream
# Content-Length: 13
# Connection: keep-alive

```

### 5.6 set 自定义变量

```bash
cat > /data/server/nginx/conf/conf.d/rewrite-set.conf <<'EOF'
server {
    listen 80;
    server_name set.test.com;

    # 定义变量
    set $backend_flag 0;

    # 根据条件设置变量
    location /set-test {
        if ($request_method = POST) {
            set $backend_flag "post_method";
        }

        if ($http_user_agent ~* "mobile") {
            set $backend_flag "${backend_flag}_mobile";
        }

        return 200 "Backend Flag: $backend_flag\n";
    }

    # 使用变量进行重写
    location /dynamic-backend {
        set $backend_server "http://10.0.7.61";

        if ($arg_version = "v2") {
            set $backend_server "http://10.0.7.62";
        }

        return 200 "Backend: $backend_server\n";
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试
curl -X POST -A "Mobile Safari"  http://set.test.com/set-test
# 输出：Backend Flag: post_method_mobile

curl -H "Host: set.test.com" http://127.0.0.1/dynamic-backend?version=v2
# 输出：Backend: http://10.0.7.62

[root@client data]# curl   -A "Mobile Safari"  http://set.test.com//dynamic-backend?version=v2
# Backend: http://10.0.7.62
[root@client data]# curl   -A "Mobile Safari"  http://set.test.com//dynamic-backend?version=v1
# Backend: http://10.0.7.61

```

#### 5.6.1 实战：使用 set 配合 limit_rate 实现限速下载

**应用场景**：根据文件类型或路径，对特定资源进行下载限速。

```bash
# 准备测试文件
mkdir -p /data/wwwroot/nginx-proxy/downloads
mkdir -p /data/wwwroot/nginx-proxy/files
dd if=/dev/zero of=/data/wwwroot/nginx-proxy/downloads/normal.zip bs=10M count=1
dd if=/dev/zero of=/data/wwwroot/nginx-proxy/downloads/slow.zip bs=10M count=1
dd if=/dev/zero of=/data/wwwroot/nginx-proxy/downloads/slow2.zip bs=10M count=1
dd if=/dev/zero of=/data/wwwroot/nginx-proxy/files/test.zip bs=10M count=1

# 配置限速下载
cat > /data/server/nginx/conf/conf.d/rewrite-limit.conf <<'EOF'
server {
    listen 80;
    server_name limit.test.com;
    root /data/wwwroot/nginx-proxy;  # 标准路径

    # 示例 1：对特定文件限速（使用 ^~ 完整前缀匹配，优先级高于正则）
    location ^~ /downloads/slow.zip {
        add_header X-Match-Location "Example-1-Specific-File" always;
        limit_rate 100k;  # 限速 100KB/s
    }

    # 示例 2：根据文件扩展名限速（正则匹配）
    # 注意：由于示例1使用了 ^~，/downloads/slow.zip 不会被这里匹配
    location ~* \.(zip|tar|gz)$ {
        set $slow 0;
        add_header X-Match-Location "Example-2-Regex" always;

        # 如果是 slow2 开头的文件，则限速
        if ($uri ~ "^/downloads/slow2") {
            set $slow 1;
        }

        add_header X-Regex-Slow "$slow" always;
        if ($slow) {
            limit_rate 10k;  # 限速 10KB/s
        }
    }

    # 示例 3：根据请求参数动态限速（使用 ^~ 避免被正则覆盖）
    location ^~ /files/ {
        set $download_speed 0;
        add_header X-Match-Location "Example-3-Params" always;

        # 如果 URL 参数包含 speed=slow，则限速
        if ($arg_speed = "slow") {
            set $download_speed 50k;  # 50KB/s
        }

        # 如果 URL 参数包含 speed=fast，则不限速
        if ($arg_speed = "fast") {
            set $download_speed 0;  # 不限速
        }

        # 默认限速 200KB/s
        if ($download_speed = 0) {
            set $download_speed 200k;
        }

        add_header X-Download-Speed "$download_speed" always;
        limit_rate $download_speed;
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试示例 1：特定文件限速（走 ^~ 完整前缀匹配，100KB/s）
curl -I http://limit.test.com/downloads/slow.zip
# 查看响应头：
# X-Match-Location: Example-1-Specific-File
# 说明匹配了示例1，limit_rate 100KB/s

time curl -o /tmp/slow.zip http://limit.test.com/downloads/slow.zip
# 预期：10MB 文件，100KB/s 速度，大约需要 100 秒

# 测试示例 2：正则匹配不限速（走正则，不限速）
curl -I http://limit.test.com/downloads/normal.zip
# 查看响应头：
# X-Match-Location: Example-2-Regex
# X-Regex-Slow: 0
# 说明匹配了示例2，不限速

time curl -o /tmp/normal.zip http://limit.test.com/downloads/normal.zip
# 预期：很快完成（不限速）

# 测试示例 2：正则匹配限速（slow2.zip 会被限速 10KB/s）
curl -I http://limit.test.com/downloads/slow2.zip
# 查看响应头：
# X-Match-Location: Example-2-Regex
# X-Regex-Slow: 1
# 说明匹配了示例2，且 if 条件触发，limit_rate 10KB/s

time curl -o /tmp/slow2.zip http://limit.test.com/downloads/slow2.zip
# 预期：10MB 文件，10KB/s 速度，大约需要 1000 秒（约 16 分钟）

# 测试示例 3：参数动态限速（走 ^~ 完整前缀匹配）
curl -I "http://limit.test.com/files/test.zip?speed=slow"
# 查看响应头：
# X-Match-Location: Example-3-Params
# X-Download-Speed: 50k

time curl -o /tmp/test-slow.zip "http://limit.test.com/files/test.zip?speed=slow"
# 预期：10MB 文件，50KB/s 速度，大约需要 200 秒

curl -I "http://limit.test.com/files/test.zip?speed=fast"
# 查看响应头：
# X-Match-Location: Example-3-Params
# X-Download-Speed: 0

time curl -o /tmp/test-fast.zip "http://limit.test.com/files/test.zip?speed=fast"
# 预期：很快完成（不限速）

curl -I "http://limit.test.com/files/test.zip"
# 查看响应头：
# X-Match-Location: Example-3-Params
# X-Download-Speed: 200k

time curl -o /tmp/test-default.zip "http://limit.test.com/files/test.zip"
# 预期：10MB 文件，200KB/s 速度，大约需要 50 秒
```

**⚠️ Location 匹配优先级说明**：

本示例特别展示了 Nginx location 匹配优先级问题，这是配置中最容易出错的地方！

| 优先级 | 匹配类型 | 语法 | 示例 | 说明 |
|-------|---------|------|------|------|
| **1** | 精确匹配 | `= /path` | `location = /downloads/slow.zip` | 完全匹配时优先级最高 |
| **2** | 完整前缀匹配 | `^~ /path` | `location ^~ /downloads/slow.zip` | 匹配后不再检查正则 |
| **3** | 正则匹配 | `~ pattern` | `location ~* \.(zip\|tar)$` | 按配置顺序，先匹配先使用 |
| **4** | 前缀匹配 | `/path` | `location /downloads/` | 最长前缀优先 |

**本示例配置分析**：

```nginx
# 示例 1：^~ /downloads/slow.zip
# 匹配优先级：2（完整前缀匹配）
# 请求 /downloads/slow.zip → 匹配示例1，limit_rate 100KB/s

# 示例 2：~* \.(zip|tar|gz)$
# 匹配优先级：3（正则匹配）
# 请求 /downloads/normal.zip → 匹配示例2（因为示例1没有匹配）
# 请求 /downloads/slow2.zip → 匹配示例2，且 if 条件触发，limit_rate 10KB/s

# 示例 3：^~ /files/
# 匹配优先级：2（完整前缀匹配）
# 请求 /files/test.zip → 匹配示例3（因为 ^~ 优先于正则）
```

**关键知识点**：

1. **`^~` 的作用**：一旦匹配，就不再检查后续的正则 location
2. **正则的风险**：会覆盖普通前缀匹配（如示例3如果不用 `^~`，会被示例2的正则覆盖）
3. **调试技巧**：使用 `add_header X-Match-Location` 来判断匹配了哪个 location

**如果配置错误**（旧版本问题）：

```nginx
# ❌ 错误配置
location /downloads/slow.zip { ... }     # 前缀匹配，优先级低
location ~* \.(zip|tar|gz)$ { ... }      # 正则匹配，优先级高
location /downloads/ { ... }             # 前缀匹配，优先级低

# 结果：所有 .zip 文件都被正则捕获，示例1和示例3失效！
```

**修复方法**：使用 `^~` 提升优先级，避免被正则覆盖。

---

**limit_rate 指令说明**：

| 指令 | 说明 | 示例 |
|------|------|------|
| `limit_rate` | 限制向客户端传送响应的速率 | `limit_rate 100k;` |
| `limit_rate_after` | 传输指定大小后才开始限速 | `limit_rate_after 5m;` |

**实际应用场景**：

1. **防止带宽被大文件下载占满**
2. **提供付费用户高速下载，免费用户限速下载**
3. **保护服务器资源，避免恶意下载**

```nginx
# 组合使用：下载 5MB 后开始限速
location /downloads/ {
    limit_rate_after 5m;   # 前 5MB 不限速
    limit_rate 200k;       # 5MB 之后限速为 200KB/s
}
```

### 5.7 实战：URL 美化

```bash
# 将 /article.php?id=123&page=2 重写为 /article/123/page/2
cat > /data/server/nginx/conf/conf.d/rewrite-url-beauty.conf <<'EOF'
server {
    listen 80;
    server_name beauty.test.com;

    # 美化 URL：/article/123/page/2
    location ~* ^/article/(\d+)/page/(\d+)$ {
        rewrite ^/article/(\d+)/page/(\d+)$ /article-view?id=$1&page=$2 last;
    }

    # 美化 URL：/article/123
    location ~* ^/article/(\d+)$ {
        rewrite ^/article/(\d+)$ /article-view?id=$1 last;
    }

    location /article-view {
        return 200 "Article ID: $arg_id, Page: $arg_page\n";
    }

    # 美化 URL：/category/tech
    location ~* ^/category/([a-z]+)$ {
        rewrite ^/category/([a-z]+)$ /category-list?name=$1 last;
    }

    location /category-list {
        return 200 "Category: $arg_name\n";
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试
curl -H "Host: beauty.test.com" http://127.0.0.1/article/123
curl beauty.test.com/article/123
# 输出：Article ID: 123, Page:

curl -H "Host: beauty.test.com" http://127.0.0.1/article/456/page/3
curl beauty.test.com/article/123/page/3
# 输出：Article ID: 456, Page: 3

curl -H "Host: beauty.test.com" http://127.0.0.1/category/tech
curl beauty.test.com/category/tech
# 输出：Category: tech
```

---

## 🔁 第六部分：反向代理配置

### 6.1 基础反向代理

#### 6.1.1 proxy_pass 指令详解

```nginx
proxy_pass URL;
```

**URL 格式**：

| 格式 | 说明 | 示例 |
|------|------|------|
| `http://IP:PORT` | 代理到指定后端服务器 | `proxy_pass http://10.0.7.61:80;` |
| `http://upstream_name` | 代理到 upstream 组 | `proxy_pass http://backend;` |
| `http://IP/path/` | 代理并修改 URI | `proxy_pass http://10.0.7.61/app/;` |

**重要规则**：

```nginx
# 规则 1：proxy_pass 不带 URI
location /api/ {
    proxy_pass http://10.0.7.61;  # 完整 URI 传递给后端
    # 访问 /api/test → 后端收到 /api/test
}

# 规则 2：proxy_pass 带 URI
location /api/ {
    proxy_pass http://10.0.7.61/backend/;  # 替换 URI
    # 访问 /api/test → 后端收到 /backend/test
}
```

#### 6.1.2 基础代理配置

```bash
# 在代理服务器中配置
sudo docker compose exec -it nginx-proxy bash

cat > /data/server/nginx/conf/conf.d/proxy-basic.conf <<'EOF'
server {
    listen 80;
    server_name proxy.test.com;

    # 代理所有请求到后端服务器 1
    location / {
        proxy_pass http://10.0.7.61;
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试（从宿主机访问）
curl -H "Host: proxy.test.com" http://127.0.0.1:8060/
http://proxy.test.com/
# 预期输出：后端服务器 1 的首页内容（Backend Server 1）
```

### 6.2 负载均衡（upstream）

#### 6.2.1 upstream 配置

```bash
cat > /data/server/nginx/conf/conf.d/proxy-upstream.conf <<'EOF'
# 定义后端服务器组
upstream backend_servers {
    # 默认使用轮询（round-robin）
    server 10.0.7.61:80;  # 后端服务器 1
    server 10.0.7.62:80;  # 后端服务器 2
}

server {
    listen 80;
    server_name lb.test.com;

    location / {
        proxy_pass http://backend_servers;
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试负载均衡
for i in {1..10}; do
    curl -H "Host: lb.test.com" http://127.0.0.1:8060/api/test
done

# 预期输出：交替显示 backend-1 和 backend-2
# {"server": "backend-1", ...}
# {"server": "backend-2", ...}
# {"server": "backend-1", ...}
# ...
```

#### 6.2.2 负载均衡算法

**轮询（默认）**：

```nginx
upstream backend {
    server 10.0.7.61;
    server 10.0.7.62;
}
```

**权重（weight）**：

```nginx
upstream backend {
    server 10.0.7.61 weight=3;  # 权重 3
    server 10.0.7.62 weight=1;  # 权重 1
    # 10.0.7.61 接收 75% 的请求，10.0.7.62 接收 25%
}
```

**IP 哈希（ip_hash）**：

```nginx
upstream backend {
    ip_hash;  # 同一客户端 IP 始终访问同一后端
    server 10.0.7.61;
    server 10.0.7.62;
}
```

**最少连接（least_conn）**：

```nginx
upstream backend {
    least_conn;  # 将请求发送到连接数最少的服务器
    server 10.0.7.61;
    server 10.0.7.62;
}
```

#### 6.2.3 服务器状态标志

```nginx
upstream backend {
    server 10.0.7.61 weight=3 max_fails=2 fail_timeout=30s;
    server 10.0.7.62 backup;  # 备用服务器
    server 10.0.7.63 down;    # 暂时下线
}
```

| 参数 | 说明 |
|------|------|
| **weight=N** | 权重（默认为 1） |
| **max_fails=N** | 失败 N 次后标记为不可用（默认 1） |
| **fail_timeout=TIME** | 标记为不可用的时间（默认 10s） |
| **backup** | 备用服务器（所有主服务器不可用时启用） |
| **down** | 标记服务器永久不可用 |

#### 6.2.4 健康检查实践

```bash
cat > /data/server/nginx/conf/conf.d/proxy-health.conf <<'EOF'
upstream backend_with_health {
    server 10.0.7.61 max_fails=3 fail_timeout=10s;
    server 10.0.7.62 max_fails=3 fail_timeout=10s;
}

server {
    listen 80;
    server_name health.test.com;

    location / {
        proxy_pass http://backend_with_health;
        proxy_next_upstream error timeout http_502 http_503 http_504;
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试：停止后端服务器 1
sudo docker compose exec nginx-backend-1 nginx -s stop

# 再次访问，请求会自动转发到后端服务器 2
curl -H "Host: health.test.com" http://127.0.0.1:8060/api/test

# 预期输出：{"server": "backend-2", ...}（自动切换到可用服务器）
```

### 6.3 proxy_set_header 设置请求头

```bash
cat > /data/server/nginx/conf/conf.d/proxy-headers.conf <<'EOF'
server {
    listen 80;
    server_name headers.test.com;

    location / {
        proxy_pass http://10.0.7.61;

        # 设置 Host 头（后端需要正确的 Host）
        proxy_set_header Host $host;

        # 传递真实客户端 IP
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # 传递协议
        proxy_set_header X-Forwarded-Proto $scheme;

        # 自定义头
        proxy_set_header X-Custom-Header "Proxied by Nginx";
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 在后端服务器中查看请求头
sudo docker compose exec nginx-backend-1 bash

# 在现有的 default.conf 中添加 /headers location（避免创建新文件导致冲突）
cat > /data/server/nginx/conf/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /data/wwwroot/backend-1;

    location / {
        index index.html;
    }

    location /api/ {
        default_type application/json;
        return 200 '{
            "server": "backend-1",
            "ip": "10.0.7.61",
            "time": "$time_iso8601",
            "request_uri": "$request_uri"
        }\n';
    }

    # 新增：显示接收到的请求头
    location /headers {
        default_type text/plain;
        return 200 "
Host: $host
X-Real-IP: $http_x_real_ip
X-Forwarded-For: $http_x_forwarded_for
X-Forwarded-Proto: $http_x_forwarded_proto
X-Custom-Header: $http_x_custom_header
Remote-Addr: $remote_addr
";
    }
}
EOF

nginx -s reload

# 测试（从代理服务器访问）
sudo docker compose exec nginx-proxy bash
curl -H "Host: headers.test.com" http://127.0.0.1/headers

# 预期输出：
# Host: headers.test.com
# X-Real-IP: 10.0.7.60
# X-Forwarded-For: 10.0.7.60
# ...
```

---

## 📦 第七部分：动静分离实践

### 7.1 动静分离架构设计

```
客户端请求
    ↓
Nginx 代理服务器（10.0.7.60）
    ├─ 静态资源（*.css, *.js, *.png, *.jpg）
    │   → 转发到静态服务器（10.0.7.63）
    └─ 动态请求（/api/*, *.php）
        → 负载均衡到后端服务器（10.0.7.61, 10.0.7.62）
```

### 7.2 配置动静分离

```bash
# 在代理服务器中配置
sudo docker compose exec -it nginx-proxy bash

cat > /data/server/nginx/conf/conf.d/proxy-separation.conf <<'EOF'
# 定义后端服务器组
upstream backend_dynamic {
    server 10.0.7.61;
    server 10.0.7.62;
}

# 定义静态资源服务器
upstream backend_static {
    server 10.0.7.63;
}

server {
    listen 80;
    server_name separation.test.com;

    # 静态资源：HTML、CSS、JS、图片
    location ~* \.(html|htm|css|js|jpg|jpeg|png|gif|ico|webp|svg)$ {
        proxy_pass http://backend_static;
        proxy_set_header Host $host;

        # 静态资源缓存
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # 静态资源目录：/static/
    location /static/ {
        proxy_pass http://backend_static;
        proxy_set_header Host $host;
        expires 7d;
    }

    # 动态请求：API 接口
    location /api/ {
        proxy_pass http://backend_dynamic;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # 动态请求不缓存
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # 默认请求：转发到后端动态服务器
    location / {
        proxy_pass http://backend_dynamic;
        proxy_set_header Host $host;
    }
}
EOF

# 重载 Nginx
nginx -s reload
```

### 7.3 测试动静分离

#### 7.3.1 测试静态资源（应转发到 10.0.7.63）

```bash
# 从代理服务器测试
sudo docker compose exec nginx-proxy bash

# 测试图片
curl -I -H "Host: separation.test.com" http://127.0.0.1/static/images/logo.png

# 查看响应头，确认是否来自静态服务器
curl -v -H "Host: separation.test.com" http://127.0.0.1/static/css/style.css 2>&1 | grep -i server

# 测试 CSS 文件
curl -H "Host: separation.test.com" http://127.0.0.1/static/css/style.css

# 预期输出：CSS 文件内容（来自静态服务器）
```

#### 7.3.2 测试动态请求（应转发到 10.0.7.61 或 10.0.7.62）

```bash
# 测试 API 请求
for i in {1..5}; do
    curl -H "Host: separation.test.com" http://127.0.0.1/api/test
done

# 预期输出：交替显示 backend-1 和 backend-2
```

#### 7.3.3 查看日志验证

```bash
# 在静态服务器查看访问日志
sudo docker compose exec nginx-static tail /data/server/nginx/logs/access.log

# 应看到 /static/ 和图片请求

# 在后端服务器 1 查看访问日志
sudo docker compose exec nginx-backend-1 tail /data/server/nginx/logs/access.log

# 应看到 /api/ 请求
```

### 7.4 完整测试页面

```bash
# 在静态服务器创建测试页面（HTML 是静态资源，应放在静态服务器）
sudo docker compose exec nginx-static bash

cat > /data/wwwroot/nginx-static/demo.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>动静分离测试</title>
    <link rel="stylesheet" href="/static/css/style.css">
</head>
<body>
    <h1>动静分离测试页面</h1>
    <p>这是静态服务器 (10.0.7.63) 上的 HTML 文件</p>
    <img src="/static/images/logo.png" alt="Logo">
    <script src="/static/js/app.js"></script>
    <div id="api-result">正在加载 API 数据...</div>
    <script>
        // 调用动态 API（会转发到 backend-1 或 backend-2）
        fetch('/api/test')
            .then(res => res.json())
            .then(data => {
                document.getElementById('api-result').innerHTML =
                    '<strong>API Server:</strong> ' + data.server + '<br>' +
                    '<strong>API IP:</strong> ' + data.ip + '<br>' +
                    '<strong>Time:</strong> ' + data.time;
            })
            .catch(err => {
                document.getElementById('api-result').innerText =
                    'API 请求失败: ' + err.message;
            });
    </script>
</body>
</html>
EOF

# 从宿主机访问
curl -H "Host: separation.test.com" http://127.0.0.1:8060/demo.html

# 查看响应头（确认是否来自静态服务器）
curl -I -H "Host: separation.test.com" http://127.0.0.1:8060/demo.html
# 应该看到：
# Cache-Control: public, immutable
# Expires: （30天后的日期）

# 在浏览器中访问（如果配置了 DNS）
# http://separation.test.com/demo.html
```

**⚠️ 动静分离架构说明**：

在本示例中，资源的分离策略如下：

| 资源类型 | 扩展名 | 转发目标 | 缓存策略 | 说明 |
|---------|-------|---------|---------|------|
| **HTML 文件** | `.html`, `.htm` | nginx-static (10.0.7.63) | 30天 | HTML 也是静态资源 |
| **CSS 文件** | `.css` | nginx-static (10.0.7.63) | 30天 | 样式表文件 |
| **JS 文件** | `.js` | nginx-static (10.0.7.63) | 30天 | JavaScript 文件 |
| **图片文件** | `.jpg`, `.png`, `.gif` 等 | nginx-static (10.0.7.63) | 30天 | 图片资源 |
| **静态目录** | `/static/*` | nginx-static (10.0.7.63) | 7天 | 统一静态资源目录 |
| **API 请求** | `/api/*` | backend_dynamic (10.0.7.61/62) | 不缓存 | 动态数据接口 |
| **其他请求** | `/` | backend_dynamic (10.0.7.61/62) | 默认 | 动态页面、表单提交等 |

**关键知识点**：

1. **HTML 是静态资源**：虽然 HTML 包含 JavaScript 代码可以调用 API，但 HTML 文件本身是静态的，应该放在静态服务器上并设置长缓存
2. **Location 匹配优先级**：
   - 正则匹配 `~* \.(html|css|js)$` 优先于前缀匹配 `/`
   - 所以 `/demo.html` 会被正则捕获，转发到静态服务器
   - `/api/test` 会被 `/api/` 前缀匹配，转发到动态服务器
3. **浏览器中的 JavaScript**：HTML 文件中的 JavaScript 代码（`fetch('/api/test')`）会在**浏览器端执行**，直接向代理服务器发起 `/api/test` 请求，这个请求会被转发到动态服务器

**请求流程**：

```
浏览器请求 /demo.html
    ↓
nginx-proxy (10.0.7.60)
    ↓ 匹配 ~* \.(html)$
nginx-static (10.0.7.63) - 返回 HTML 文件
    ↓
浏览器收到 HTML 并解析
    ↓
浏览器执行 JavaScript: fetch('/api/test')
    ↓
浏览器再次向 nginx-proxy 请求 /api/test
    ↓
nginx-proxy (10.0.7.60)
    ↓ 匹配 /api/
backend-1 或 backend-2 (10.0.7.61/62) - 返回 JSON 数据
```

---

## 💾 第八部分：代理缓存配置与测试

### 8.1 缓存原理与配置

#### 8.1.1 缓存区域定义（proxy_cache_path）

```nginx
proxy_cache_path /path/to/cache
                 levels=1:2
                 keys_zone=cache_name:10m
                 max_size=1g
                 inactive=60m;
```

| 参数 | 说明 |
|------|------|
| **levels=1:2** | 缓存目录层级（1级目录1个字符，2级目录2个字符） |
| **keys_zone=name:size** | 共享内存区域名称和大小（用于存储缓存键） |
| **max_size=SIZE** | 缓存最大磁盘空间 |
| **inactive=TIME** | 缓存项未访问后的过期时间 |

#### 8.1.2 缓存配置

```bash
# 在代理服务器中配置
sudo docker compose exec -it nginx-proxy bash

# 创建缓存目录
mkdir -p /tmp/nginx/cache
chown -R nginx:nginx /tmp/nginx/cache 2>/dev/null || chown -R nobody:nogroup /tmp/nginx/cache

# 配置缓存
cat > /data/server/nginx/conf/conf.d/proxy-cache.conf <<'EOF'
# 定义缓存区域（放在 http 段或 server 段之外）
proxy_cache_path /tmp/nginx/cache
                 levels=1:2
                 keys_zone=my_cache:10m
                 max_size=500m
                 inactive=60m
                 use_temp_path=off;

upstream backend_cache {
    server 10.0.7.61;
    server 10.0.7.62;
}

server {
    listen 80;
    server_name cache.test.com;

    # 添加缓存状态头（用于调试）
    add_header X-Cache-Status $upstream_cache_status;

    location / {
        proxy_pass http://backend_cache;

        # 启用缓存
        proxy_cache my_cache;

        # 缓存键（默认为 $scheme$proxy_host$request_uri）
        proxy_cache_key "$scheme$host$request_uri";

        # 缓存有效期（根据状态码）
        proxy_cache_valid 200 304 10m;  # 200 和 304 缓存 10 分钟
        proxy_cache_valid 404 1m;       # 404 缓存 1 分钟
        proxy_cache_valid any 5m;       # 其他状态码缓存 5 分钟

        # 缓存使用条件
        proxy_cache_methods GET HEAD;   # 只缓存 GET 和 HEAD 请求
        proxy_cache_min_uses 2;         # 至少访问 2 次才缓存

        # 设置请求头
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # 不缓存 API 请求
    location /api/ {
        proxy_pass http://backend_cache;
        proxy_cache off;  # 禁用缓存
        proxy_set_header Host $host;
    }
}
EOF

# 重载 Nginx
nginx -s reload
```

### 8.2 测试缓存

#### 8.2.1 测试缓存命中

```bash
# 在代理服务器中测试
sudo docker compose exec nginx-proxy bash

# 第 1 次访问（缓存未命中）
curl -I -H "Host: cache.test.com" http://127.0.0.1/

# 查看响应头
# X-Cache-Status: MISS（缓存未命中）

# 第 2 次访问（缓存未命中，因为 proxy_cache_min_uses=2）
curl -I -H "Host: cache.test.com" http://127.0.0.1/

# X-Cache-Status: MISS

# 第 3 次访问（缓存命中）
curl -I -H "Host: cache.test.com" http://127.0.0.1/

# X-Cache-Status: HIT（缓存命中）

# 后续访问都会从缓存返回
for i in {1..5}; do
    curl -I -H "Host: cache.test.com" http://127.0.0.1/ | grep X-Cache-Status
done

# 预期输出：全部显示 HIT
```

#### 8.2.2 缓存状态说明

| 状态 | 说明 |
|------|------|
| **MISS** | 缓存未命中，从后端获取 |
| **HIT** | 缓存命中，直接返回缓存内容 |
| **EXPIRED** | 缓存过期，重新从后端获取 |
| **STALE** | 缓存过期但后端不可用，返回旧缓存 |
| **UPDATING** | 缓存正在更新，返回旧缓存 |
| **REVALIDATED** | 缓存验证通过（304 Not Modified） |
| **BYPASS** | 跳过缓存（如 POST 请求） |

#### 8.2.3 查看缓存文件

**缓存目录结构说明**：

Nginx 缓存文件按照 `levels=1:2` 配置，生成两级目录结构：
- 第一级目录：MD5 哈希的最后 1 个字符
- 第二级目录：MD5 哈希的倒数第 2-3 个字符
- 文件名：完整的 MD5 哈希值

```bash
# 1. 查看缓存目录树形结构
tree /tmp/nginx/cache/ -L 3

# 预期输出：
# /tmp/nginx/cache/
# ├── 1
# │   └── a2
# │       └── 7e2b55c4c38e99561caa378268f87a21
# ├── 9
# │   └── cf
# │       └── 7e2b55c4c38e99561caa378268f87cf9
# └── temp  # 临时目录

# 2. 查看缓存文件详细信息
ls -lh /tmp/nginx/cache/1/*/*

# 输出示例：
# -rw------- 1 nginx nginx 453 Oct 18 10:00 /tmp/nginx/cache/1/a2/7e2b55c4c38e99561caa378268f87a21

# 3. 查看缓存文件类型
file /tmp/nginx/cache/1/a2/*

# 输出：
# /tmp/nginx/cache/1/a2/7e2b55c4c38e99561caa378268f87a21: data
# 说明：缓存文件是二进制数据文件

# 4. 查看缓存文件完整内容
cat /tmp/nginx/cache/1/a2/7e2b55c4c38e99561caa378268f87a21

# 输出示例：
# ⏎KEY: httpcache.test.com/
# HTTP/1.1 200 OK
# Server: nginx/1.24.0
# Date: Thu, 18 Oct 2025 02:00:00 GMT
# Content-Type: text/html
# Content-Length: 18
# Last-Modified: Wed, 17 Oct 2025 10:00:00 GMT
# Connection: close
# ETag: "671234567890"
# X-Cache-Status: HIT
# Accept-Ranges: bytes
#
# Static Web Server  # ← 实际缓存的内容

# 5. 只查看缓存文件头部（元数据）
head -20 /tmp/nginx/cache/1/*/*

# 6. 只查看缓存的实际内容（跳过头部）
tail -n +15 /tmp/nginx/cache/1/a2/* | head -5

# 7. 查看缓存文件的修改时间
stat /tmp/nginx/cache/1/a2/*

# 输出：
# File: /tmp/nginx/cache/1/a2/7e2b55c4c38e99561caa378268f87a21
# Size: 453         Blocks: 8          IO Block: 4096   regular file
# Access: (0600/-rw-------)  Uid: (  101/  nginx)   Gid: (  101/  nginx)
# Access: 2025-10-18 10:05:00.000000000 +0800
# Modify: 2025-10-18 10:00:00.000000000 +0800  # ← 缓存创建时间
# Change: 2025-10-18 10:00:00.000000000 +0800

# 8. 统计缓存文件数量
find /tmp/nginx/cache -type f | wc -l

# 9. 统计缓存总大小
du -sh /tmp/nginx/cache

# 输出：
# 15M  /tmp/nginx/cache

# 10. 查看最近缓存的文件（按修改时间排序）
find /tmp/nginx/cache -type f -printf '%T@ %p\n' | sort -rn | head -10 | awk '{print $2}' | xargs ls -lh
```

**缓存文件内容结构**：

```
┌─────────────────────────────────────┐
│ 缓存键（Cache Key）                  │  ← KEY: 行，标识缓存内容
├─────────────────────────────────────┤
│ HTTP 响应头（Response Headers）      │  ← HTTP/1.1 状态码及响应头
│ - HTTP/1.1 200 OK                   │
│ - Server: nginx                     │
│ - Date: ...                         │
│ - Content-Type: ...                 │
│ - Last-Modified: ...                │
│ - ETag: ...                         │
├─────────────────────────────────────┤
│ 空行                                 │  ← 头部与内容的分隔
├─────────────────────────────────────┤
│ HTTP 响应体（Response Body）         │  ← 实际缓存的内容
│ 例如：HTML 页面、JSON 数据、图片等    │
└─────────────────────────────────────┘
```

**实用技巧**：

```bash
# 技巧 1：根据 URL 查找缓存文件
# 计算 URL 的 MD5 值
echo -n "httpcache.test.com/" | md5sum
# 输出：7e2b55c4c38e99561caa378268f87cf9

# 根据 MD5 定位缓存文件路径
# 最后 1 位：9 → /tmp/nginx/cache/9/
# 倒数 2-3 位：cf → /tmp/nginx/cache/9/cf/
# 完整文件名：7e2b55c4c38e99561caa378268f87cf9

# 技巧 2：监控缓存文件变化
watch -n 1 'find /tmp/nginx/cache -type f | wc -l'

# 技巧 3：查看缓存命中率
# 通过日志统计 X-Cache-Status
tail -1000 /data/server/nginx/logs/access.log | grep "X-Cache-Status: HIT" | wc -l
tail -1000 /data/server/nginx/logs/access.log | grep "X-Cache-Status: MISS" | wc -l

# 技巧 4：清除过期缓存
# Nginx 会自动清理（根据 inactive 参数）
# 手动清理：
find /tmp/nginx/cache -type f -mtime +1 -delete  # 删除 1 天前的缓存
```

### 8.3 缓存控制

#### 8.3.1 根据请求参数缓存

```bash
cat > /data/server/nginx/conf/conf.d/proxy-cache-advanced.conf <<'EOF'
proxy_cache_path /tmp/nginx/cache_advanced
                 levels=1:2
                 keys_zone=advanced_cache:10m
                 max_size=100m
                 inactive=10m;

server {
    listen 80;
    server_name cache-adv.test.com;

    add_header X-Cache-Status $upstream_cache_status;

    location /api/ {
        proxy_pass http://10.0.7.61;

        # 启用缓存
        proxy_cache advanced_cache;

        # 缓存键包含查询参数
        proxy_cache_key "$scheme$host$uri$is_args$args";

        # 缓存有效期
        proxy_cache_valid 200 5m;

        # 忽略后端的缓存控制头
        proxy_ignore_headers Cache-Control Expires;

        proxy_set_header Host $host;
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试不同参数的缓存
curl -I -H "Host: cache-adv.test.com" http://127.0.0.1/api/test?id=1
curl -I -H "Host: cache-adv.test.com" http://127.0.0.1/api/test?id=2
curl -I -H "Host: cache-adv.test.com" http://127.0.0.1/api/test?id=1

# 第一个和第三个请求缓存相同（参数相同）
# 第二个请求单独缓存（参数不同）
```

#### 8.3.2 根据 Cookie 决定是否缓存

```bash
cat > /data/server/nginx/conf/conf.d/proxy-cache-cookie.conf <<'EOF'
server {
    listen 80;
    server_name cache-cookie.test.com;

    add_header X-Cache-Status $upstream_cache_status;

    location / {
        proxy_pass http://10.0.7.61;

        # 有 Cookie 时不缓存
        proxy_cache my_cache;
        proxy_cache_bypass $cookie_nocache $arg_nocache;
        proxy_no_cache $cookie_nocache;

        proxy_cache_valid 200 5m;
        proxy_set_header Host $host;
    }
}
EOF

# 重载 Nginx
nginx -s reload

# 测试：无 Cookie 时缓存
curl -I -H "Host: cache-cookie.test.com" http://127.0.0.1/
# X-Cache-Status: MISS → HIT

# 测试：有 Cookie 时不缓存
curl -I -b "nocache=1" -H "Host: cache-cookie.test.com" http://127.0.0.1/
curl -I  -H "Host: cache-cookie.test.com" http://127.0.0.1?nocache=1
# X-Cache-Status: BYPASS（跳过缓存）
```

### 8.4 清除缓存

#### 8.4.1 手动清除缓存

```bash
# 删除所有缓存文件
rm -rf /tmp/nginx/cache/*

# 删除特定 URL 的缓存（需要找到对应的缓存文件）
# 缓存文件名是 URL 的 MD5 哈希值
echo -n "http://cache.test.com/" | md5sum
# 输出：abc123...

# 查找并删除
find /tmp/nginx/cache -name "*abc123*" -delete
```

#### 8.4.2 使用 proxy_cache_purge（需要第三方模块）

```nginx
# 需要编译时加入 --add-module=ngx_cache_purge
location ~ /purge(/.*) {
    proxy_cache_purge my_cache "$scheme$host$1";
}
```

---

## 🌍 第九部分：IP 透传配置

### 9.1 为什么需要 IP 透传

在反向代理架构中，后端服务器看到的客户端 IP 是代理服务器的 IP，而非真实客户端 IP。

```
客户端（1.2.3.4）→ 代理服务器（10.0.7.60）→ 后端服务器（10.0.7.61）

后端服务器日志：
10.0.7.60 - - [12/Oct/2025:10:00:00] "GET / HTTP/1.0" 200
    ↑ 代理服务器 IP，而非客户端真实 IP
```

### 9.2 X-Real-IP 和 X-Forwarded-For

**核心区别**：

| 特性 | X-Real-IP | X-Forwarded-For |
|------|-----------|----------------|
| **用途** | 记录客户端的真实 IP 地址 | 记录经过的代理服务器的 IP 地址列表 |
| **格式** | 单个 IP 地址 | 逗号分隔的 IP 列表 |
| **示例** | `1.2.3.4` | `1.2.3.4, 5.6.7.8, 9.10.11.12` |
| **含义** | 最初发起请求的客户端 IP | 完整的代理链路（从左到右） |
| **设置方式** | `proxy_set_header X-Real-IP $remote_addr;` | `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` |
| **是否标准** | 非标准头（常用但非 RFC 标准） | RFC 7239 准标准头 |
| **多层代理** | 只记录第一层代理看到的客户端 IP | 记录完整代理链 |
| **使用场景** | 简单的单层代理场景 | 多层代理、CDN、负载均衡场景 |

**详细说明**：

#### 9.2.1 X-Real-IP 详解

**设置方式**：
```nginx
proxy_set_header X-Real-IP $remote_addr;
```

**工作原理**：
- `$remote_addr` 是 Nginx 内置变量，表示与当前 Nginx 直接建立连接的客户端 IP
- X-Real-IP 是一个自定义 HTTP 头，用于传递这个 IP 给后端服务器
- 每次代理转发时，会**覆盖**之前的 X-Real-IP 值

**示例场景**：
```
客户端（1.2.3.4）→ Nginx 代理（10.0.7.60）→ 后端服务器（10.0.7.61）

在 Nginx 代理上：
$remote_addr = 1.2.3.4
设置：X-Real-IP: 1.2.3.4

后端服务器收到：
X-Real-IP: 1.2.3.4  ← 记录了真实客户端 IP
```

**优点**：
- 简单直接，易于理解
- 只包含一个 IP，便于解析

**缺点**：
- 多层代理时，会丢失中间代理信息
- 如果客户端伪造 X-Real-IP 头，可能被覆盖（取决于配置）

---

#### 9.2.2 X-Forwarded-For 详解

**设置方式**：
```nginx
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

**$proxy_add_x_forwarded_for 变量展开**：
```
$proxy_add_x_forwarded_for = $http_x_forwarded_for, $remote_addr
```

**工作原理**：
- 如果请求已经包含 X-Forwarded-For 头，追加当前 `$remote_addr`
- 如果请求没有 X-Forwarded-For 头，创建新的并设置为 `$remote_addr`
- 每次代理转发时，会**追加**新的 IP，而不是覆盖

**示例场景 1：单层代理**
```
客户端（1.2.3.4）→ Nginx 代理（10.0.7.60）→ 后端服务器（10.0.7.61）

在 Nginx 代理上：
$remote_addr = 1.2.3.4
$http_x_forwarded_for = 空（客户端未设置）
$proxy_add_x_forwarded_for = 1.2.3.4

后端服务器收到：
X-Forwarded-For: 1.2.3.4  ← 最左边是真实客户端 IP
```

**示例场景 2：多层代理**
```
客户端（1.2.3.4）→ CDN（5.6.7.8）→ Nginx 代理（10.0.7.60）→ 后端服务器（10.0.7.61）

在 CDN 上：
X-Forwarded-For: 1.2.3.4  ← CDN 添加

在 Nginx 代理上：
$remote_addr = 5.6.7.8（CDN 的 IP）
$http_x_forwarded_for = 1.2.3.4（来自 CDN）
$proxy_add_x_forwarded_for = 1.2.3.4, 5.6.7.8

后端服务器收到：
X-Forwarded-For: 1.2.3.4, 5.6.7.8
                   ↑         ↑
              真实客户端    CDN IP
```

**优点**：
- 保留完整的代理链路
- 可以追溯请求经过的所有代理
- 适合复杂的网络架构

**缺点**：
- 包含多个 IP，需要解析
- 客户端可以伪造 X-Forwarded-For 头（需要后端验证）

---

#### 9.2.3 如何选择？

**使用 X-Real-IP 的场景**：
1. **简单的单层代理架构**
2. **后端只需要知道真实客户端 IP**
3. **不关心中间代理链路**

**使用 X-Forwarded-For 的场景**：
1. **多层代理架构（如 CDN + 负载均衡 + 应用服务器）**
2. **需要追溯完整的代理链路**
3. **安全审计需求（记录所有代理 IP）**
4. **需要防止 IP 伪造（可以验证 IP 链）**

**推荐配置**：
```nginx
location / {
    proxy_pass http://backend;

    # 同时设置两个头（推荐）
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

    # 还可以设置协议头
    proxy_set_header X-Forwarded-Proto $scheme;  # http 或 https

    # 设置原始 Host
    proxy_set_header Host $host;
}
```

---

#### 9.2.4 读取真实客户端 IP 的最佳实践

**后端服务器读取逻辑**：

```nginx
# 优先级：X-Real-IP > X-Forwarded-For 最左边的 IP > $remote_addr

# 方法 1：使用 map 提取真实 IP
map $http_x_forwarded_for $real_ip {
    ~^([^,]+) $1;          # 提取 X-Forwarded-For 最左边的 IP
    default   $remote_addr;
}

# 方法 2：使用 realip 模块（推荐）
set_real_ip_from 10.0.7.60;           # 信任代理服务器 IP
set_real_ip_from 10.0.7.0/24;         # 信任整个代理网段
real_ip_header X-Forwarded-For;       # 从 X-Forwarded-For 提取 IP
real_ip_recursive on;                 # 递归查找（跳过信任的代理 IP）

# 此时 $remote_addr 已经是真实客户端 IP
log_format main '$remote_addr - $remote_user [$time_local] "$request"';
```

**安全注意事项**：

1. **防止 IP 伪造**：
```nginx
# 只信任已知的代理服务器
set_real_ip_from 10.0.7.60;  # 只信任这个代理
set_real_ip_from 5.6.7.0/24; # 只信任 CDN 网段

# 不要信任所有 IP
# ❌ set_real_ip_from 0.0.0.0/0;  # 不安全！
```

2. **验证 IP 格式**：
```nginx
# 确保 X-Forwarded-For 包含有效的 IP
if ($http_x_forwarded_for !~ "^([0-9]{1,3}\.){3}[0-9]{1,3}") {
    return 400 "Invalid X-Forwarded-For";
}
```

3. **日志记录完整信息**：
```nginx
log_format detailed '$remote_addr - $http_x_real_ip - $http_x_forwarded_for '
                    '[$time_local] "$request" $status';
```

### 9.3 配置 IP 透传（代理服务器）

```bash
# 在代理服务器中配置
sudo docker compose exec -it nginx-proxy bash

cat > /data/server/nginx/conf/conf.d/proxy-real-ip.conf <<'EOF'
upstream backend_realip {
    server 10.0.7.61;
}

server {
    listen 80;
    server_name realip.test.com;

    location / {
        proxy_pass http://backend_realip;

        # 传递真实客户端 IP
        proxy_set_header X-Real-IP $remote_addr;

        # 传递完整的 IP 链（追加模式）
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        # 传递协议
        proxy_set_header X-Forwarded-Proto $scheme;

        # 传递原始 Host
        proxy_set_header Host $host;
    }
}
EOF

# 重载 Nginx
nginx -s reload
```

### 9.4 配置后端服务器读取真实 IP

#### 9.4.1 方法 1：使用内置变量（推荐）

```bash
# 在后端服务器 1 中配置
sudo docker compose exec nginx-backend-1 bash

# 第一步：在主配置文件的 http 块中定义 log_format（log_format 只能在 http 上下文）
# 备份原配置
cp /data/server/nginx/conf/nginx.conf /data/server/nginx/conf/nginx.conf.bak

# 方法 A：手动编辑（推荐，更可靠）
vim /data/server/nginx/conf/nginx.conf
# 在 http { 块中添加以下内容：
    log_format real_ip '$http_x_real_ip - $remote_user [$time_local] '
                       '"$request" $status $body_bytes_sent '
                       '"$http_referer" "$http_user_agent" '
                       'X-Forwarded-For: $http_x_forwarded_for';

 

 
# 第二步：在现有的 default.conf 中添加 /show-ip location（避免创建新文件导致冲突）
cat > /data/server/nginx/conf/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /data/wwwroot/backend-1;
    charset utf-8;
    # 使用在 nginx.conf 中定义的自定义日志格式
    access_log /data/server/nginx/logs/realip_access.log real_ip;

    location / {
        index index.html;
    }

    location /api/ {
        default_type application/json;
        return 200 '{
            "server": "backend-1",
            "ip": "10.0.7.61",
            "time": "$time_iso8601",
            "request_uri": "$request_uri"
        }\n';
    }

    # 显示接收到的请求头
    location /headers {
        default_type text/plain;
        return 200 "
Host: $host
X-Real-IP: $http_x_real_ip
X-Forwarded-For: $http_x_forwarded_for
X-Forwarded-Proto: $http_x_forwarded_proto
X-Custom-Header: $http_x_custom_header
Remote-Addr: $remote_addr
";
    }

    # 新增：显示真实 IP 信息
    location /show-ip {
     charset utf-8;
        default_type text/plain;
        return 200 "
Remote Addr (代理 IP): $remote_addr
X-Real-IP (真实客户端 IP): $http_x_real_ip
X-Forwarded-For (完整 IP 链): $http_x_forwarded_for
X-Forwarded-Proto (协议): $http_x_forwarded_proto
";
    }
}
EOF

# 删除可能存在的 realip-backend.conf（避免冲突）
rm -f /data/server/nginx/conf/conf.d/realip-backend.conf

# 验证配置
nginx -t

# 重载 Nginx
nginx -s reload

# 第三步：测试配置
# 从代理服务器发起请求
exit  # 退出 backend-1 容器

sudo docker compose exec nginx-proxy bash
curl http://10.0.7.61/show-ip

# 预期输出：
# Remote Addr (代理 IP): 10.0.7.60
# X-Real-IP (真实客户端 IP): <宿主机 IP>
# X-Forwarded-For (完整 IP 链): <宿主机 IP>
# X-Forwarded-Proto (协议): http

# 查看后端服务器的日志（应该记录真实客户端 IP）
sudo docker compose exec nginx-backend-1 tail -5 /data/server/nginx/logs/realip_access.log

# 预期日志格式：
# <真实客户端 IP> - - [18/Oct/2025:10:00:00 +0800] "GET /show-ip HTTP/1.0" 200 123 "-" "curl/7.68.0" X-Forwarded-For: <真实客户端 IP>
```

**⚠️ 重要说明：log_format 指令的上下文限制**

| 指令 | 允许的上下文 | 说明 |
|------|-------------|------|
| `log_format` | **仅 `http` 块** | ❌ 不能在 `server` 或 `location` 中使用 |
| `access_log` | `http`, `server`, `location` | ✅ 可以在多个位置使用 |

**错误示例**：
```nginx
server {
    log_format real_ip '...';  # ❌ 错误！会报错
    access_log /path/to/log real_ip;
}
```

**正确示例**：
```nginx
http {
    log_format real_ip '...';  # ✅ 正确！在 http 块中定义

    server {
        access_log /path/to/log real_ip;  # ✅ 在 server 中引用
    }
}
```

**⚠️ 重要说明：避免多配置文件冲突**

在本示例中，backend-1 容器已经存在 `default.conf` 监听 80 端口，因此我们**不能创建新的配置文件**也监听 80 端口，否则会导致冲突。

**错误做法**（会导致冲突）：
```bash
# ❌ default.conf 和 realip-backend.conf 同时存在
ls conf/conf.d/
# default.conf         realip-backend.conf  # 两个文件都监听 80 端口！

# default.conf:
server { listen 80; server_name _; ... }

# realip-backend.conf:
server { listen 80; ... }  # 冲突！
```

**正确做法**（在现有配置中添加）：
```bash
# ✅ 直接修改 default.conf，在原有 server 块中添加新的 location
server {
    listen 80;
    server_name _;
    location / { ... }          # 原有
    location /api/ { ... }      # 原有
    location /headers { ... }   # 原有
    location /show-ip { ... }   # 新增
}
```

**关键规则**：
- 一个端口只能有一个默认 server（`server_name _` 或无 `server_name`）
- 添加新功能时，应该在现有 server 块中添加新的 location
- 只有当需要不同的 `server_name` 时，才创建新的配置文件

---

**常见错误排查**：

**错误 1：log_format 指令位置错误**

```
nginx: [emerg] "log_format" directive is not allowed here in /path/to/file.conf:8
```

**原因**：`log_format` 指令放在了错误的位置（server 或 location 块中）

**解决步骤**：
1. 将 `log_format` 定义从 `server` 块移到主配置文件的 `http` 块
2. 保留 `server` 块中的 `access_log` 指令
3. 验证配置：`nginx -t`
4. 重载 Nginx：`nginx -s reload`

#### 9.4.2 方法 2：使用 realip 模块（修改 $remote_addr）

```bash
# 在现有的 default.conf 中添加 realip 模块配置（避免创建新文件导致冲突）
cat > /data/server/nginx/conf/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /data/wwwroot/backend-1;

    # 使用 realip 模块：信任的代理服务器 IP
    set_real_ip_from 10.0.7.60;          # 信任代理服务器
    set_real_ip_from 10.0.7.0/24;        # 信任整个网段

    # 从哪个请求头获取真实 IP
    real_ip_header X-Real-IP;            # 或 X-Forwarded-For

    # 是否递归查找（适用于多层代理）
    real_ip_recursive off;

    # 使用在 nginx.conf 中定义的自定义日志格式
    access_log /data/server/nginx/logs/realip_access.log;

    location / {
        index index.html;
    }

    location /api/ {
        default_type application/json;
        return 200 '{
            "server": "backend-1",
            "ip": "10.0.7.61",
            "time": "$time_iso8601",
            "request_uri": "$request_uri"
        }\n';
    }

    # 显示接收到的请求头
    location /headers {
        default_type text/plain;
        return 200 "
Host: $host
X-Real-IP: $http_x_real_ip
X-Forwarded-For: $http_x_forwarded_for
X-Forwarded-Proto: $http_x_forwarded_proto
X-Custom-Header: $http_x_custom_header
Remote-Addr: $remote_addr
";
    }

    # 显示真实 IP 信息（方法1：使用 $http_x_real_ip 变量）
    location /show-ip {
        default_type text/plain;
        return 200 "
Remote Addr (代理 IP): $remote_addr
X-Real-IP (真实客户端 IP): $http_x_real_ip
X-Forwarded-For (完整 IP 链): $http_x_forwarded_for
X-Forwarded-Proto (协议): $http_x_forwarded_proto
";
    }

    # 测试 realip 模块效果（方法2：$remote_addr 已被替换）
    location /real-ip-test {
        default_type text/plain;
        return 200 "Remote Addr (已替换为真实 IP): $remote_addr
X-Real-IP: $http_x_real_ip
X-Forwarded-For: $http_x_forwarded_for

说明：启用 realip 模块后，$remote_addr 变量会被自动替换为真实客户端 IP
";
    }
}
EOF

# 删除可能存在的冲突配置文件
rm -f /data/server/nginx/conf/conf.d/realip-backend.conf
rm -f /data/server/nginx/conf/conf.d/realip-module.conf

# 验证配置
nginx -t

# 重载 Nginx
nginx -s reload
```

### 9.5 测试 IP 透传

#### 9.5.1 基础测试

```bash
# 从代理服务器访问后端
sudo docker compose exec nginx-proxy bash

curl -H "Host: realip.test.com" http://127.0.0.1/show-ip

# 预期输出：
# Remote Addr (代理 IP): 10.0.7.60
# X-Real-IP (真实客户端 IP): 10.0.7.60
# X-Forwarded-For (完整 IP 链): 10.0.7.60
```

#### 9.5.2 多层代理测试

使用现有容器构建真实的三层代理架构：

```
宿主机/客户端
  ↓
第1层：nginx-proxy (10.0.7.60) - 代理服务器
  ↓ proxy_pass 到 backend-1
第2层：nginx-backend-1 (10.0.7.61) - 中间代理
  ↓ proxy_pass 到 backend-2
第3层：nginx-backend-2 (10.0.7.62) - 最终后端
```

**配置步骤**：

```bash
# 第1层：配置 nginx-proxy 代理到 backend-1
sudo docker compose exec nginx-proxy bash

cat > /data/server/nginx/conf/conf.d/proxy-multilayer.conf <<'EOF'
server {
    listen 80;
    server_name multilayer.test.com;

    location / {
        proxy_pass http://10.0.7.61;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

nginx -s reload
exit

# 第2层：配置 backend-1 作为中间代理，转发到 backend-2
sudo docker compose exec nginx-backend-1 bash

cat > /data/server/nginx/conf/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;

    # 继续代理到 backend-2（第3层）
    location / {
        proxy_pass http://10.0.7.62;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $http_x_real_ip;  # 透传第1层设置的 X-Real-IP
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;  # 追加当前层 IP
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
    }
}
EOF

nginx -s reload
exit

# 第3层：配置 backend-2 显示接收到的所有 IP 信息
sudo docker compose exec nginx-backend-2 bash

cat > /data/server/nginx/conf/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        default_type text/plain;
        charset utf-8;
        return 200 "=== 第3层后端 (backend-2) 接收到的信息 ===

Remote Addr (直接连接的 IP): $remote_addr
  ↑ 这是第2层代理 backend-1 的 IP: 10.0.7.61

X-Real-IP (第1层设置): $http_x_real_ip
  ↑ 这是宿主机/客户端的真实 IP

X-Forwarded-For (完整代理链): $http_x_forwarded_for
  ↑ 格式：客户端IP, 第1层代理IP, 第2层代理IP
  ↑ 例如：172.17.0.1, 10.0.7.60, 10.0.7.61

X-Forwarded-Proto: $http_x_forwarded_proto

Request URI: $request_uri
Host: $host
";
    }
}
EOF

nginx -s reload
exit

 
 
# 测试多层代理
curl -H "Host: multilayer.test.com" http://127.0.0.1/

# 预期输出：
# === 第3层后端 (backend-2) 接收到的信息 ===
#
# Remote Addr (直接连接的 IP): 10.0.7.61
#   ↑ 这是第2层代理 backend-1 的 IP: 10.0.7.61
#
# X-Real-IP (第1层设置): 172.17.0.1
#   ↑ 这是宿主机/客户端的真实 IP
#
# X-Forwarded-For (完整代理链): 172.17.0.1, 10.0.7.60, 10.0.7.61
#   ↑ 格式：客户端IP, 第1层代理IP, 第2层代理IP
#   ↑ 例如：172.17.0.1, 10.0.7.60, 10.0.7.61
#
# X-Forwarded-Proto: http
# Request URI: /
# Host: multilayer.test.com
```

**关键知识点：X-Forwarded-For 的累积过程**

每一层代理都会执行 `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`

`$proxy_add_x_forwarded_for` 的值为：`$http_x_forwarded_for, $remote_addr`

| 代理层 | $remote_addr | $http_x_forwarded_for（接收） | $proxy_add_x_forwarded_for（发送） |
|-------|-------------|-------------------------|------------------------------|
| **第1层 (proxy)** | 172.17.0.1（客户端） | 空 | `172.17.0.1` |
| **第2层 (backend-1)** | 10.0.7.60（第1层） | `172.17.0.1` | `172.17.0.1, 10.0.7.60` |
| **第3层 (backend-2)** | 10.0.7.61（第2层） | `172.17.0.1, 10.0.7.60` | `172.17.0.1, 10.0.7.60, 10.0.7.61` |

**请求流程图**：

```
宿主机 (172.17.0.1)
  ↓ HTTP 请求
nginx-proxy (10.0.7.60) - 第1层
  ├─ $remote_addr = 172.17.0.1
  ├─ X-Real-IP: 172.17.0.1
  └─ X-Forwarded-For: 172.17.0.1
     ↓ proxy_pass http://10.0.7.61
nginx-backend-1 (10.0.7.61) - 第2层
  ├─ $remote_addr = 10.0.7.60
  ├─ $http_x_real_ip = 172.17.0.1（透传）
  ├─ $http_x_forwarded_for = 172.17.0.1
  └─ X-Forwarded-For: 172.17.0.1, 10.0.7.60（追加）
     ↓ proxy_pass http://10.0.7.62
nginx-backend-2 (10.0.7.62) - 第3层（最终后端）
  ├─ $remote_addr = 10.0.7.61
  ├─ $http_x_real_ip = 172.17.0.1（不变）
  └─ $http_x_forwarded_for = 172.17.0.1, 10.0.7.60, 10.0.7.61
```

#### 9.5.3 查看日志验证

```bash
# 在后端服务器查看日志
sudo docker compose exec nginx-backend-1 bash
tail -f /data/server/nginx/logs/realip_access.log

# 从代理访问
sudo docker compose exec nginx-proxy curl -H "Host: realip.test.com" http://127.0.0.1/

# 日志输出：
# 10.0.7.60 - - [12/Oct/2025:10:30:00] "GET / HTTP/1.0" 200 X-Forwarded-For: 10.0.7.60
```

---

## 🔧 第十部分：故障排除

### 10.1 防盗链问题

#### 问题 1：合法请求被拒绝

**现象**：
```bash
curl -H "Referer: http://www.example.com/" http://10.0.7.63/static/images/logo.png
# 输出：403 Forbidden
```

**原因**：
- `valid_referers` 配置错误
- Referer 域名拼写错误
- 缺少通配符

**解决**：
```bash
# 检查配置
nginx -T | grep -A 5 valid_referers

# 修改配置，添加通配符
valid_referers none blocked *.example.com example.com;

# 重载配置
nginx -s reload
```

#### 问题 2：空 Referer 被拒绝

**原因**：`valid_referers` 中缺少 `none` 参数。

**解决**：
```nginx
valid_referers none blocked server_names;  # 添加 none
```

---

### 10.2 Rewrite 问题

#### 问题 1：重写死循环

**现象**：
```bash
curl http://127.0.0.1/test
# 输出：500 Internal Server Error
# 日志：rewrite or internal redirection cycle
```

**原因**：
```nginx
location /test {
    rewrite ^/test$ /test permanent;  # 死循环
}
```

**解决**：
```nginx
location /test {
    rewrite ^/test$ /test-new permanent;  # 修改目标 URI
}
```

**常见死循环场景**：

```nginx
# 场景 1：rewrite 到自身
location /page {
    rewrite ^/page$ /page last;  # ❌ 无限循环
}

# 场景 2：多个 location 互相重写
location /a {
    rewrite ^/a$ /b last;
}
location /b {
    rewrite ^/b$ /a last;  # ❌ /a 和 /b 互相重定向
}

# 场景 3：正则匹配导致的循环
location /files {
    rewrite ^/files/(.*)$ /files/$1 last;  # ❌ 重写后路径不变
}
```

**如何避免死循环**：

1. **使用 break 代替 last**（如果不需要重新匹配 location）
2. **确保重写后的 URI 与原 URI 不同**
3. **使用条件判断避免重复重写**：

```nginx
location /test {
    # 使用变量标记，避免重复重写
    if ($uri !~ "^/new/") {
        rewrite ^/test/(.*)$ /new/$1 last;
    }
}

location /new {
    # 处理重写后的请求
    return 200 "Rewritten to /new\n";
}
```

**⚠️ 重要提示**：
- Nginx 默认允许最多 10 次内部重定向
- 超过此限制会返回 `500 Internal Server Error`
- 错误日志会显示：`rewrite or internal redirection cycle`

#### 问题 2：last 和 break 混淆

**问题**：使用 `last` 但后续 location 未生效。

**解决**：
- `last`：重新匹配 location（用于内部重定向）
- `break`：停止重写，继续处理请求（用于文件查找）

```nginx
# 场景 1：需要重新匹配 location
location /old {
    rewrite ^/old/(.*)$ /new/$1 last;  # 使用 last
}
location /new {
    # 处理逻辑
}

# 场景 2：直接查找文件
location /files {
    rewrite ^/files/(.*)$ /data/$1 break;  # 使用 break
    root /data/wwwroot/nginx-proxy;  # 标准路径
}
```

---

### 10.3 反向代理问题

#### 10.3.0 502 vs 504 错误区分

在反向代理场景中，502 和 504 是最常见的错误，但它们的原因和解决方法完全不同。

**错误对比表**：

| 特性 | 502 Bad Gateway | 504 Gateway Timeout |
|------|----------------|---------------------|
| **HTTP 状态码** | 502 | 504 |
| **含义** | 网关或代理服务器从上游服务器收到无效响应 | 网关或代理服务器等待上游服务器响应超时 |
| **根本原因** | 后端服务器不可用 | 后端服务器响应时间过长 |
| **常见场景** | • 后端服务未启动<br>• 后端端口未监听<br>• 后端进程崩溃<br>• 防火墙阻止连接 | • 后端处理时间过长<br>• 数据库查询慢<br>• 网络延迟高<br>• 代理超时时间过短 |
| **网络层面** | TCP 连接失败（无法建立连接） | TCP 连接成功，但读取响应超时 |
| **发生时机** | 代理尝试连接后端时失败 | 代理等待后端响应时超时 |

**502 错误示例**：

```bash
# 场景：后端服务未启动
sudo docker compose exec nginx-backend-1 nginx -s stop

# 访问代理服务器
curl http://127.0.0.1:8060/
# 输出：
# <html>
# <head><title>502 Bad Gateway</title></head>
# <body>
# <center><h1>502 Bad Gateway</h1></center>
# <center>nginx/1.24.0</center>
# </body>
# </html>

# 错误日志：
# connect() failed (111: Connection refused) while connecting to upstream
```

**504 错误示例**：

```bash
# 场景：后端处理时间过长
# 配置后端服务器模拟慢响应
cat > /data/server/nginx/conf/conf.d/slow-backend.conf <<'EOF'
server {
    listen 80;
    location /slow {
        # 延迟 10 秒返回
        echo_sleep 10;
        echo "Slow response";
    }
}
EOF

# 配置代理服务器，设置 2 秒超时
cat > /data/server/nginx/conf/conf.d/proxy-timeout.conf <<'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://10.0.7.61;
        proxy_read_timeout 2s;  # 2 秒超时
    }
}
EOF

# 访问代理服务器
curl http://127.0.0.1:8060/slow
# 输出：
# <html>
# <head><title>504 Gateway Timeout</title></head>
# <body>
# <center><h1>504 Gateway Timeout</h1></center>
# <center>nginx/1.24.0</center>
# </body>
# </html>

# 错误日志：
# upstream timed out (110: Connection timed out) while reading response header from upstream
```

**排查步骤**：

**502 Bad Gateway 排查**：
```bash
# 1. 检查后端服务是否运行
sudo docker compose ps
ps aux | grep nginx

# 2. 检查后端端口是否监听
netstat -tlnp | grep :80
ss -tlnp | grep :80

# 3. 测试后端连通性
telnet 10.0.7.61 80
curl http://10.0.7.61/

# 4. 检查防火墙规则
iptables -L -n | grep 80

# 5. 查看 Nginx 错误日志
tail -f /data/server/nginx/logs/error.log
```

**504 Gateway Timeout 排查**：
```bash
# 1. 检查后端响应时间
time curl http://10.0.7.61/api/test

# 2. 检查代理超时配置
nginx -T | grep timeout

# 3. 增加超时时间（见下方解决方案）

# 4. 优化后端性能
# - 数据库查询优化
# - 添加缓存
# - 代码性能优化
```

**解决方案**：

**502 解决方案**：
```nginx
# 1. 启动后端服务
nginx -s start

# 2. 配置健康检查和故障转移
upstream backend {
    server 10.0.7.61 max_fails=3 fail_timeout=10s;
    server 10.0.7.62 backup;  # 备用服务器
}

# 3. 配置自动重试
location / {
    proxy_pass http://backend;
    proxy_next_upstream error timeout http_502 http_503 http_504;
}
```

**504 解决方案**：
```nginx
location / {
    proxy_pass http://backend;

    # 增加超时时间
    proxy_connect_timeout 60s;  # 连接超时（默认 60s）
    proxy_send_timeout 60s;     # 发送超时（默认 60s）
    proxy_read_timeout 60s;     # 读取超时（默认 60s）

    # 或根据业务需求设置更长时间
    # proxy_read_timeout 300s;  # 5 分钟
}
```

**⚠️ 重要提示**：
- **502 是连接问题**：后端服务器物理上不可达或服务未运行
- **504 是性能问题**：后端服务器可达但响应慢
- 优先修复 502（服务可用性问题），再优化 504（性能问题）
- 不要盲目增加超时时间，应该优化后端性能

---

#### 问题 1：后端收到错误的 Host 头

**现象**：后端服务器无法识别请求的虚拟主机。

**原因**：未设置 `proxy_set_header Host $host;`

**解决**：
```nginx
location / {
    proxy_pass http://backend;
    proxy_set_header Host $host;  # 添加此行
}
```

#### 问题 2：proxy_pass 末尾斜杠问题

**问题**：URI 重写不符合预期。

**规则**：
```nginx
# 有斜杠：替换 location 部分
location /api/ {
    proxy_pass http://backend/v1/;
    # 访问 /api/test → 后端收到 /v1/test
}

# 无斜杠：完整传递 URI
location /api/ {
    proxy_pass http://backend;
    # 访问 /api/test → 后端收到 /api/test
}
```

#### 问题 3：504 Gateway Timeout

**原因**：后端处理时间过长，超过代理超时时间。

**解决**：
```nginx
location / {
    proxy_pass http://backend;
    proxy_connect_timeout 60s;  # 连接超时
    proxy_send_timeout 60s;     # 发送超时
    proxy_read_timeout 60s;     # 读取超时
}
```

---

### 10.4 缓存问题

#### 问题 1：缓存未命中（一直 MISS）

**检查步骤**：

```bash
# 1. 检查缓存目录权限
ls -ld /tmp/nginx/cache
# 应该可写（nginx 用户）

# 2. 检查缓存配置
nginx -T | grep proxy_cache

# 3. 检查 proxy_cache_min_uses
# 默认值为 1，如果设置为 2 则需要访问 2 次才缓存

# 4. 检查后端响应头
curl -I http://backend/
# Cache-Control: no-cache → 不缓存
# 使用 proxy_ignore_headers Cache-Control;
```

#### 问题 2：缓存空间不足

**现象**：日志中出现 "cache file too large"

**解决**：
```nginx
proxy_cache_path /tmp/nginx/cache
                 max_size=2g;  # 增大缓存空间
```

#### 问题 3：POST 请求被缓存

**原因**：缓存了不应该缓存的请求方法。

**解决**：
```nginx
proxy_cache_methods GET HEAD;  # 只缓存 GET 和 HEAD
```

---

### 10.5 IP 透传问题

#### 问题 1：后端无法获取真实 IP

**检查步骤**：

```bash
# 1. 检查代理配置
nginx -T | grep X-Real-IP

# 2. 检查后端配置
sudo docker compose exec nginx-backend-1 bash
nginx -T | grep real_ip

# 3. 测试请求头
curl -H "Host: realip.test.com" http://127.0.0.1/show-ip
```

#### 问题 2：realip 模块不生效

**原因**：

1. **未信任代理 IP**：
```nginx
set_real_ip_from 10.0.7.60;  # 添加代理服务器 IP
```

2. **请求头错误**：
```nginx
real_ip_header X-Real-IP;  # 检查请求头名称
```

3. **模块未编译**：
```bash
# 检查模块是否存在
nginx -V 2>&1 | grep http_realip_module
```

---

## 📋 第十一部分：测试检查清单

### 11.1 防盗链

- [ ] **基础配置**
  - [ ] 配置 `valid_referers` 指令
  - [ ] 测试空 Referer（直接访问）
  - [ ] 测试合法 Referer
  - [ ] 测试非法 Referer（应返回 403）

- [ ] **高级配置**
  - [ ] 配置通配符域名（`*.example.com`）
  - [ ] 返回默认图片替代 403
  - [ ] 仅对特定文件类型启用防盗链

---

### 11.2 Rewrite URL 重写

- [ ] **基础 Rewrite**
  - [ ] 使用 `rewrite` 指令重写 URI
  - [ ] 理解 `last` 和 `break` 的区别
  - [ ] 理解 `redirect` 和 `permanent` 的区别

- [ ] **if 条件判断**
  - [ ] 使用 `=` 判断字符串相等
  - [ ] 使用 `~` 正则匹配
  - [ ] 使用 `-f` 判断文件存在

- [ ] **set 自定义变量**
  - [ ] 定义自定义变量
  - [ ] 在 rewrite 中使用变量
  - [ ] 使用 map 映射变量

- [ ] **URL 美化**
  - [ ] 实现 `/article/123` 重写
  - [ ] 实现多段 URL 重写

---

### 11.3 反向代理

- [ ] **基础代理**
  - [ ] 配置 `proxy_pass` 基础代理
  - [ ] 理解 `proxy_pass` 末尾斜杠规则
  - [ ] 设置 `proxy_set_header Host $host`

- [ ] **负载均衡**
  - [ ] 配置 upstream 服务器组
  - [ ] 测试轮询算法
  - [ ] 配置权重（weight）
  - [ ] 配置 IP 哈希（ip_hash）
  - [ ] 配置健康检查（max_fails, fail_timeout）

- [ ] **请求头传递**
  - [ ] 传递 Host 头
  - [ ] 传递 X-Real-IP 头
  - [ ] 传递 X-Forwarded-For 头

---

### 11.4 动静分离

- [ ] **架构设计**
  - [ ] 理解动静分离原理
  - [ ] 设计静态资源规则
  - [ ] 设计动态请求规则

- [ ] **配置实践**
  - [ ] 配置静态资源转发（正则匹配文件类型）
  - [ ] 配置动态请求转发（API 接口）
  - [ ] 验证静态资源来自静态服务器
  - [ ] 验证动态请求来自后端服务器

---

### 11.5 代理缓存

- [ ] **基础缓存**
  - [ ] 配置 `proxy_cache_path`
  - [ ] 配置 `proxy_cache` 启用缓存
  - [ ] 配置 `proxy_cache_valid` 缓存有效期
  - [ ] 测试缓存命中（HIT/MISS）

- [ ] **高级缓存**
  - [ ] 配置 `proxy_cache_key` 自定义缓存键
  - [ ] 配置 `proxy_cache_min_uses` 最小访问次数
  - [ ] 配置 `proxy_cache_bypass` 跳过缓存条件
  - [ ] 查看缓存文件

- [ ] **缓存控制**
  - [ ] 根据 Cookie 决定是否缓存
  - [ ] 根据请求参数缓存
  - [ ] 手动清除缓存

---

### 11.6 IP 透传

- [ ] **代理端配置**
  - [ ] 配置 `proxy_set_header X-Real-IP`
  - [ ] 配置 `proxy_set_header X-Forwarded-For`
  - [ ] 配置 `proxy_set_header X-Forwarded-Proto`

- [ ] **后端配置**
  - [ ] 使用 `$http_x_real_ip` 读取真实 IP
  - [ ] 配置自定义日志格式记录真实 IP
  - [ ] 使用 realip 模块修改 `$remote_addr`
  - [ ] 配置 `set_real_ip_from` 信任代理 IP

---

## ❓ 第十二部分：常见问题

### Q1: valid_referers 中 none、blocked、server_names 的区别？

**答**：

| 参数 | 说明 | 示例 |
|------|------|------|
| **none** | 允许空 Referer（直接访问） | 地址栏输入 URL |
| **blocked** | 允许被防火墙/代理移除的 Referer | 某些代理服务器 |
| **server_names** | 允许与 server_name 匹配的 Referer | 本站域名 |

**推荐配置**：
```nginx
valid_referers none blocked server_names *.mysite.com;
```

---

### Q2: rewrite 的 last 和 break 什么时候用？

**答**：

| 标志 | 行为 | 使用场景 |
|------|------|---------|
| **last** | 重新匹配 location | 需要继续走 location 匹配逻辑 |
| **break** | 停止重写，查找文件 | 重写后直接访问文件 |

**示例**：
```nginx
# 场景 1：重定向到其他 location（用 last）
location /api-old {
    rewrite ^.*$ /api-new last;
}
location /api-new {
    # 处理新 API
}

# 场景 2：重写后直接访问文件（用 break）
location /images {
    rewrite ^/images/(.*)$ /data/pics/$1 break;
    root /data/wwwroot/nginx-proxy;  # 标准路径
}
```

---

### Q3: proxy_pass 末尾有无斜杠的区别？

**答**：

| proxy_pass 配置 | URI 处理 | 示例 |
|----------------|---------|------|
| `http://backend` | 完整传递 URI | `/api/test` → `/api/test` |
| `http://backend/` | 替换 location 部分 | `/api/test` → `/test` |
| `http://backend/v1` | 替换并追加 | `/api/test` → `/v1/test` |

**示例**：
```nginx
# 场景 1：完整传递（无斜杠）
location /api/ {
    proxy_pass http://backend;
    # /api/user → 后端收到 /api/user
}

# 场景 2：替换路径（有斜杠）
location /api/ {
    proxy_pass http://backend/v2/;
    # /api/user → 后端收到 /v2/user
}
```

---

### Q4: 如何调试缓存是否命中？

**答**：

**方法 1：添加响应头**
```nginx
add_header X-Cache-Status $upstream_cache_status;
```

**方法 2：查看日志**
```nginx
log_format cache '$remote_addr - $upstream_cache_status [$time_local] '
                 '"$request" $status';
access_log /data/server/nginx/logs/cache.log cache;
```

**方法 3：查看缓存文件**
```bash
ls -lR /tmp/nginx/cache/
```

---

### Q5: 如何在后端获取客户端真实 IP？

**答**：

**方法 1：读取请求头（推荐）**
```nginx
# 代理端
proxy_set_header X-Real-IP $remote_addr;

# 后端
log_format real_ip '$http_x_real_ip ...';
```

**方法 2：使用 realip 模块**
```nginx
# 后端
set_real_ip_from 10.0.7.60;  # 信任代理 IP
real_ip_header X-Real-IP;

# 此时 $remote_addr 已是真实客户端 IP
```

---

### Q6: 动静分离后如何验证请求来自哪个服务器？

**答**：

**方法 1：查看日志**
```bash
# 静态服务器日志
sudo docker compose exec nginx-static tail -f /data/server/nginx/logs/access.log

# 后端服务器日志
sudo docker compose exec nginx-backend-1 tail -f /data/server/nginx/logs/access.log
```

**方法 2：添加响应头**
```nginx
# 静态服务器
add_header X-Served-By "Static-Server";

# 后端服务器
add_header X-Served-By "Backend-Server-1";
```

**方法 3：在代理端查看上游服务器**
```nginx
add_header X-Upstream-Addr $upstream_addr;
```

---

### Q7: 如何限制只允许代理服务器访问后端？

**答**：

```nginx
# 在后端服务器配置
server {
    listen 80;

    # 只允许代理服务器访问
    allow 10.0.7.60;
    deny all;

    location / {
        # ...
    }
}
```

---

## 🎓 第十三部分：学习总结

### 核心知识点

1. **防盗链机制**：通过检查 Referer 头保护资源
2. **Rewrite URL 重写**：正则匹配、条件判断、内部重定向
3. **反向代理**：隐藏后端、负载均衡、健康检查
4. **动静分离**：静态资源分离、性能优化
5. **代理缓存**：减少后端压力、缓存命中率优化
6. **IP 透传**：获取真实客户端 IP、多层代理处理

---

### 实战能力

通过本章学习，你应该能够：

✅ **防盗链保护**
- 配置 valid_referers 防止盗链
- 返回默认图片替代 403
- 针对特定文件类型启用防盗链

✅ **URL 重写与重定向**
- 使用 rewrite 重写 URI
- 理解 last/break/redirect/permanent 区别
- 使用 if 条件判断
- 实现 URL 美化

✅ **反向代理与负载均衡**
- 配置基础反向代理
- 配置 upstream 负载均衡
- 实现健康检查和故障转移
- 传递客户端请求头

✅ **动静分离架构**
- 设计动静分离方案
- 配置静态资源转发
- 配置动态请求负载均衡
- 验证请求转发路径

✅ **代理缓存优化**
- 配置缓存区域和缓存策略
- 实现缓存命中率优化
- 根据条件控制缓存
- 清除和管理缓存

✅ **真实 IP 透传**
- 传递 X-Real-IP 和 X-Forwarded-For
- 在后端读取真实客户端 IP
- 使用 realip 模块修改 $remote_addr
- 处理多层代理 IP 链

---

### 架构设计能力

🏗️ **设计高可用架构**
```
客户端
  ↓
代理服务器（防盗链、缓存、负载均衡）
  ├─ 静态资源服务器集群（CDN）
  └─ 后端应用服务器集群（健康检查）
      ↓
    数据库（读写分离）
```

---

## 🧹 清理环境

```bash
# 1. 停止所有容器
sudo docker compose down

# 2. 删除缓存目录
rm -rf /tmp/nginx/cache

# 3. 完全清理（包括镜像）
sudo docker compose down --volumes --rmi all
```

---

## 📖 参考资料

- **Nginx Rewrite Module**: https://nginx.org/en/docs/http/ngx_http_rewrite_module.html
- **Nginx Proxy Module**: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- **Nginx Upstream Module**: https://nginx.org/en/docs/http/ngx_http_upstream_module.html
- **Nginx RealIP Module**: https://nginx.org/en/docs/http/ngx_http_realip_module.html
- **Nginx Referer Module**: https://nginx.org/en/docs/http/ngx_http_referer_module.html

---

**完成时间**: 2025-10-12
**文档版本**: v1.0
**适用场景**: Nginx 反向代理、负载均衡、缓存优化、动静分离
**维护者**: docker-man 项目组
