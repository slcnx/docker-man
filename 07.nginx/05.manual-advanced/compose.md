# Docker Compose Nginx 高级功能实践指南

## 📚 第一部分：基础知识

### 1.1 本章内容概览

本章将深入讲解 Nginx 的高级功能，包括：

| 功能模块 | 应用场景 | 难度 |
|---------|---------|------|
| **内置变量** | 日志格式、条件判断、动态配置 | ⭐⭐ |
| **长连接** | 性能优化、减少握手开销 | ⭐⭐ |
| **文件下载** | 文件服务器、软件下载站 | ⭐⭐ |
| **文件上传** | 图片上传、资源管理 | ⭐⭐⭐ |
| **限速控制** | 带宽管理、防止滥用 | ⭐⭐⭐ |
| **请求限制** | DDoS 防护、限流保护 | ⭐⭐⭐⭐ |
| **压缩传输** | 减少带宽、提升速度 | ⭐⭐ |
| **HTTPS 配置** | 安全通信、SSL/TLS | ⭐⭐⭐⭐ |

---

## 🌐 第二部分：环境架构

### 2.1 网络拓扑

```
Docker Bridge 网络：nginx-net (10.0.7.0/24)
├── 10.0.7.1   - 网关
├── 10.0.7.50  - Ubuntu 高级功能演示（nginx-ubuntu-advanced）
│   ├── 端口：8050:80, 8443:443
│   └── 功能：长连接、限速、压缩、HTTPS
└── 10.0.7.51  - Rocky PHP 环境（nginx-rocky-php）
    ├── 端口：8051:80
    └── 功能：文件上传、PHP 处理
```

### 2.2 环境启动

```bash
# 1. 进入项目目录
cd /home/www/docker-man/07.nginx/05.manual-advanced

# 2. 启动服务
docker compose up -d

# 3. 检查服务状态
docker compose ps

# 4. 进入容器
docker compose exec -it nginx-ubuntu-advanced bash
```

---

## 📊 第三部分：内置变量实践

### 3.1 常用内置变量详解

#### 3.1.1 核心变量表

| 变量 | 说明 | 示例值 |
|------|------|--------|
| **$remote_addr** | 客户端 IP | 192.168.1.100 |
| **$remote_user** | HTTP 认证的用户名 | admin |
| **$request** | 完整的 HTTP 请求行 | GET /index.html HTTP/1.1 |
| **$request_uri** | 完整请求 URI（含参数） | /api/user?id=123 |
| **$uri** | 当前 URI（不含参数） | /api/user |
| **$args** | URL 参数 | id=123&name=tom |
| **$host** | 请求的主机头 | www.example.com |
| **$http_user_agent** | 客户端 User-Agent | Mozilla/5.0... |
| **$http_referer** | 来源页面 | http://google.com |
| **$http_cookie** | 所有 Cookie | sessionid=abc123 |
| **$cookie_NAME** | 特定 Cookie | $cookie_username |
| **$status** | 响应状态码 | 200 |
| **$body_bytes_sent** | 发送字节数 | 1024 |
| **$request_time** | 请求处理时间（秒） | 0.123 |
| **$scheme** | 协议（http/https） | http |
| **$server_name** | Server 名称 | www.example.com |
| **$server_port** | Server 端口 | 80 |
| **$document_uri** | 当前 URI（同 $uri） | /vars |
| **$proxy_add_x_forwarded_for** | X-Forwarded-For 头（追加客户端 IP） | 192.168.1.100, 10.0.7.60 |

#### 3.1.2 变量实践

```bash
# 创建测试目录
mkdir -p /data/server/nginx/web1

# 配置变量测试
cat > /data/server/nginx/conf/conf.d/vars-test.conf <<'EOF'
server {
    listen 80;
    server_name _;

    location /vars {
        default_type text/plain;
        return 200 "
=== Request Information ===
Request: $request
Request URI: $request_uri
URI: $uri
Args: $args
Request Method: $request_method

=== Client Information ===
Client IP: $remote_addr
Host: $host
User-Agent: $http_user_agent
Referer: $http_referer
All Cookies: $http_cookie
Cookie username: $cookie_username

=== Server Information ===
Server Name: $server_name
Server Port: $server_port
Scheme: $scheme

=== File Information ===
Document Root: $document_root
Request Filename: $request_filename

=== Response Information ===
Status: $status
Body Bytes Sent: $body_bytes_sent
Request Time: $request_time
";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload
```

#### 3.1.3 测试变量

```bash
# 测试 1：基本请求
curl "http://127.0.0.1/vars?id=123&name=tom"

# 测试 2：带 Cookie 请求
curl --cookie "username=admin;sessionid=abc123" \
     "http://127.0.0.1/vars?id=456"

# 测试 3：带 Referer 请求
curl -H "Referer: http://google.com/search" \
     "http://127.0.0.1/vars"

# 输出示例：
# ==> Request Information ===
# Request: GET /vars?id=123&name=tom HTTP/1.1
# Request URI: /vars?id=123&name=tom
# URI: /vars
# Args: id=123&name=tom
# ...
```

### 3.2 自定义变量

#### 3.2.1 使用 set 指令

```bash
cat > /data/server/nginx/conf/conf.d/custom-vars.conf <<'EOF'
server {
    listen 80;

    # 定义自定义变量
    set $api_version "v1";
    set $environment "production";
    set $custom_header "Custom-API-$api_version";

    location /set-test {
        # 在 location 中定义变量
        set $location_var "location value";
        set $from_builtin $host;  # 从内置变量赋值

        return 200 "
API Version: $api_version
Environment: $environment
Custom Header: $custom_header
Location Var: $location_var
From Builtin: $from_builtin
";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试
curl http://127.0.0.1/set-test
```

#### 3.2.2 条件赋值（map 指令）

```bash
# 在 http 段添加 map
cat > /data/server/nginx/conf/conf.d/map-vars.conf <<'EOF'
# 在 http 段定义 map
map $request_method $is_post {
    default 0;
    POST    1;
}

map $http_user_agent $mobile_request {
    default              0;
    "~*mobile"           1;
    "~*android"          1;
    "~*iphone"           1;
}

server {
    listen 80;

    location /map-test {
        return 200 "
Is POST: $is_post
Is Mobile: $mobile_request
User-Agent: $http_user_agent
";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试
curl http://127.0.0.1/map-test
# Is POST: 0

curl -X POST http://127.0.0.1/map-test
# Is POST: 1

curl -A "Mobile Safari/537.36" http://127.0.0.1/map-test
# Is Mobile: 1
```

---

## ⏱️ 第四部分：长连接（Keep-Alive）实践

### 4.1 长连接基础知识

#### 4.1.1 什么是长连接

**短连接流程**：
```
客户端 → TCP 握手 → 发送请求 → 接收响应 → TCP 挥手 → 结束
客户端 → TCP 握手 → 发送请求 → 接收响应 → TCP 挥手 → 结束  (重复)
```

**长连接流程**：
```
客户端 → TCP 握手 → 发送请求1 → 接收响应1
                 → 发送请求2 → 接收响应2
                 → 发送请求3 → 接收响应3
                 → TCP 挥手 → 结束
```

#### 4.1.2 长连接优势

| 优势 | 说明 |
|------|------|
| **减少握手次数** | 节省 3 次握手 + 4 次挥手的开销 |
| **降低延迟** | 后续请求无需等待连接建立 |
| **提升性能** | HTTP/1.1 默认开启 |
| **节省资源** | 减少系统调用和 CPU 消耗 |

### 4.2 配置长连接

#### 4.2.1 基本配置（双参数用法）

```bash
cat > /data/server/nginx/conf/conf.d/keepalive.conf <<'EOF'
server {
    listen 80;
    root /data/server/nginx/web1;

    # 长连接超时时间（双参数用法）
    # 第一个值：服务器端真实超时时长（60秒）
    # 第二个值：响应头中显示给客户端（30秒）
    keepalive_timeout 60s 30s;

    # 单个连接最多处理的请求数（默认 1000）
    keepalive_requests 100;

    location / {
        return 200 "Keep-Alive Test\n";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试响应头
curl -I http://127.0.0.1

# 输出：
# HTTP/1.1 200 OK
# Connection: keep-alive
# Keep-Alive: timeout=30  ← 显示第二个参数的值
```

#### 4.2.2 测试长连接

**方法 1：使用 telnet**

```bash
# 安装 telnet
apt install -y telnet

# 连接测试
telnet 127.0.0.1 80

# 输入以下内容（手动输入）：
GET / HTTP/1.1
Host: 127.0.0.1
  # 这里按两次回车

# 查看响应，注意 Connection: keep-alive

# 在同一连接中继续请求（60 秒内）：
GET / HTTP/1.1
Host: 127.0.0.1
  # 再次按两次回车

# 可以持续请求，直到超时或达到 keepalive_requests 限制
```

**方法 2：使用 curl 查看响应头**

```bash
# 查看响应头
curl -I http://127.0.0.1

# 输出：
# HTTP/1.1 200 OK
# Server: nginx/1.24.0
# Connection: keep-alive  ← 长连接已启用
# Keep-Alive: timeout=60  ← 超时时间（如果配置了第二个参数）
```

### 4.3 限制长连接请求数

```bash
cat > /data/server/nginx/conf/conf.d/keepalive-limit.conf <<'EOF'
server {
    listen 80;

    keepalive_timeout 60s;
    keepalive_requests 3;  # 限制为 3 个请求

    location / {
        return 200 "Request processed\n";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 使用 telnet 测试
telnet 127.0.0.1 80

# 发送第 1 个请求
GET / HTTP/1.1
Host: 127.0.0.1

# 响应：Connection: keep-alive

# 发送第 2 个请求
GET / HTTP/1.1
Host: 127.0.0.1

# 响应：Connection: keep-alive

# 发送第 3 个请求
GET / HTTP/1.1
Host: 127.0.0.1

# 响应：Connection: close  ← 达到限制，服务器主动关闭连接
```

### 4.4 测试请求数限制

```bash
# 配置每个连接最多 2 个请求
cat > /data/server/nginx/conf/conf.d/keepalive-limit.conf <<'EOF'
server {
    listen 80;

    keepalive_timeout 60s;
    keepalive_requests 2;  # 限制为 2 个请求

    location / {
        return 200 "Request processed\n";
    }
}
EOF

nginx -s reload

# 使用 telnet 测试
telnet 127.0.0.1 80

# 发送第 1 个请求
GET / HTTP/1.1
Host: 127.0.0.1
  # 按两次回车

# 响应：Connection: keep-alive

# 发送第 2 个请求
GET / HTTP/1.1
Host: 127.0.0.1
  # 按两次回车

# 响应：Connection: close  ← 第 2 个请求后，服务器主动关闭连接
# Connection closed by foreign host.
```

**结果说明**：
- 第 1 个请求：`Connection: keep-alive`
- 第 2 个请求：`Connection: close`（达到 `keepalive_requests` 限制）
- 第 3 个请求：连接已关闭，需要重新建立连接

---

## 📥 第五部分：文件下载服务实践

### 5.1 目录索引（autoindex）

#### 5.1.1 配置文件下载服务器

⚠️ **重要提示**：
- `autoindex` 所在 root 的目录下面，**不要存在 index.html 文件**，否则直接显示首页而不是目录列表
- 如果存在 index.html，需要先删除或重命名：`mv index.html index.html.bak`

**配置参数默认值**：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| **autoindex_exact_size** | on | on=显示字节数，off=友好格式（MB/GB） |
| **autoindex_localtime** | off | off=UTC 时区，on=本地时区 |
| **autoindex_format** | html | html / xml / json / jsonp |

```bash
# 准备测试文件（确保删除 index.html）
mv /data/server/nginx/html/index.html /data/server/nginx/html/index.html.bak  # ← 关键步骤

mkdir -p /data/download/{docs,images,videos}

echo "Document 1" > /data/download/docs/readme.txt
echo "Document 2" > /data/download/docs/manual.pdf
dd if=/dev/zero of=/data/download/videos/movie.mp4 bs=10M count=1

# 创建中文文件名测试
echo "三国演义" > /data/download/三国演义.txt

# 配置下载服务器
cat > /data/server/nginx/conf/conf.d/download.conf <<'EOF'
server {
    listen 80;
    server_name download.test.com;

    charset utf-8;  # 支持中文文件名

    location /download/ {
        alias /data/download/;

        autoindex on;                    # 开启目录索引
        autoindex_exact_size off;        # 显示友好的文件大小（MB/GB）
        autoindex_localtime on;          # 使用服务器本地时间
        autoindex_format html;           # 输出格式（html/json/xml）

        # 设置下载的 MIME 类型
        default_type application/octet-stream;

        # 限制下载速度（可选）
        limit_rate 1m;  # 限制为 1MB/s
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload
```

#### 5.1.2 测试下载服务

```bash
# 命令行测试
curl -H "Host: download.test.com" http://127.0.0.1/download/

# 输出：HTML 格式的目录列表

# 下载文件
curl -H "Host: download.test.com" \
     http://127.0.0.1/download/docs/readme.txt

# 输出：Document 1

# 下载限速测试
time curl -H "Host: download.test.com" \
     http://127.0.0.1/download/videos/movie.mp4 > /dev/null
# 应该需要约 10 秒（10MB ÷ 1MB/s）
```

### 5.2 JSON 格式输出

```bash
cat > /data/server/nginx/conf/conf.d/download-json.conf <<'EOF'
server {
    listen 80;

    location /api/files/ {
        alias /data/download/;

        autoindex on;
        autoindex_format json;  # JSON 格式输出

        # 添加 CORS 头
        add_header Access-Control-Allow-Origin "*";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试 JSON 输出
curl http://127.0.0.1/api/files/ | jq .

# 输出：
# [
#   {
#     "name": "docs",
#     "type": "directory",
#     "mtime": "2025-10-12T10:30:00Z"
#   },
#   {
#     "name": "测试文件.txt",
#     "type": "file",
#     "mtime": "2025-10-12T10:35:00Z",
#     "size": 15
#   }
# ]
```

---

## 📤 第六部分：文件上传实践（需 PHP 环境）

### 6.1 环境准备

```bash
# 切换到 Rocky PHP 容器
docker compose exec -it nginx-rocky-php bash

# 安装 PHP-FPM
yum install -y php php-fpm php-cli

# 启动 PHP-FPM
php-fpm
```

### 6.2 配置 Nginx + PHP-FPM

**上传配置参数详解**：

| 参数 | 默认值 | 说明 | 超出限制的影响 |
|------|--------|------|----------------|
| **client_max_body_size** | **1m** | 单个文件最大值 | 超过返回 **413** |
| **client_body_buffer_size** | **16k** | 缓冲区大小 | 超过时写入临时文件 |
| **client_body_temp_path** | - | 临时文件路径 | 支持三级目录结构 |

**三级目录结构说明**：
```nginx
client_body_temp_path /tmp/nginx_upload 1 2 3;
#                                        ↑ ↑ ↑
#                                     level1 level2 level3
# 数字表示当前级别创建几个子目录（16进制）
```

```bash
cat > /data/server/nginx/conf/conf.d/upload.conf <<'EOF'
server {
    listen 80;
    root /data/server/nginx/html;
    index index.php index.html;

    # PHP 处理
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }

    # 文件上传配置
    client_max_body_size 50m;           # 最大上传 50MB
    client_body_buffer_size 1m;         # 缓冲区 1MB
    client_body_temp_path /tmp/nginx_upload 1 2;  # 临时文件路径（三级目录）
}
EOF

# 创建临时目录
mkdir -p /tmp/nginx_upload
chown -R nginx:nginx /tmp/nginx_upload

# 重载 Nginx 配置
nginx -s reload
```

### 6.3 创建上传表单

```bash
# 创建上传目录
mkdir -p /data/server/nginx/html/uploads
chmod 755 /data/server/nginx/html/uploads

# 创建 HTML 上传表单
cat > /data/server/nginx/html/upload.html <<'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>文件上传</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 600px;
            margin: 50px auto;
            padding: 20px;
        }
        .upload-form {
            border: 2px solid #ccc;
            border-radius: 5px;
            padding: 30px;
        }
        input[type="file"] {
            margin: 20px 0;
        }
        button {
            background-color: #4CAF50;
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
        }
        button:hover {
            background-color: #45a049;
        }
    </style>
</head>
<body>
    <h1>文件上传系统</h1>
    <div class="upload-form">
        <form action="upload.php" method="post" enctype="multipart/form-data">
            <label for="file">选择文件：</label><br>
            <input type="file" name="file" id="file" required><br>
            <button type="submit">上传文件</button>
        </form>
    </div>
</body>
</html>
EOF
```

### 6.4 创建 PHP 上传处理脚本

```bash
cat > /data/server/nginx/html/upload.php <<'EOF'
<?php
$target_dir = "uploads/";
$max_size = 50 * 1024 * 1024;  // 50MB

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    // 检查文件是否上传
    if (!isset($_FILES['file']) || $_FILES['file']['error'] != 0) {
        die("上传失败：错误代码 " . $_FILES['file']['error']);
    }

    // 检查文件大小
    if ($_FILES['file']['size'] > $max_size) {
        die("文件太大，最大允许 50MB");
    }

    // 获取文件信息
    $file_name = basename($_FILES['file']['name']);
    $target_file = $target_dir . $file_name;
    $file_type = strtolower(pathinfo($target_file, PATHINFO_EXTENSION));

    // 检查文件是否已存在
    if (file_exists($target_file)) {
        die("文件已存在：$file_name");
    }

    // 允许的文件类型
    $allowed_types = array('jpg', 'jpeg', 'png', 'gif', 'pdf', 'txt', 'doc', 'docx');
    if (!in_array($file_type, $allowed_types)) {
        die("不允许的文件类型：$file_type");
    }

    // 移动上传的文件
    if (move_uploaded_file($_FILES['file']['tmp_name'], $target_file)) {
        echo "<h2>上传成功！</h2>";
        echo "<p>文件名：$file_name</p>";
        echo "<p>大小：" . ($_FILES['file']['size'] / 1024) . " KB</p>";
        echo "<p>类型：$file_type</p>";
        echo "<p><a href='upload.html'>继续上传</a></p>";
    } else {
        echo "上传失败！";
    }
} else {
    header("Location: upload.html");
}
?>
EOF
```

### 6.5 测试上传

```bash
# 在容器内测试
echo "Test file content" > /tmp/test.txt

curl -F "file=@/tmp/test.txt" http://127.0.0.1/upload.php

# 输出：
# <h2>上传成功！</h2>
# <p>文件名：test.txt</p>
# ...

# 验证文件
ls -lh /data/server/nginx/html/uploads/
```

### 6.6 缓冲区测试

**测试缓冲区大小对临时文件的影响**：

```bash
# 场景 1：缓冲区过大（1024k），临时文件不会生成
sed -i 's/client_body_buffer_size.*/client_body_buffer_size 1024k;/' \
    /data/server/nginx/conf/conf.d/upload.conf

nginx -s reload

# 上传小文件（< 1024k）
echo "Small file" > /tmp/small.txt
curl -F "file=@/tmp/small.txt" http://127.0.0.1/upload.php

# 检查临时目录（空的）
tree /tmp/nginx_upload/
# 0 directories, 0 files

# 场景 2：缓冲区较小（2k），临时文件会生成
sed -i 's/client_body_buffer_size.*/client_body_buffer_size 2k;/' \
    /data/server/nginx/conf/conf.d/upload.conf

nginx -s reload

# 上传稍大文件（> 2k）
head -c 10k /dev/urandom > /tmp/large.bin
curl -F "file=@/tmp/large.bin" http://127.0.0.1/upload.php

# 检查临时目录（有文件）
tree /tmp/nginx_upload/
# /tmp/nginx_upload/
# └── 1
#     └── 00
#         └── 0000000001  ← 临时文件（三级目录结构）
```

**结论**：
- 当上传文件大小 **< client_body_buffer_size** 时，不生成临时文件
- 当上传文件大小 **> client_body_buffer_size** 时，生成临时文件

---

## 🚦 第七部分：限速与请求限制

### 7.1 下载限速（limit_rate）

⚠️ **重要特性**：
- `limit_rate` 限速只对**单一连接**而言
- **同一客户端两个连接，总速率为限速的 2 倍**
- `limit_rate_after` 默认值为 **0**（表示一开始就限速）

**示例说明**：
```nginx
limit_rate 100k;  # 单个连接限速 100KB/s

# 如果客户端同时开启 2 个连接下载：
# - 每个连接：100KB/s
# - 总速率：200KB/s
```

#### 7.1.1 基本限速

```bash
# 准备测试文件
dd if=/dev/zero of=/data/download/100M.bin bs=100M count=1

cat > /data/server/nginx/conf/conf.d/limit-rate.conf <<'EOF'
server {
    listen 80;

    location /slow/ {
        alias /data/download/;

        # 限制下载速度为 100KB/s
        limit_rate 100k;
    }

    location /fast/ {
        alias /data/download/;

        # 不限速
        limit_rate 0;
    }

    location /adaptive/ {
        alias /data/download/;

        # 前 10MB 不限速，之后限制为 500KB/s
        limit_rate_after 10m;
        limit_rate 500k;
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试慢速下载
time curl http://127.0.0.1/slow/100M.bin > /dev/null
# 应该需要约 1000 秒（100MB ÷ 100KB/s）

# 测试快速下载
time curl http://127.0.0.1/fast/100M.bin > /dev/null
# 应该很快完成

# 测试自适应限速
time curl http://127.0.0.1/adaptive/100M.bin > /dev/null
# 前 10MB 快速，后 90MB 慢速
```

### 7.2 并发连接数限制（limit_conn）

#### 7.2.1 配置连接限制

```bash
# 在 http 段定义限制区域（编辑 nginx.conf）
cat > /data/server/nginx/conf/conf.d/limit-conn-zone.conf <<'EOF'
# 定义限制区域（基于 IP）
limit_conn_zone $binary_remote_addr zone=conn_per_ip:10m;

# 定义限制区域（基于 server）
limit_conn_zone $server_name zone=conn_per_server:10m;
EOF

cat > /data/server/nginx/conf/conf.d/limit-conn.conf <<'EOF'
server {
    listen 80;

    location /download/ {
        alias /data/download/;

        # 限制每个 IP 最多 2 个并发连接
        limit_conn conn_per_ip 2;

        # 限制整个 server 最多 100 个并发连接
        limit_conn conn_per_server 100;

        # 连接数超过时返回的状态码
        limit_conn_status 503;
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload
```

#### 7.2.2 测试连接限制

```bash
# 准备大文件
dd if=/dev/zero of=/data/download/200M.bin bs=200M count=1

# 启动 3 个并发下载（在后台）
wget http://127.0.0.1/download/200M.bin -O /tmp/file1 &
wget http://127.0.0.1/download/200M.bin -O /tmp/file2 &
wget http://127.0.0.1/download/200M.bin -O /tmp/file3 &

# 查看进程
ps aux | grep wget

# 第 3 个下载会收到 503 错误
# HTTP request sent, awaiting response... 503 Service Unavailable
```

### 7.3 请求频率限制（limit_req）

#### 7.3.1 基本配置说明

**重要概念**：
- `rate=2r/s` 表示每秒 2 个请求
- 由于 Nginx 是**毫秒级**控制粒度，`2r/s` 实际意味着**每 500ms 只能处理 1 个请求**
- 超出限制的请求默认返回 **503**（可通过 `limit_req_status` 修改）

| 配置参数 | 说明 | 示例值 |
|---------|------|--------|
| **zone** | 共享内存区域名称 | req_per_ip |
| **size** | 内存大小 | 10m |
| **rate** | 限制速率 | 2r/s（每 500ms 一个请求） |
| **burst** | 允许突发请求数（排队） | burst=3（允许 3 个排队） |
| **nodelay** | 立即处理不排队 | 超出直接返回 503 |

#### 7.3.2 基本请求限制

**配置解析详解**：

| 配置项 | 说明 | 关键点 |
|--------|------|--------|
| **rate=2r/s** | 每秒 2 个请求 | **实际是每 500ms 处理 1 个请求**（毫秒级粒度） |
| **10r/s** | 每秒 10 个请求 | **实际是每 100ms 处理 1 个请求** |
| **完整写法** | `10requests/seconds` | 简写为 `10r/s` |
| **Nginx 粒度** | 毫秒级控制 | 对同一客户端在 100ms 只能处理一个请求 |

```bash
# 在 http 段定义限制区域
cat > /data/server/nginx/conf/conf.d/limit-req-zone.conf <<'EOF'
# 限制每秒请求数（rate limiting）
# rate=2r/s 表示每 500ms 只能处理 1 个请求
limit_req_zone $binary_remote_addr zone=req_per_ip:10m rate=2r/s;
EOF

cat > /data/server/nginx/conf/conf.d/limit-req.conf <<'EOF'
server {
    listen 80;

    location /api/ {
        # 调用限制规则
        limit_req zone=req_per_ip;

        # 超过限制时返回的状态码（默认 503）
        limit_req_status 503;

        return 200 "API Request Success\n";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试 1：间隔 400ms 发送 2 个请求（失败）
for i in {1..2}; do
    curl http://127.0.0.1/api/
    sleep 0.4
done

# 输出：
# API Request Success      (第 1 个成功)
# 503 Service Temporarily Unavailable  (第 2 个失败，因为只过了 400ms)

# 测试 2：间隔 500ms 发送 2 个请求（成功）
for i in {1..2}; do
    curl http://127.0.0.1/api/
    sleep 0.5
done

# 输出：
# API Request Success      (第 1 个成功)
# API Request Success      (第 2 个成功，因为过了 500ms)
```

#### 7.3.3 带突发队列的限制（burst）

**配置说明**：
- `burst=3`：允许突发 3 个额外请求放入队列
- **不带 nodelay**：队列中的请求会延迟处理（每 500ms 处理 1 个）
- **示例**：5 个并发请求 → 第 1 个立即处理，第 2-4 个排队，第 5 个返回 503

**burst 延迟处理详细解析**：

假设配置：`rate=2r/s, burst=3`

**接收 5 个并发请求时的处理流程**：
1. **第 1 个请求**：立即处理（正常配额）
2. **第 2-4 个请求**：放入队列，每 500ms 处理一个（burst 配额）
3. **第 5 个请求**：直接返回 503（超出限制）

**时间轴示例**：
```
0ms    → 第1个请求立即处理
500ms  → 第2个请求处理（队列中）
1000ms → 第3个请求处理（队列中）
1500ms → 第4个请求处理（队列中）
同时   → 第5个请求返回503
```

```bash
cat > /data/server/nginx/conf/conf.d/limit-req-burst.conf <<'EOF'
server {
    listen 80;

    location /api/burst/ {
        # burst=3: 允许突发 3 个请求排队（不带 nodelay，会延迟处理）
        limit_req zone=req_per_ip burst=3;

        return 200 "Burst API Success\n";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试：并发发送 5 个请求
for i in {1..5}; do
    curl http://127.0.0.1/api/burst/ &
done
wait

# 输出（逐个延迟返回）：
# Burst API Success  (第 1 个立即处理)
# Burst API Success  (第 2 个延迟 500ms)
# Burst API Success  (第 3 个延迟 1000ms)
# Burst API Success  (第 4 个延迟 1500ms)
# 503 Service Temporarily Unavailable  (第 5 个直接拒绝)
```

**日志分析示例**：
```bash
# 查看日志（注意时间戳变化）
tail -n 5 /data/server/nginx/logs/access.log

# 输出：
# 10.0.7.50 [12/Oct/2025:11:30:09 +0800] "GET / HTTP/1.1" 200 11
# 10.0.7.50 [12/Oct/2025:11:30:09 +0800] "GET / HTTP/1.1" 503 197  ← 拒绝
# 10.0.7.50 [12/Oct/2025:11:30:09 +0800] "GET / HTTP/1.1" 200 11   ← 延迟
# 10.0.7.50 [12/Oct/2025:11:30:10 +0800] "GET / HTTP/1.1" 200 11   ← 延迟（注意秒数变化）
# 10.0.7.50 [12/Oct/2025:11:30:10 +0800] "GET / HTTP/1.1" 200 11   ← 延迟
```

#### 7.3.4 无延迟突发限制（burst + nodelay）

**配置说明**：
- `burst=3 nodelay`：允许突发 3 个额外请求，**立即处理**不排队
- **示例**：5 个并发请求 → 前 4 个立即处理（1 个正常 + 3 个突发），第 5 个返回 503

**nodelay 原理详解**：

- `nodelay` 表示**无延时队列**
- **排在队列越后面的请求等待时间越久**
- 如果请求数过多，可能会等到**超时**也不会被处理
- **与不带 nodelay 的区别**：
  - 不带 nodelay：请求会延迟返回（每 500ms 处理一个）
  - 带 nodelay：前 N 个立即返回，超出的立即返回 503

```bash
cat > /data/server/nginx/conf/conf.d/limit-req-nodelay.conf <<'EOF'
server {
    listen 80;

    location /api/nodelay/ {
        # burst=3 nodelay: 允许突发 3 个请求立即处理（不延迟）
        limit_req zone=req_per_ip burst=3 nodelay;

        return 200 "Nodelay API Success\n";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试：在 500ms 内并发发送 5 个请求
for i in {1..5}; do
    curl http://127.0.0.1/api/nodelay/
    sleep 0.1
done

# 输出（前 4 个立即返回）：
# Nodelay API Success  (第 1 个：正常配额)
# Nodelay API Success  (第 2 个：突发配额 1)
# Nodelay API Success  (第 3 个：突发配额 2)
# Nodelay API Success  (第 4 个：突发配额 3)
# 503 Service Temporarily Unavailable  (第 5 个：超出限制)
```

**并发测试脚本**：
```bash
cat > /tmp/test_limit_req.sh <<'EOF'
#!/bin/bash
# 并发请求测试
for i in {1..5}; do
    curl http://127.0.0.1/api/nodelay/ &
done
wait
EOF

chmod +x /tmp/test_limit_req.sh
/tmp/test_limit_req.sh
```

---

## 🎨 第七点五部分：favicon.ico 配置

### 7.5.1 问题说明

**为什么 favicon.ico 总是 404？**

当客户端使用浏览器访问页面时，浏览器会**自动发起请求**获取页面的 `favicon.ico` 文件（网站图标）。

当请求的 favicon.ico 文件不存在时：
- 服务器会记录 **404 日志**
- 浏览器也会显示 **404 报错**（开发者工具中显示红色）

```bash
# 查看日志
tail /data/server/nginx/logs/access.log | grep favicon

# 输出：
# 10.0.7.50 - - [12/Oct/2025:12:09:05 +0800] "GET /favicon.ico HTTP/1.1" 404 187
```

### 7.5.2 解决方案 1：不记录日志

```bash
cat > /data/server/nginx/conf/conf.d/favicon.conf <<'EOF'
server {
    listen 80;
    root /data/server/nginx/web1;

    # 方案 1：不记录 favicon.ico 的访问日志和错误日志
    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试：浏览器刷新页面（Ctrl + F5）
# 查看日志（不再记录 favicon.ico 的 404）
tail /data/server/nginx/logs/access.log | grep favicon
# 无输出
```

**优点**：配置简单
**缺点**：浏览器开发者工具中仍然显示 404（红色）

### 7.5.3 解决方案 2：添加真实的 favicon.ico 文件

```bash
# 准备目录
mkdir -p /data/server/nginx/html/static

# 下载一个 favicon.ico 文件
wget https://www.logosc.cn/uploads/output/2021/10/19/aaabb9adc7fad4ed3268b7e5ce05ba37.jpg \
     -O /data/server/nginx/html/static/favicon.ico

# 配置
cat > /data/server/nginx/conf/conf.d/favicon.conf <<'EOF'
server {
    listen 80;
    root /data/server/nginx/html;

    location = /favicon.ico {
        alias /data/server/nginx/html/static/favicon.ico;
        access_log off;
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload

# 测试：浏览器刷新页面
# 浏览器开发者工具中显示 200（绿色）
```

**优点**：彻底解决问题，浏览器正常显示图标
**缺点**：需要准备 favicon.ico 文件

---

## 🗜️ 第八部分：Gzip 压缩实践

### 8.1 配置 Gzip 压缩

```bash
# 准备测试文件
head -c 500K /dev/urandom > /data/server/nginx/web1/large.txt

cat > /data/server/nginx/conf/conf.d/gzip.conf <<'EOF'
server {
    listen 80;
    root /data/server/nginx/web1;

    # 启用 Gzip 压缩
    gzip on;

    # 压缩级别（1-9，9 最高压缩率但最耗 CPU）
    gzip_comp_level 6;

    # 压缩的最小文件大小
    gzip_min_length 1k;

    # 压缩的文件类型
    gzip_types text/plain text/css text/javascript
               application/json application/javascript application/x-javascript
               application/xml text/xml
               application/x-httpd-php
               image/gif image/png;

    # 对代理请求也压缩（any: 任何情况都压缩）
    # 其他选项：
    # - no_etag: 如果请求头中不包含 ETag 则压缩
    # - auth: 如果请求头中包含 Authorization 则压缩
    # - any: 任何情况都压缩（推荐）
    gzip_proxied any;

    # 添加 Vary 响应头
    gzip_vary on;

    location /no-gzip/ {
        alias /data/server/nginx/web1/;
        gzip off;  # 禁用压缩
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload
```

### 8.2 测试压缩效果

```bash
# 测试 1：查看未压缩的大小
curl -I http://127.0.0.1/large.txt

# 输出：
# Content-Length: 524288  (未压缩大小)

# 测试 2：请求压缩内容
curl -H "Accept-Encoding: gzip" -I http://127.0.0.1/large.txt

# 输出：
# Content-Encoding: gzip  (已压缩)
# Vary: Accept-Encoding
# (注意：没有 Content-Length，因为压缩后大小动态变化)

# 测试 3：使用 curl --compressed 自动解压
curl --compressed http://127.0.0.1/large.txt > /tmp/decompressed.txt

# 测试 4：对比压缩率
curl http://127.0.0.1/large.txt | wc -c          # 未压缩
curl -H "Accept-Encoding: gzip" \
     http://127.0.0.1/large.txt | wc -c          # 已压缩

# 压缩率通常能达到 70-90%
```

**为什么压缩后看不到 Content-Length？**

启用压缩后，传输的内容要进行压缩，大小会改变。但是：
1. HTTP 响应头（header）**先于** 响应体（body）传输
2. header 在传输前**并不知道** body 会被压成多大
3. 所以无法在 header 中给出 Content-Length

**解决方法**：
- 使用 `ngx_http_gzip_static_module` 模块（预压缩）
- 或者在浏览器开发者工具中查看实际大小

---

## 🔐 第九部分：HTTPS 配置实践

### 9.1 生成自签名证书

```bash
# 创建证书目录
mkdir -p /data/server/nginx/ssl
cd /data/server/nginx/ssl

# 生成私钥和证书（一步完成）
openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout server.key \
    -out server.crt \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Example/OU=IT/CN=example.com"

# 设置权限
chmod 600 server.key
chmod 644 server.crt

# 查看证书信息
openssl x509 -in server.crt -text -noout | head -20
```

### 9.1.5 SSL 会话缓存原理

**为什么需要 SSL 会话缓存？**

SSL/TLS 握手过程非常耗时（涉及多次网络往返和加密计算），会话缓存可以**重用**握手数据，避免重复握手。

**会话缓存存储的数据**：

| 数据项 | 说明 |
|--------|------|
| **会话标识符**（Session Identifier） | 唯一标识一个 SSL/TLS 会话 |
| **主密钥**（Master Secret） | 用于生成加密密钥 |
| **加密算法和参数** | 协商的密码套件 |

**工作原理**：
1. 客户端首次连接时，完整执行 SSL/TLS 握手，生成会话数据
2. 服务器将会话数据存储在缓存中（会话标识符作为 key）
3. 客户端再次连接时，提供之前的会话标识符
4. 服务器从缓存中查找会话数据，**直接重用**，跳过握手

**性能提升**：
- 减少 **80% 的握手时间**
- 降低 CPU 计算负担
- 提高并发处理能力

**配置示例**：
```nginx
# SSL 会话缓存（10MB 内存，可存储约 40000 个会话）
ssl_session_cache shared:SSL:10m;

# 会话缓存超时时间（默认 5m）
ssl_session_timeout 10m;
```

### 9.2 配置 HTTPS

```bash
cat > /data/server/nginx/conf/conf.d/https.conf <<'EOF'
# HTTP 服务器（重定向到 HTTPS）
server {
    listen 80;
    server_name secure.example.com;

    # 重定向所有 HTTP 请求到 HTTPS
    return 301 https://$server_name$request_uri;
}

# HTTPS 服务器
server {
    listen 443 ssl;
    server_name secure.example.com;
    root /data/server/nginx/web1;

    # SSL 证书配置
    ssl_certificate /data/server/nginx/ssl/server.crt;
    ssl_certificate_key /data/server/nginx/ssl/server.key;

    # SSL 协议和加密套件
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # SSL 会话缓存
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    location / {
        index index.html;
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload
```

### 9.3 测试 HTTPS

```bash
# 测试 1：HTTP 重定向
curl -I http://127.0.0.1

# 输出：
# HTTP/1.1 301 Moved Permanently
# Location: https://secure.example.com/

# 测试 2：HTTPS 访问（跳过证书验证）
curl -k https://127.0.0.1

# 测试 3：查看 SSL 证书信息
openssl s_client -connect 127.0.0.1:443 -showcerts

# 测试 4：使用 curl 显示详细信息
curl -vk https://127.0.0.1 2>&1 | grep -i ssl

# 输出：
# SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
```

---

## 📋 第十部分：综合实践案例

### 10.1 高性能文件下载站

```bash
cat > /data/server/nginx/conf/conf.d/download-site.conf <<'EOF'
# 下载限制区域
limit_conn_zone $binary_remote_addr zone=download_conn:10m;
limit_req_zone $binary_remote_addr zone=download_req:10m rate=10r/s;

server {
    listen 80;
    server_name download.example.com;
    charset utf-8;

    # 访问日志
    access_log /data/server/nginx/logs/download_access.log;

    location /files/ {
        alias /data/download/;

        # 目录索引
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        # 连接限制：每个 IP 最多 3 个并发下载
        limit_conn download_conn 3;

        # 请求频率限制：每秒最多 10 个请求
        limit_req zone=download_req burst=20 nodelay;

        # 下载限速：500KB/s（前 5MB 不限速）
        limit_rate_after 5m;
        limit_rate 500k;

        # Gzip 压缩
        gzip on;
        gzip_comp_level 5;
        gzip_types text/plain text/css application/json;

        # 缓存控制
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # 健康检查端点
    location /health {
        access_log off;
        return 200 "OK\n";
    }
}
EOF

# 重载 Nginx 配置
nginx -s reload
```

---

## 🔧 第十一部分：故障排除

### 11.1 长连接问题

**问题**：长连接不生效

```bash
# 检查配置
nginx -T | grep keepalive

# 检查响应头
curl -I http://127.0.0.1

# 如果看到 Connection: close，检查：
# 1. HTTP/1.0 客户端不支持长连接
# 2. keepalive_timeout 设置为 0
# 3. keepalive_requests 达到上限
```

### 11.2 限速问题

**问题**：limit_req 返回 503 而非 429

```bash
# 检查是否设置了 limit_req_status
grep limit_req_status /data/server/nginx/conf/conf.d/*.conf

# 添加配置
limit_req_status 429;  # 自定义状态码
```

### 11.3 压缩问题

**问题**：Gzip 压缩不生效

```bash
# 检查模块是否安装
nginx -V 2>&1 | grep http_gzip

# 检查配置
nginx -T | grep gzip

# 常见原因：
# 1. 文件类型不在 gzip_types 中
# 2. 文件小于 gzip_min_length
# 3. 客户端未发送 Accept-Encoding: gzip
```

---

## 📋 第十二部分：测试检查清单

- [ ] **内置变量**
  - [ ] 理解常用变量含义
  - [ ] 使用 set 自定义变量
  - [ ] 使用 map 条件赋值

- [ ] **长连接**
  - [ ] 配置 keepalive_timeout
  - [ ] 配置 keepalive_requests
  - [ ] 使用 telnet 测试长连接

- [ ] **文件下载**
  - [ ] 配置 autoindex 目录索引
  - [ ] 测试 JSON 格式输出
  - [ ] 配置下载限速

- [ ] **限速与限制**
  - [ ] 配置 limit_rate 下载限速
  - [ ] 配置 limit_conn 连接限制
  - [ ] 配置 limit_req 请求频率限制
  - [ ] 测试 burst 突发队列

- [ ] **压缩**
  - [ ] 配置 Gzip 压缩
  - [ ] 测试压缩率
  - [ ] 验证响应头

- [ ] **HTTPS**
  - [ ] 生成自签名证书
  - [ ] 配置 SSL
  - [ ] 测试 HTTPS 访问

---

## 🎓 第十三部分：学习总结

### 核心知识点

1. **Nginx 变量系统**：内置变量、自定义变量、map 映射
2. **性能优化**：长连接、Gzip 压缩、缓存控制
3. **流量控制**：下载限速、连接限制、请求频率限制
4. **安全加固**：HTTPS 配置、SSL/TLS 优化、请求限制
5. **文件服务**：目录索引、下载服务、上传处理

### 实战能力

✅ 理解并应用 Nginx 内置变量
✅ 配置长连接提升性能
✅ 搭建文件下载服务器
✅ 实现文件上传功能（PHP）
✅ 配置多层次限速与限流
✅ 启用 Gzip 压缩减少带宽
✅ 部署 HTTPS 加密通信
✅ 排查常见配置问题

---

## 🧹 清理环境

```bash
docker compose down
docker compose down --volumes
docker compose down --volumes --rmi all
```

---

## 📖 参考资料

- **Nginx Variables**: https://nginx.org/en/docs/varindex.html
- **Limit Req Module**: https://nginx.org/en/docs/http/ngx_http_limit_req_module.html
- **Gzip Module**: https://nginx.org/en/docs/http/ngx_http_gzip_module.html
- **SSL Module**: https://nginx.org/en/docs/http/ngx_http_ssl_module.html

---

**完成时间**: 2025-10-12
**文档版本**: v1.0
**适用场景**: Nginx 高级功能、性能优化、流量控制
