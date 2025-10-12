# Docker Compose Nginx 虚拟主机与配置实践指南

## 📚 第一部分：基础知识

### 1.1 什么是 Nginx 虚拟主机

Nginx 虚拟主机（Virtual Host）是一种在**单台物理服务器上运行多个网站**的技术。

#### 1.1.1 虚拟主机的优势

| 优势 | 说明 | 应用场景 |
|------|------|---------|
| **资源节约** | 一台服务器托管多个站点 | 中小型网站集群 |
| **灵活管理** | 每个站点独立配置 | 多租户 SaaS 平台 |
| **成本降低** | 减少硬件和运维成本 | 创业公司、个人开发者 |
| **易于扩展** | 按需添加新站点 | 快速业务迭代 |

#### 1.1.2 虚拟主机的类型

| 类型 | 匹配方式 | 优势 | 劣势 | 推荐场景 |
|------|---------|------|------|---------|
| **基于域名** | server_name | 最常用，易管理 | 需要 DNS 解析 | 生产环境（推荐） |
| **基于端口** | listen 端口 | 无需域名 | 用户需记端口号 | 内部测试环境 |
| **基于 IP** | listen IP | 隔离性强 | 需要多个 IP | 高安全要求场景 |

---

### 1.2 Server 与 Location 配置层级

#### 1.2.1 配置结构图

```
http {                           ← HTTP 全局配置
    ├─ log_format                ← 日志格式定义
    ├─ gzip on;                  ← 全局压缩设置
    │
    ├─ server {                  ← 虚拟主机 1（www.a.com）
    │   ├─ listen 80;            ← 监听端口
    │   ├─ server_name www.a.com;← 域名
    │   ├─ root /data/server/nginx/html/a;      ← 根目录
    │   │
    │   ├─ location / {          ← URL 匹配规则 1
    │   │   index index.html;
    │   │ }
    │   │
    │   └─ location /api/ {      ← URL 匹配规则 2
    │       proxy_pass http://backend;
    │     }
    │ }
    │
    └─ server {                  ← 虚拟主机 2（www.b.com）
        ├─ listen 80;
        ├─ server_name www.b.com;
        └─ root /data/server/nginx/html/b;
      }
}
```

#### 1.2.2 请求匹配流程

```
客户端请求：http://www.a.com/api/users

↓ 第一步：匹配 Server
根据 Host 头和 listen 端口匹配到对应的 server 块

↓ 第二步：匹配 Location
在匹配到的 server 块中，根据 URI 匹配 location 规则

↓ 第三步：处理请求
执行 location 块中的指令（proxy_pass / root / return 等）
```

---

### 1.3 Location 匹配规则详解

#### 1.3.1 匹配符号优先级

| 匹配符 | 说明 | 正则 | 大小写 | 优先级 |
|--------|------|------|--------|--------|
| `=` | 精确匹配 | 否 | 区分 | ⭐⭐⭐⭐⭐ (最高) |
| `^~` | 前缀匹配（优先） | 否 | 区分 | ⭐⭐⭐⭐ |
| `~` | 正则匹配 | 是 | 区分 | ⭐⭐⭐ |
| `~*` | 正则匹配 | 是 | 不区分 | ⭐⭐⭐ |
| 无符号 | 前缀匹配 | 否 | 区分 | ⭐⭐ (最低) |

#### 1.3.2 匹配流程图

```
请求 URI: /images/photo.jpg

↓ 第一步：检查精确匹配（=）
  location = /images/photo.jpg  → 如果匹配，立即返回 ✅

↓ 第二步：检查优先前缀匹配（^~）
  location ^~ /images/          → 如果匹配，立即返回 ✅

↓ 第三步：检查正则匹配（~ 和 ~*）
  location ~ \.(jpg|png)$       → 按顺序匹配，找到第一个即返回 ✅

↓ 第四步：使用最长前缀匹配（无符号）
  location /images/             → 选择匹配长度最长的 ✅
  location /                    → 兜底匹配
```

---

### 1.4 Root vs Alias 深度解析

#### 1.4.1 核心区别

| 指令 | 路径处理 | location 路径 | 适用场景 |
|------|---------|---------------|---------|
| **root** | 拼接 location | 包含在最终路径中 | 标准目录结构 |
| **alias** | 替换 location | 不包含在最终路径中 | 路径别名、重映射 |

#### 1.4.2 示例对比

**场景 1：访问 `http://example.com/images/logo.png`**

```nginx
# 使用 root
location /images/ {
    root /data/server/nginx/html;
}
# 实际访问路径：/data/server/nginx/html/images/logo.png
#                      ↑ root      ↑ location + 文件名
```

```nginx
# 使用 alias
location /images/ {
    alias /data/server/nginx/pictures/;
}
# 实际访问路径：/data/server/nginx/pictures/logo.png
#                      ↑ alias    ↑ 文件名（location 被替换）
```

**关键点**：
- root：`最终路径 = root值 + location路径 + 文件名`
- alias：`最终路径 = alias值 + 文件名`（location 路径被忽略）

#### 1.4.3 常见错误

```nginx
# ❌ 错误 1：alias 忘记加结尾斜杠
location /images/ {
    alias /data/server/nginx/pictures;  # 缺少斜杠
}
# 访问 /images/logo.png 变成 /data/server/nginx/pictureslogo.png（拼接错误）

# ✅ 正确写法
location /images/ {
    alias /data/server/nginx/pictures/;  # 结尾必须有斜杠
}

# ❌ 错误 2：正则匹配中使用 alias
location ~ ^/images/ {
    alias /data/server/nginx/pictures/;  # 不支持正则
}

# ✅ 正确写法：正则匹配只能用 root
location ~ ^/images/ {
    root /data/server/nginx/html;
}
```

---

## 🌐 第二部分：环境架构

### 2.1 网络拓扑

```
Docker Bridge 网络：nginx-net (10.0.7.0/24)
├── 10.0.7.1   - 网关（Docker 网桥）
├── 10.0.7.40  - Ubuntu 虚拟主机演示（nginx-ubuntu-vhost）
│   ├── 端口：8040:80, 8041:81, 8042:82
│   └── 用途：基于端口、域名的虚拟主机
└── 10.0.7.41  - Rocky 虚拟主机演示（nginx-rocky-vhost）
    ├── 端口：8043:80
    └── 用途：访问控制、日志管理、状态监控
```

### 2.2 Docker Compose 配置说明

本环境包含两个容器：
- **nginx-ubuntu-vhost**：演示多端口、多域名虚拟主机
- **nginx-rocky-vhost**：演示访问控制、身份认证、日志管理

---

## 🚀 第三部分：虚拟主机配置实践

### 3.1 环境启动

```bash
# 1. 进入项目目录
cd /home/www/docker-man/07.nginx/04.manual-vhost

# 2. 启动服务
docker compose up -d

# 3. 检查服务状态
docker compose ps

# 4. 进入 Ubuntu 容器
docker compose exec -it nginx-ubuntu-vhost bash
```

---

### 3.2 基于端口的虚拟主机

#### 3.2.1 应用场景

| 场景 | 说明 |
|------|------|
| **开发环境** | 本地多项目测试 |
| **内部系统** | 后台管理、监控面板 |
| **临时演示** | 无需配置 DNS |

#### 3.2.2 准备网站文件

```bash
# 创建三个网站目录
mkdir -p /data/server/nginx/web{1,2,3}

# 创建首页文件
echo "<h1>Welcome to Website 1</h1>" > /data/server/nginx/web1/index.html
echo "<h1>Welcome to Website 2</h1>" > /data/server/nginx/web2/index.html
echo "<h1>Welcome to Website 3</h1>" > /data/server/nginx/web3/index.html

# 添加子目录和文件
mkdir /data/server/nginx/web1/dir1
echo "<h1>Web1 - Directory 1</h1>" > /data/server/nginx/web1/dir1/index.html

# 查看目录结构
tree /data/server/nginx/
# /data/server/nginx/
# ├── web1
# │   ├── dir1
# │   │   └── index.html
# │   └── index.html
# ├── web2
# │   └── index.html
# └── web3
#     └── index.html
```

#### 3.2.3 配置虚拟主机

```bash
# 删除默认配置（如果存在）
rm -f /data/server/nginx/conf/conf.d/default.conf

# 创建基于端口的虚拟主机配置
cat > /data/server/nginx/conf/conf.d/port-vhost.conf <<'EOF'
# 虚拟主机 1 - 端口 80
server {
    listen 80;
    root /data/server/nginx/web1;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}

# 虚拟主机 2 - 端口 81
server {
    listen 81;
    root /data/server/nginx/web2;
    index index.html;
}

# 虚拟主机 3 - 端口 82
server {
    listen 82;
    root /data/server/nginx/web3;
    index index.html;
}
EOF

# 测试配置
nginx -t

# 启动 Nginx
nginx
```

#### 3.2.4 测试访问

```bash
# 测试 80 端口
curl http://127.0.0.1:80
# 输出：<h1>Welcome to Website 1</h1>

# 测试 81 端口
curl http://127.0.0.1:81
# 输出：<h1>Welcome to Website 2</h1>

# 测试 82 端口
curl http://127.0.0.1:82
# 输出：<h1>Welcome to Website 3</h1>

# 在宿主机测试（通过 Docker 端口映射）
curl http://localhost:8040  # 访问 web1
curl http://localhost:8041  # 访问 web2
curl http://localhost:8042  # 访问 web3
```

---

### 3.3 基于域名的虚拟主机（推荐）

#### 3.3.1 应用场景

| 场景 | 说明 |
|------|------|
| **生产环境** | 多个正式网站托管 |
| **SaaS 平台** | 多租户子域名 |
| **微服务** | 不同域名对应不同服务 |

#### 3.3.2 配置虚拟主机

```bash
# 创建基于域名的虚拟主机配置
cat > /data/server/nginx/conf/conf.d/domain-vhost.conf <<'EOF'
# 虚拟主机 1 - www.site1.com
server {
    listen 80;
    server_name www.site1.com site1.com;
    root /data/server/nginx/web1;
    index index.html;

    access_log /data/server/nginx/logs/site1_access.log;
    error_log /data/server/nginx/logs/site1_error.log;

    location / {
        try_files $uri $uri/ =404;
    }
}

# 虚拟主机 2 - www.site2.com
server {
    listen 80;
    server_name www.site2.com site2.com;
    root /data/server/nginx/web2;
    index index.html;

    access_log /data/server/nginx/logs/site2_access.log;
    error_log /data/server/nginx/logs/site2_error.log;
}

# 虚拟主机 3 - www.site3.com
server {
    listen 80;
    server_name www.site3.com site3.com;
    root /data/server/nginx/web3;
    index index.html;

    access_log /data/server/nginx/logs/site3_access.log;
    error_log /data/server/nginx/logs/site3_error.log;
}

# 默认虚拟主机（兜底，处理未匹配的域名）
server {
    listen 80 default_server;
    server_name _;
    return 444;  # 直接关闭连接
}
EOF

# 重载配置
nginx -s reload
```

#### 3.3.3 配置 /etc/hosts（模拟 DNS）

**在容器内**：

```bash
# 添加域名解析
cat >> /etc/hosts <<EOF
127.0.0.1 www.site1.com site1.com
127.0.0.1 www.site2.com site2.com
127.0.0.1 www.site3.com site3.com
EOF
```

**在宿主机**（可选，用于浏览器访问）：

```bash
# Linux/Mac
sudo tee -a /etc/hosts <<EOF
127.0.0.1 www.site1.local
127.0.0.1 www.site2.local
127.0.0.1 www.site3.local
EOF

# Windows（以管理员身份编辑）
# C:\Windows\System32\drivers\etc\hosts
127.0.0.1 www.site1.local
127.0.0.1 www.site2.local
127.0.0.1 www.site3.local
```

#### 3.3.4 测试域名访问

```bash
# 测试 site1
curl -H "Host: www.site1.com" http://127.0.0.1
# 输出：<h1>Welcome to Website 1</h1>

# 测试 site2
curl -H "Host: www.site2.com" http://127.0.0.1
# 输出：<h1>Welcome to Website 2</h1>

# 测试 site3
curl -H "Host: www.site3.com" http://127.0.0.1
# 输出：<h1>Welcome to Website 3</h1>

# 测试默认虚拟主机（未知域名）
curl -H "Host: www.unknown.com" http://127.0.0.1
# 输出：（无响应，连接直接关闭）

# 测试不带 Host 头
curl http://127.0.0.1
# 输出：（匹配 default_server，连接关闭）
```

---

### 3.4 Location 匹配规则实践

#### 3.4.1 准备测试文件

```bash
# 在 web1 目录下创建多种资源
mkdir -p /data/server/nginx/web1/{documents,images,api}

# 创建测试文件
echo "Document Page" > /data/server/nginx/web1/documents/index.html
echo "Image Directory" > /data/server/nginx/web1/images/index.html
echo "API Response" > /data/server/nginx/web1/api/index.html

# 创建图片文件（模拟）
touch /data/server/nginx/web1/images/photo.jpg
touch /data/server/nginx/web1/images/logo.gif
touch /data/server/nginx/web1/test.png
```

#### 3.4.2 配置不同匹配规则

```bash
cat > /data/server/nginx/conf/conf.d/location-test.conf <<'EOF'
server {
    listen 80;
    server_name test.location.com;
    root /data/server/nginx/web1;

    # 规则 1：精确匹配（最高优先级）
    location = / {
        return 200 "Rule 1: Exact match for /\n";
    }

    # 规则 2：精确匹配特定路径
    location = /api {
        return 200 "Rule 2: Exact match for /api\n";
    }

    # 规则 3：优先前缀匹配（^~）
    location ^~ /images/ {
        return 200 "Rule 3: Priority prefix match for /images/\n";
    }

    # 规则 4：正则匹配（区分大小写）
    location ~ \.(jpg|jpeg|png|gif)$ {
        return 200 "Rule 4: Regex match for image files\n";
    }

    # 规则 5：正则匹配（不区分大小写）
    location ~* \.(JPG|PNG)$ {
        return 200 "Rule 5: Case-insensitive regex match\n";
    }

    # 规则 6：普通前缀匹配
    location /documents/ {
        return 200 "Rule 6: Prefix match for /documents/\n";
    }

    # 规则 7：兜底规则
    location / {
        return 200 "Rule 7: Default match for all\n";
    }
}
EOF

# 重载配置
nginx -s reload
```

#### 3.4.3 测试匹配优先级

```bash
# 测试 1：精确匹配 /
curl -H "Host: test.location.com" http://127.0.0.1/
# 输出：Rule 1: Exact match for /

# 测试 2：精确匹配 /api
curl -H "Host: test.location.com" http://127.0.0.1/api
# 输出：Rule 2: Exact match for /api

# 测试 3：优先前缀匹配 ^~
curl -H "Host: test.location.com" http://127.0.0.1/images/photo.jpg
# 输出：Rule 3: Priority prefix match for /images/
# 说明：虽然规则 4 也能匹配 .jpg，但 ^~ 优先级更高

# 测试 4：正则匹配（区分大小写）
curl -H "Host: test.location.com" http://127.0.0.1/test.png
# 输出：Rule 4: Regex match for image files

# 测试 5：正则匹配（不区分大小写）
curl -H "Host: test.location.com" http://127.0.0.1/test.PNG
# 输出：Rule 5: Case-insensitive regex match

# 测试 6：普通前缀匹配
curl -H "Host: test.location.com" http://127.0.0.1/documents/
# 输出：Rule 6: Prefix match for /documents/

# 测试 7：兜底规则
curl -H "Host: test.location.com" http://127.0.0.1/unknown
# 输出：Rule 7: Default match for all
```

---

### 3.5 Root 与 Alias 实践

#### 3.5.1 Root 使用场景

```bash
cat > /data/server/nginx/conf/conf.d/root-test.conf <<'EOF'
server {
    listen 80;
    server_name root.test.com;
    root /data/server/nginx/web1;

    # location 路径会拼接到 root 后面
    location /dir1/ {
        root /data/server/nginx/web1;
        # 访问 /dir1/index.html
        # 实际路径：/data/server/nginx/web1/dir1/index.html
    }

    location /documents/ {
        root /data/server/nginx/web1;
        # 访问 /documents/index.html
        # 实际路径：/data/server/nginx/web1/documents/index.html
    }
}
EOF

nginx -s reload

# 测试 root
curl -H "Host: root.test.com" http://127.0.0.1/dir1/index.html
# 输出：<h1>Web1 - Directory 1</h1>

curl -H "Host: root.test.com" http://127.0.0.1/documents/index.html
# 输出：Document Page
```

#### 3.5.2 Alias 使用场景

```bash
cat > /data/server/nginx/conf/conf.d/alias-test.conf <<'EOF'
server {
    listen 80;
    server_name alias.test.com;
    root /data/server/nginx/web1;

    # 将 /web2/ 映射到 web2 目录
    location /web2/ {
        alias /data/server/nginx/web2/;
        # 访问 /web2/index.html
        # 实际路径：/data/server/nginx/web2/index.html
        # （注意：/web2/ 被 alias 替换了）
    }

    # 将 /web3/ 映射到 web3 目录
    location /web3/ {
        alias /data/server/nginx/web3/;
        # 访问 /web3/index.html
        # 实际路径：/data/server/nginx/web3/index.html
    }

    # 将 /pics/ 映射到 images 目录
    location /pics/ {
        alias /data/server/nginx/web1/images/;
        autoindex on;  # 开启目录浏览
    }
}
EOF

nginx -s reload

# 测试 alias
curl -H "Host: alias.test.com" http://127.0.0.1/web2/index.html
# 输出：<h1>Welcome to Website 2</h1>

curl -H "Host: alias.test.com" http://127.0.0.1/web3/index.html
# 输出：<h1>Welcome to Website 3</h1>

curl -H "Host: alias.test.com" http://127.0.0.1/pics/
# 输出：（目录列表）
```

---

## 🔐 第四部分：访问控制实践

### 4.1 IP 黑白名单

#### 4.1.1 切换到 Rocky 容器

```bash
# 退出 Ubuntu 容器
exit

# 进入 Rocky 容器
docker compose exec -it nginx-rocky-vhost bash

# 启动 Nginx（已预装）
nginx
```

#### 4.1.2 准备测试文件

```bash
mkdir -p /data/server/nginx/{public,private,internal}

echo "<h1>Public Content</h1>" > /data/server/nginx/public/index.html
echo "<h1>Private Content</h1>" > /data/server/nginx/private/index.html
echo "<h1>Internal Only</h1>" > /data/server/nginx/internal/index.html
```

#### 4.1.3 配置访问控制

```bash
cat > /data/server/nginx/conf/conf.d/access-control.conf <<'EOF'
server {
    listen 80;
    server_name _;

    # 公开内容（所有人可访问）
    location /public/ {
        alias /data/server/nginx/public/;
    }

    # 私有内容（仅允许特定 IP）
    location /private/ {
        alias /data/server/nginx/private/;

        allow 127.0.0.1;      # 允许本机
        allow 10.0.7.0/24;    # 允许 Docker 网段
        deny all;             # 拒绝其他所有 IP
    }

    # 内部内容（仅本机可访问）
    location /internal/ {
        alias /data/server/nginx/internal/;

        allow 127.0.0.1;
        deny all;
    }
}
EOF

nginx -s reload
```

#### 4.1.4 测试访问控制

```bash
# 测试 1：公开内容（应该成功）
curl http://127.0.0.1/public/
# 输出：<h1>Public Content</h1>

# 测试 2：私有内容（本机应该成功）
curl http://127.0.0.1/private/
# 输出：<h1>Private Content</h1>

# 测试 3：内部内容（本机应该成功）
curl http://127.0.0.1/internal/
# 输出：<h1>Internal Only</h1>

# 在容器外测试（模拟外部访问）
# 从宿主机执行（应该被拒绝，因为 allow 规则中没有宿主机 IP）
curl http://localhost:8043/private/
# 输出：403 Forbidden
```

---

### 4.2 HTTP 基本认证

#### 4.2.1 安装密码工具

```bash
# Rocky 系统
yum install -y httpd-tools

# Ubuntu 系统（如果在 Ubuntu 容器中）
# apt install -y apache2-utils
```

#### 4.2.2 创建用户密码

```bash
# 创建第一个用户（使用 -c 创建文件）
htpasswd -c /data/server/nginx/conf/.htpasswd admin
# 提示输入密码：输入 admin123

# 添加第二个用户（不使用 -c）
htpasswd /data/server/nginx/conf/.htpasswd user01
# 提示输入密码：输入 user123

# 非交互式添加用户
htpasswd -b /data/server/nginx/conf/.htpasswd user02 pass456

# 查看密码文件
cat /data/server/nginx/conf/.htpasswd
# 输出：
# admin:$apr1$xxx...
# user01:$apr1$yyy...
# user02:$apr1$zzz...

# 设置文件权限
chmod 600 /data/server/nginx/conf/.htpasswd
```

#### 4.2.3 配置身份认证

```bash
cat > /data/server/nginx/conf/conf.d/auth-test.conf <<'EOF'
server {
    listen 80;
    server_name auth.test.com;

    # 公开区域（无需认证）
    location /public/ {
        alias /data/server/nginx/public/;
    }

    # 管理后台（需要认证）
    location /admin/ {
        alias /data/server/nginx/private/;

        auth_basic "Admin Area - Please Login";
        auth_basic_user_file /data/server/nginx/conf/.htpasswd;
    }

    # 结合 IP 白名单和身份认证
    location /secure/ {
        alias /data/server/nginx/internal/;

        # 先验证 IP
        allow 127.0.0.1;
        allow 10.0.7.0/24;
        deny all;

        # 再验证身份
        auth_basic "Secure Area";
        auth_basic_user_file /data/server/nginx/conf/.htpasswd;

        # 两个条件都满足才能访问
        satisfy all;  # 默认值，可省略
    }
}
EOF

nginx -s reload
```

#### 4.2.4 测试身份认证

```bash
# 测试 1：公开区域（无需认证）
curl http://127.0.0.1/public/
# 输出：<h1>Public Content</h1>

# 测试 2：管理后台（未提供认证，应该 401）
curl -I http://127.0.0.1/admin/
# 输出：HTTP/1.1 401 Unauthorized
#      WWW-Authenticate: Basic realm="Admin Area - Please Login"

# 测试 3：管理后台（提供正确认证）
curl -u admin:admin123 http://127.0.0.1/admin/
# 输出：<h1>Private Content</h1>

# 测试 4：管理后台（错误密码）
curl -u admin:wrongpass http://127.0.0.1/admin/
# 输出：401 Unauthorized

# 测试 5：URL 中嵌入认证信息
curl http://admin:admin123@127.0.0.1/admin/
# 输出：<h1>Private Content</h1>

# 测试 6：安全区域（需要 IP + 认证）
curl -u admin:admin123 http://127.0.0.1/secure/
# 输出：<h1>Internal Only</h1>
```

---

## 📊 第五部分：日志管理实践

### 5.1 自定义日志格式

#### 5.1.1 定义多种日志格式

```bash
# 编辑主配置文件
vim /data/server/nginx/conf/nginx.conf

# 在 http 段添加日志格式
http {
    # 格式 1：基本格式（包含核心信息）
    log_format basic '$remote_addr [$time_local] '
                     '"$request" $status $body_bytes_sent '
                     '"$http_user_agent"';

    # 格式 2：详细格式（包含完整信息）
    log_format detailed '$remote_addr - $remote_user [$time_local] '
                        '"$request" $status $body_bytes_sent '
                        '"$http_referer" "$http_user_agent" '
                        '$request_time $upstream_response_time';

    # 格式 3：JSON 格式（便于日志分析）
    log_format json escape=json '{'
        '"timestamp":"$time_iso8601",'
        '"client_ip":"$remote_addr",'
        '"request":"$request",'
        '"status":$status,'
        '"bytes_sent":$body_bytes_sent,'
        '"request_time":$request_time,'
        '"user_agent":"$http_user_agent",'
        '"referer":"$http_referer",'
        '"host":"$host"'
    '}';

    # 格式 4：性能监控格式
    log_format performance '$remote_addr - $request_time - $upstream_response_time '
                           '[$time_local] "$request" $status $body_bytes_sent';

    # ... 其他配置
}
```

#### 5.1.2 应用日志格式

```bash
cat > /data/server/nginx/conf/conf.d/log-test.conf <<'EOF'
server {
    listen 80;
    server_name log.test.com;

    # 全局访问日志（使用详细格式）
    access_log /data/server/nginx/logs/detailed_access.log detailed;

    # 位置 1：使用基本格式
    location /api/ {
        alias /data/server/nginx/public/;
        access_log /data/server/nginx/logs/api_access.log basic;
    }

    # 位置 2：使用 JSON 格式
    location /json/ {
        alias /data/server/nginx/public/;
        access_log /data/server/nginx/logs/json_access.log json;
    }

    # 位置 3：性能监控
    location /monitor/ {
        alias /data/server/nginx/public/;
        access_log /data/server/nginx/logs/performance.log performance;
    }

    # 位置 4：不记录日志
    location /health {
        access_log off;
        return 200 "OK\n";
    }

    # 位置 5：条件日志（仅记录 4xx/5xx 错误）
    location /errors/ {
        alias /data/server/nginx/public/;
        access_log /data/server/nginx/logs/error_only.log detailed if=$loggable;
    }
}

# 定义条件变量
map $status $loggable {
    ~^[45]  1;
    default 0;
}
EOF

nginx -s reload
```

#### 5.1.3 测试日志记录

```bash
# 生成测试请求
curl -H "Host: log.test.com" http://127.0.0.1/api/
curl -H "Host: log.test.com" http://127.0.0.1/json/
curl -H "Host: log.test.com" http://127.0.0.1/monitor/
curl -H "Host: log.test.com" http://127.0.0.1/health
curl -H "Host: log.test.com" http://127.0.0.1/not-found  # 404 错误

# 查看基本格式日志
tail -1 /data/server/nginx/logs/api_access.log
# 输出：10.0.7.1 [12/Oct/2025:10:30:15 +0800] "GET /api/ HTTP/1.1" 200 25 "curl/7.68.0"

# 查看 JSON 格式日志
tail -1 /data/server/nginx/logs/json_access.log | jq .
# 输出：
# {
#   "timestamp": "2025-10-12T10:30:20+08:00",
#   "client_ip": "10.0.7.1",
#   "request": "GET /json/ HTTP/1.1",
#   "status": 200,
#   "bytes_sent": 25,
#   "request_time": 0.001,
#   "user_agent": "curl/7.68.0",
#   "referer": "",
#   "host": "log.test.com"
# }

# 查看性能日志
tail -1 /data/server/nginx/logs/performance.log
# 输出：10.0.7.1 - 0.001 - - [12/Oct/2025:10:30:25 +0800] "GET /monitor/ HTTP/1.1" 200 25

# 验证健康检查不记录日志
grep health /data/server/nginx/logs/*.log
# 输出：（无结果）
```

---

### 5.2 日志轮转配置

#### 5.2.1 配置 logrotate

```bash
cat > /etc/logrotate.d/nginx <<'EOF'
/data/server/nginx/logs/*.log {
    daily                   # 每天轮转
    rotate 30               # 保留 30 个归档
    missingok               # 如果日志文件丢失，不报错
    notifempty              # 空文件不轮转
    compress                # 压缩旧日志
    delaycompress           # 延迟一天压缩（便于查看昨天日志）
    dateext                 # 添加日期扩展名
    dateformat -%Y%m%d     # 日期格式：-20251012
    sharedscripts           # 所有日志处理完后执行一次脚本
    postrotate
        if [ -f /data/server/nginx/run/nginx.pid ]; then
            kill -USR1 $(cat /data/server/nginx/run/nginx.pid)
        fi
    endscript
}
EOF

# 测试轮转配置
logrotate -d /etc/logrotate.d/nginx

# 强制执行轮转（测试）
logrotate -f /etc/logrotate.d/nginx

# 查看轮转后的文件
ls -lh /data/server/nginx/logs/
# 输出：
# access.log
# access.log-20251012
# access.log-20251011.gz
# ...
```

---

## 🔍 第六部分：状态监控实践

### 6.1 Stub Status 模块

#### 6.1.1 配置状态页

```bash
cat > /data/server/nginx/conf/conf.d/status.conf <<'EOF'
server {
    listen 80;
    server_name status.test.com;

    # 状态页（仅限内网访问）
    location /nginx-status {
        stub_status;

        allow 127.0.0.1;
        allow 10.0.7.0/24;
        deny all;

        access_log off;
    }

    # 简单的健康检查端点
    location /health {
        access_log off;
        return 200 "healthy\n";
    }
}
EOF

nginx -s reload
```

#### 6.1.2 访问状态页

```bash
# 访问状态页
curl -H "Host: status.test.com" http://127.0.0.1/nginx-status

# 输出：
# Active connections: 1
# server accepts handled requests
#  125 125 320
# Reading: 0 Writing: 1 Waiting: 0
```

#### 6.1.3 状态指标解读

| 指标 | 说明 | 正常值 |
|------|------|--------|
| **Active connections** | 当前活动连接数 | < worker_connections |
| **accepts** | 累计接受的连接数 | 持续增长 |
| **handled** | 累计处理的连接数 | = accepts |
| **requests** | 累计处理的请求数 | ≥ handled |
| **Reading** | 正在读取请求头的连接数 | 较小值 |
| **Writing** | 正在发送响应的连接数 | 中等值 |
| **Waiting** | 空闲 keepalive 连接数 | 较大值 |

#### 6.1.4 监控脚本

```bash
# 创建监控脚本
cat > /usr/local/bin/nginx-monitor.sh <<'EOF'
#!/bin/bash

while true; do
    echo "=== Nginx Status at $(date) ==="
    curl -s http://127.0.0.1/nginx-status | grep -v "^$"
    echo ""
    sleep 5
done
EOF

chmod +x /usr/local/bin/nginx-monitor.sh

# 运行监控
/usr/local/bin/nginx-monitor.sh
```

---

## 📋 第七部分：综合实践案例

### 7.1 多站点企业级配置

#### 7.1.1 场景描述

企业需要在一台服务器上托管：
- 官网（www.company.com）
- 博客（blog.company.com）
- API 服务（api.company.com）
- 管理后台（admin.company.com，需要认证）

#### 7.1.2 完整配置

```bash
# 准备目录
mkdir -p /data/www/{website,blog,api,admin}

# 创建测试文件
echo "<h1>Company Website</h1>" > /data/www/website/index.html
echo "<h1>Company Blog</h1>" > /data/www/blog/index.html
echo '{"status":"ok"}' > /data/www/api/index.json
echo "<h1>Admin Dashboard</h1>" > /data/www/admin/index.html

# 创建认证文件
htpasswd -bc /data/server/nginx/conf/.admin-passwd admin admin@2025

# 配置虚拟主机
cat > /data/server/nginx/conf/conf.d/enterprise.conf <<'EOF'
# 官网
server {
    listen 80;
    server_name www.company.com company.com;
    root /data/www/website;
    index index.html;

    access_log /data/server/nginx/logs/website_access.log detailed;
    error_log /data/server/nginx/logs/website_error.log warn;

    location / {
        try_files $uri $uri/ =404;
    }

    # 静态资源缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}

# 博客
server {
    listen 80;
    server_name blog.company.com;
    root /data/www/blog;
    index index.html;

    access_log /data/server/nginx/logs/blog_access.log detailed;

    location / {
        try_files $uri $uri/ =404;
    }
}

# API 服务
server {
    listen 80;
    server_name api.company.com;
    root /data/www/api;

    access_log /data/server/nginx/logs/api_access.log json;

    # API 限流
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

    location / {
        limit_req zone=api_limit burst=20 nodelay;

        default_type application/json;
        add_header Access-Control-Allow-Origin "*";
        try_files $uri $uri/ =404;
    }
}

# 管理后台（需要认证）
server {
    listen 80;
    server_name admin.company.com;
    root /data/www/admin;
    index index.html;

    access_log /data/server/nginx/logs/admin_access.log detailed;

    # IP 白名单 + 身份认证
    location / {
        allow 10.0.7.0/24;
        deny all;

        auth_basic "Admin Login Required";
        auth_basic_user_file /data/server/nginx/conf/.admin-passwd;

        try_files $uri $uri/ =404;
    }

    # 状态监控（仅管理员可见）
    location /status {
        stub_status;
        access_log off;
    }
}
EOF

nginx -s reload
```

#### 7.1.3 测试企业配置

```bash
# 测试官网
curl -H "Host: www.company.com" http://127.0.0.1
# 输出：<h1>Company Website</h1>

# 测试博客
curl -H "Host: blog.company.com" http://127.0.0.1
# 输出：<h1>Company Blog</h1>

# 测试 API
curl -H "Host: api.company.com" http://127.0.0.1/index.json
# 输出：{"status":"ok"}

# 测试管理后台（需要认证）
curl -u admin:admin@2025 -H "Host: admin.company.com" http://127.0.0.1
# 输出：<h1>Admin Dashboard</h1>

# 测试管理后台状态页
curl -u admin:admin@2025 -H "Host: admin.company.com" http://127.0.0.1/status
# 输出：Active connections: 1 ...
```

---

## 🔧 第八部分：故障排除

### 8.1 常见问题

#### 问题 1：404 Not Found（找不到文件）

**症状**：
```bash
curl http://127.0.0.1/test.html
# 404 Not Found
```

**排查步骤**：

```bash
# 1. 检查文件是否存在
ls -l /data/server/nginx/web1/test.html

# 2. 检查 root 或 alias 配置
nginx -T | grep -A 5 "location /"

# 3. 检查文件权限
ls -l /data/server/nginx/web1/

# 4. 查看错误日志
tail -20 /data/server/nginx/logs/error.log
# 常见错误：
# - open() "/path/to/file" failed (2: No such file or directory)
# - open() "/path/to/file" failed (13: Permission denied)

# 解决方法：
# - 确保文件存在
# - 设置正确权限：chmod 644 文件, chmod 755 目录
# - 检查 SELinux：setenforce 0（临时）
```

---

#### 问题 2：403 Forbidden（权限拒绝）

**症状**：
```bash
curl http://127.0.0.1/test.html
# 403 Forbidden
```

**原因 1：文件权限不足**

```bash
# 检查权限
ls -l /data/server/nginx/web1/test.html

# 解决：
chmod 644 /data/server/nginx/web1/test.html
chmod 755 /data/server/nginx/web1
```

**原因 2：deny 规则拒绝**

```bash
# 检查配置
nginx -T | grep -A 10 "location"

# 解决：调整 allow/deny 顺序
location / {
    allow 10.0.7.0/24;
    deny all;
}
```

**原因 3：目录索引禁用**

```bash
# 访问目录时没有 index 文件且未开启 autoindex
location / {
    autoindex on;  # 开启目录浏览
}
```

---

#### 问题 3：域名不匹配，访问到错误的站点

**症状**：
```bash
curl -H "Host: www.site1.com" http://127.0.0.1
# 返回的是 site2 的内容
```

**原因：server_name 配置错误或缺少 default_server**

```bash
# 检查配置
nginx -T | grep -B 5 "server_name"

# 解决：明确指定 default_server
server {
    listen 80 default_server;
    server_name _;
    return 444;  # 拒绝未知域名
}

# 然后为每个站点配置正确的 server_name
server {
    listen 80;
    server_name www.site1.com site1.com;
    ...
}
```

---

#### 问题 4：alias 结尾没有斜杠

**症状**：
```bash
curl http://127.0.0.1/images/logo.png
# 404 Not Found
```

**原因：alias 路径缺少结尾斜杠**

```bash
# ❌ 错误配置
location /images/ {
    alias /data/server/nginx/pictures;  # 缺少斜杠
}

# 访问 /images/logo.png 变成 /data/server/nginx/pictureslogo.png（错误）

# ✅ 正确配置
location /images/ {
    alias /data/server/nginx/pictures/;  # 必须有斜杠
}
```

---

#### 问题 5：日志文件权限错误

**症状**：
```bash
ps aux | grep nginx
# nginx: [emerg] open() "/data/server/nginx/logs/access.log" failed (13: Permission denied)
```

**解决方法**：

```bash
# 检查日志目录权限
ls -ld /data/server/nginx/logs/

# 修复权限
chmod 755 /data/server/nginx/logs/
chmod 644 /data/server/nginx/logs/*.log

# 确认 nginx 用户
grep "^user" /data/server/nginx/conf/nginx.conf
# user nginx;  # 或 www-data
```

---

## 📋 第九部分：测试检查清单

### 9.1 虚拟主机配置检查

- [ ] **基于端口的虚拟主机**
  - [ ] 配置多个 listen 端口
  - [ ] 每个端口对应不同目录
  - [ ] 测试各端口独立访问

- [ ] **基于域名的虚拟主机**
  - [ ] 配置 server_name
  - [ ] 设置 default_server
  - [ ] 测试域名匹配
  - [ ] 测试未知域名处理

- [ ] **基于 IP 的虚拟主机**
  - [ ] 配置多个 IP 地址
  - [ ] 每个 IP 独立配置
  - [ ] 测试 IP 访问

### 9.2 Location 匹配检查

- [ ] **精确匹配（=）**
  - [ ] 配置 `location =`
  - [ ] 验证最高优先级

- [ ] **优先前缀匹配（^~）**
  - [ ] 配置 `location ^~`
  - [ ] 验证优先于正则

- [ ] **正则匹配（~ 和 ~*）**
  - [ ] 配置大小写敏感匹配
  - [ ] 配置大小写不敏感匹配
  - [ ] 测试正则表达式

- [ ] **普通前缀匹配**
  - [ ] 配置无符号 location
  - [ ] 验证最长匹配

### 9.3 访问控制检查

- [ ] **IP 黑白名单**
  - [ ] 配置 allow/deny 规则
  - [ ] 测试规则顺序
  - [ ] 验证拒绝效果

- [ ] **HTTP 基本认证**
  - [ ] 创建密码文件
  - [ ] 配置 auth_basic
  - [ ] 测试认证流程
  - [ ] 测试错误密码

### 9.4 日志管理检查

- [ ] **日志格式定义**
  - [ ] 定义 log_format
  - [ ] 测试基本格式
  - [ ] 测试 JSON 格式

- [ ] **日志应用**
  - [ ] 配置 access_log
  - [ ] 配置 error_log
  - [ ] 验证日志记录
  - [ ] 测试日志轮转

---

## ❓ 第十部分：常见问题

### Q1: root 和 alias 有什么区别？

**答**：

**核心区别**：
- **root**：拼接 location 路径 → `最终路径 = root + location + 文件名`
- **alias**：替换 location 路径 → `最终路径 = alias + 文件名`

**示例**：
```nginx
# root 示例
location /images/ {
    root /data/server/nginx/html;
}
# 访问 /images/logo.png → /data/server/nginx/html/images/logo.png

# alias 示例
location /images/ {
    alias /data/server/nginx/pictures/;
}
# 访问 /images/logo.png → /data/server/nginx/pictures/logo.png
```

**使用建议**：
- 标准目录结构 → 使用 root
- 路径映射/重定向 → 使用 alias

---

### Q2: location 匹配优先级是什么？

**答**：从高到低依次为：

1. **精确匹配（=）** → 完全相同立即返回
2. **优先前缀匹配（^~）** → 匹配后不再检查正则
3. **正则匹配（~ 和 ~*）** → 按配置顺序，匹配第一个
4. **普通前缀匹配（无符号）** → 选择最长匹配
5. **通用匹配（/）** → 兜底规则

---

### Q3: 如何限制特定 IP 访问？

**答**：

**白名单模式**（仅允许特定 IP）：
```nginx
location /admin/ {
    allow 10.0.0.1;
    allow 192.168.1.0/24;
    deny all;
}
```

**黑名单模式**（禁止特定 IP）：
```nginx
location / {
    deny 10.0.0.100;
    deny 192.168.2.0/24;
    allow all;
}
```

**规则顺序**：从上到下依次匹配，匹配到第一个规则即返回。

---

### Q4: 如何自定义错误页面？

**答**：

```nginx
server {
    listen 80;

    # 自定义 404 错误页
    error_page 404 /404.html;
    location = /404.html {
        root /data/server/nginx/html/errors;
        internal;  # 仅内部访问
    }

    # 多个状态码共用一个页面
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /data/server/nginx/html/errors;
    }

    # 重定向到外部 URL
    error_page 404 =302 http://www.example.com;
}
```

---

### Q5: 如何配置日志不记录特定请求？

**答**：

**方法 1：access_log off**
```nginx
location /health {
    access_log off;
    return 200 "OK";
}
```

**方法 2：条件日志**
```nginx
# 定义条件变量
map $request_uri $loggable {
    /health   0;
    /status   0;
    default   1;
}

# 应用条件
access_log /data/server/nginx/logs/access.log combined if=$loggable;
```

---

## 🎓 第十一部分：学习总结

### 11.1 核心知识点

1. **虚拟主机配置**：
   - 基于域名（推荐）、基于端口、基于 IP
   - server_name 匹配规则
   - default_server 作用

2. **Location 匹配**：
   - 5 种匹配符号及优先级
   - 匹配流程图
   - 最佳实践

3. **Root vs Alias**：
   - 路径拼接 vs 路径替换
   - 使用场景选择
   - 常见错误避免

4. **访问控制**：
   - IP 黑白名单（allow/deny）
   - HTTP 基本认证（auth_basic）
   - 规则组合应用

5. **日志管理**：
   - log_format 自定义格式
   - access_log 应用
   - JSON 格式日志
   - logrotate 轮转

### 11.2 实战能力

通过本环境的学习，你应该能够：

✅ 配置多种类型的虚拟主机（域名/端口/IP）
✅ 理解并应用 location 匹配规则
✅ 正确使用 root 和 alias 指令
✅ 配置 IP 白名单和身份认证
✅ 自定义日志格式并进行日志管理
✅ 排查虚拟主机配置常见问题
✅ 搭建企业级多站点托管环境

---

## 🧹 清理环境

```bash
# 1. 停止所有容器
docker compose down

# 2. 删除 Volume（可选）
docker compose down --volumes

# 3. 完全清理（包括镜像）
docker compose down --volumes --rmi all
```

---

## 📖 参考资料

- **Nginx Server 文档**: https://nginx.org/en/docs/http/ngx_http_core_module.html#server
- **Nginx Location 文档**: https://nginx.org/en/docs/http/ngx_http_core_module.html#location
- **Nginx Access 模块**: https://nginx.org/en/docs/http/ngx_http_access_module.html
- **Nginx Auth Basic 模块**: https://nginx.org/en/docs/http/ngx_http_auth_basic_module.html
- **Nginx Log 模块**: https://nginx.org/en/docs/http/ngx_http_log_module.html

---

**完成时间**: 2025-10-12
**文档版本**: v1.0
**适用场景**: Nginx 虚拟主机配置、访问控制、日志管理
