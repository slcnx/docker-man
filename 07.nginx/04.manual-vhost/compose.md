# sudo docker compose Nginx 虚拟主机与配置实践指南

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
│   ├── 端口：80, 81, 82
│   └── 用途：基于端口、域名的虚拟主机
└── 10.0.7.41  - Rocky 虚拟主机演示（nginx-rocky-vhost）
    ├── 端口：80
    └── 用途：访问控制、日志管理、状态监控
```

### 2.2 sudo docker compose 配置说明

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
sudo docker compose up -d

# 3. 检查服务状态
sudo docker compose ps

# 4. 进入 Ubuntu 容器
sudo docker compose exec -it nginx-ubuntu-vhost bash
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
# 创建网站根目录和三个网站子目录
mkdir -p /data/wwwroot/web{1,2,3}

# 创建首页文件
echo "<h1>Welcome to Website 1</h1>" > /data/wwwroot/web1/index.html
echo "<h1>Welcome to Website 2</h1>" > /data/wwwroot/web2/index.html
echo "<h1>Welcome to Website 3</h1>" > /data/wwwroot/web3/index.html

# 添加子目录和文件
mkdir /data/wwwroot/web1/dir1
echo "<h1>Web1 - Directory 1</h1>" > /data/wwwroot/web1/dir1/index.html

# 查看目录结构
tree /data/wwwroot/
# /data/wwwroot/
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

**说明**：本镜像已在 Dockerfile 中自动创建 `conf.d` 目录并配置 `include` 指令。

**⚠️ 重要**：需要注释掉 `nginx.conf` 中的默认 server 块，避免与自定义配置冲突。

```bash

# 创建基于端口的虚拟主机配置
cat > /data/server/nginx/conf/conf.d/port-vhost.conf <<'EOF'
# 虚拟主机 1 - 端口 80
server {
    listen 80;
    root /data/wwwroot/web1;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}

# 虚拟主机 2 - 端口 81
server {
    listen 81;
    root /data/wwwroot/web2;
    index index.html;
}

# 虚拟主机 3 - 端口 82
server {
    listen 82;
    root /data/wwwroot/web3;
    index index.html;
}
EOF

# 测试配置
/data/server/nginx/sbin/nginx -t

# 启动 Nginx（使用绝对路径，避免升级时出现问题）
/data/server/nginx/sbin/nginx
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

# 在宿主机测试（通过静态 IP 直接访问）
curl http://10.0.7.40:80  # 访问 web1
curl http://10.0.7.40:81  # 访问 web2
curl http://10.0.7.40:82  # 访问 web3
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
    root /data/wwwroot/web1;
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
    root /data/wwwroot/web2;
    index index.html;

    access_log /data/server/nginx/logs/site2_access.log;
    error_log /data/server/nginx/logs/site2_error.log;
}

# 虚拟主机 3 - www.site3.com
server {
    listen 80;
    server_name www.site3.com site3.com;
    root /data/wwwroot/web3;
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
/data/server/nginx/sbin/nginx -s reload
```

#### 3.3.3 使用 DNS 服务器（手动配置）

使用 `01.dns/03.manual-master-slave-dns` 项目提供的主从 DNS 服务器进行域名解析。

```bash
# 1. 启动 DNS 服务器（在另一个终端）
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose up --build -d

# 2. 配置主 DNS 服务器（一键配置）
sudo docker compose exec -it dns-master bash

# 推荐：长选项（参数含义明确，适合文档和教学）
setup-dns-master.sh --domain site1.com --web-ip 10.0.7.40 \
                    --master-ip 10.0.0.13 --slave-ip 10.0.0.15
setup-dns-master.sh --domain site2.com --web-ip 10.0.7.40 \
                    --master-ip 10.0.0.13 --slave-ip 10.0.0.15
setup-dns-master.sh --domain site3.com --web-ip 10.0.7.40 \
                    --master-ip 10.0.0.13 --slave-ip 10.0.0.15

# 或者：位置参数（快速输入）
# setup-dns-master.sh site1.com 10.0.7.40 10.0.0.13 10.0.0.15
# setup-dns-master.sh site2.com 10.0.7.40 10.0.0.13 10.0.0.15
# setup-dns-master.sh site3.com 10.0.7.40 10.0.0.13 10.0.0.15

exit

# 3. 配置从 DNS 服务器（一键配置）
sudo docker compose exec -it dns-slave bash

# 推荐：长选项（参数含义明确，适合文档和教学）
setup-dns-slave.sh --domain site1.com --master-ip 10.0.0.13
setup-dns-slave.sh --domain site2.com --master-ip 10.0.0.13
setup-dns-slave.sh --domain site3.com --master-ip 10.0.0.13

# 或者：位置参数（快速输入）
# setup-dns-slave.sh site1.com 10.0.0.13
# setup-dns-slave.sh site2.com 10.0.0.13
# setup-dns-slave.sh site3.com 10.0.0.13

exit
```

#### 3.3.4 测试域名访问（在 client 容器中）

**⚠️ 重要**：以下所有测试均在 client 容器中完成，无需在宿主机配置 `/etc/hosts`。

```bash
# 测试 site1（使用域名直接访问）
curl http://www.site1.com
# 输出：<h1>Welcome to Website 1</h1>

# 测试 site2（使用域名直接访问）
curl http://www.site2.com
# 输出：<h1>Welcome to Website 2</h1>

# 测试 site3（使用域名直接访问）
curl http://www.site3.com
# 输出：<h1>Welcome to Website 3</h1>

# 测试不带 www 的域名
curl http://site1.com
curl http://site2.com
curl http://site3.com

# 查看响应头
curl -I http://www.site1.com
# 输出：
# HTTP/1.1 200 OK
# Server: nginx/1.26.2
# ...

# 测试访问不存在的域名（应该被 default_server 拒绝）
curl http://www.unknown.com
# 输出：（连接直接关闭，无响应）

# 查看访问日志（退出 client 容器后查看）
exit
sudo docker compose exec nginx-ubuntu-vhost bash
tail -5 /data/server/nginx/logs/site1_access.log
tail -5 /data/server/nginx/logs/site2_access.log
tail -5 /data/server/nginx/logs/site3_access.log
```

---

### 3.4 Location 匹配规则实践

#### 3.4.1 准备测试文件（在 nginx-ubuntu-vhost 容器中）

```bash
# 进入 Nginx 容器
cd /home/www/docker-man/07.nginx/04.manual-vhost
sudo docker compose exec -it nginx-ubuntu-vhost bash

# 在 web1 目录下创建多种资源
mkdir -p /data/wwwroot/web1/{documents,images,api}

# 创建测试文件
echo "Document Page" > /data/wwwroot/web1/documents/index.html
echo "Image Directory" > /data/wwwroot/web1/images/index.html
echo "API Response" > /data/wwwroot/web1/api/index.html

# 创建图片文件（模拟）
touch /data/wwwroot/web1/images/photo.jpg
touch /data/wwwroot/web1/images/logo.gif
touch /data/wwwroot/web1/test.png
```

#### 3.4.2 配置不同匹配规则（在 nginx-ubuntu-vhost 容器中）

```bash
cat > /data/server/nginx/conf/conf.d/location-test.conf <<'EOF'
server {
    listen 80;
    server_name test.location.com;
    root /data/wwwroot/web1;

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
/data/server/nginx/sbin/nginx -s reload

exit
```

#### 3.4.3 配置 DNS（添加测试域名 test.location.com）

```bash
# 进入 DNS master 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it dns-master bash

# 配置 test.location.com 域名
setup-dns-master.sh --domain test.location.com --web-ip 10.0.7.40 \
                    --master-ip 10.0.0.13 --slave-ip 10.0.0.15

exit

# 配置 DNS slave 同步
sudo docker compose exec -it dns-slave bash

setup-dns-slave.sh --domain test.location.com --master-ip 10.0.0.13

exit
```

#### 3.4.4 测试匹配优先级（在 client 容器中）

**⚠️ 重要**：所有测试在 DNS client 容器中完成，直接使用域名访问。

```bash
# 进入 client 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it client bash

# 测试 1：精确匹配 /
curl http://test.location.com/
# 输出：Rule 1: Exact match for /

# 测试 2：精确匹配 /api
curl http://test.location.com/api
# 输出：Rule 2: Exact match for /api

# 测试 3：优先前缀匹配 ^~
curl http://test.location.com/images/photo.jpg
# 输出：Rule 3: Priority prefix match for /images/
# 说明：虽然规则 4 也能匹配 .jpg，但 ^~ 优先级更高

# 测试 4：正则匹配（区分大小写）
curl http://test.location.com/test.png
# 输出：Rule 4: Regex match for image files

# 测试 5：正则匹配（不区分大小写）
curl http://test.location.com/test.PNG
# 输出：Rule 5: Case-insensitive regex match

# 测试 6：普通前缀匹配
curl http://test.location.com/documents/
# 输出：Rule 6: Prefix match for /documents/

# 测试 7：兜底规则
curl http://test.location.com/unknown
# 输出：Rule 7: Default match for all

# 验证 DNS 解析
nslookup test.location.com
# 输出：
# Server:         10.0.0.13
# Address:        10.0.0.13#53
#
# Name:   test.location.com
# Address: 10.0.7.40
```

---

### 3.5 Root 与 Alias 实践

#### 3.5.1 Root 使用场景（在 nginx-ubuntu-vhost 容器中）

```bash
# 进入 Nginx 容器
cd /home/www/docker-man/07.nginx/04.manual-vhost
sudo docker compose exec -it nginx-ubuntu-vhost bash

cat > /data/server/nginx/conf/conf.d/root-test.conf <<'EOF'
server {
    listen 80;
    server_name root.test.com;
    root /data/wwwroot/web1;

    # location 路径会拼接到 root 后面
    location /dir1/ {
        root /data/wwwroot/web1;
        # 访问 /dir1/index.html
        # 实际路径：/data/wwwroot/web1/dir1/index.html
    }

    location /documents/ {
        root /data/wwwroot/web1;
        # 访问 /documents/index.html
        # 实际路径：/data/wwwroot/web1/documents/index.html
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload

exit
```

#### 3.5.2 Alias 使用场景（在 nginx-ubuntu-vhost 容器中）

```bash
# 进入 Nginx 容器
cd /home/www/docker-man/07.nginx/04.manual-vhost
sudo docker compose exec -it nginx-ubuntu-vhost bash

cat > /data/server/nginx/conf/conf.d/alias-test.conf <<'EOF'
server {
    listen 80;
    server_name alias.test.com;
    root /data/wwwroot/web1;

    # 将 /web2/ 映射到 web2 目录
    location /web2/ {
        alias /data/wwwroot/web2/;
        # 访问 /web2/index.html
        # 实际路径：/data/wwwroot/web2/index.html
        # （注意：/web2/ 被 alias 替换了）
    }

    # 将 /web3/ 映射到 web3 目录
    location /web3/ {
        alias /data/wwwroot/web3/;
        # 访问 /web3/index.html
        # 实际路径：/data/wwwroot/web3/index.html
    }

    # 将 /pics/ 映射到 images 目录
    location /pics/ {
        alias /data/wwwroot/web1/images/;
        autoindex on;  # 开启目录浏览
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload

exit
```

#### 3.5.3 配置 DNS（添加测试域名 root.test.com 和 alias.test.com）

```bash
# 进入 DNS master 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it dns-master bash

# 配置 root.test.com 域名
setup-dns-master.sh --domain root.test.com --web-ip 10.0.7.40 \
                    --master-ip 10.0.0.13 --slave-ip 10.0.0.15

# 配置 alias.test.com 域名
setup-dns-master.sh --domain alias.test.com --web-ip 10.0.7.40 \
                    --master-ip 10.0.0.13 --slave-ip 10.0.0.15

exit

# 配置 DNS slave 同步
sudo docker compose exec -it dns-slave bash

setup-dns-slave.sh --domain root.test.com --master-ip 10.0.0.13
setup-dns-slave.sh --domain alias.test.com --master-ip 10.0.0.13

exit
```

#### 3.5.4 测试 Root 和 Alias（在 client 容器中）

**⚠️ 重要**：所有测试在 DNS client 容器中完成，直接使用域名访问。

```bash
# 进入 client 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it client bash

# 测试 root
curl http://root.test.com/dir1/index.html
# 输出：<h1>Web1 - Directory 1</h1>

curl http://root.test.com/documents/index.html
# 输出：Document Page

# 测试 alias
curl http://alias.test.com/web2/index.html
# 输出：<h1>Welcome to Website 2</h1>

curl http://alias.test.com/web3/index.html
# 输出：<h1>Welcome to Website 3</h1>

curl http://alias.test.com/pics/
# 输出：（目录列表）

# 验证 DNS 解析
nslookup root.test.com
nslookup alias.test.com
# 输出：
# Name:   root.test.com
# Address: 10.0.7.40
```

---

## 🔐 第四部分：访问控制实践

### 4.1 IP 黑白名单

#### 4.1.1 切换到 Rocky 容器

```bash
# 退出 Ubuntu 容器
exit

# 进入 Rocky 容器
sudo docker compose exec -it nginx-rocky-vhost bash

# 启动 Nginx（已预装，使用绝对路径）
/data/server/nginx/sbin/nginx
```

#### 4.1.2 准备测试文件

```bash
mkdir -p /data/wwwroot/{public,private,internal}

echo "<h1>Public Content</h1>" > /data/wwwroot/public/index.html
echo "<h1>Private Content</h1>" > /data/wwwroot/private/index.html
echo "<h1>Internal Only</h1>" > /data/wwwroot/internal/index.html
```

#### 4.1.3 配置访问控制

```bash
cat > /data/server/nginx/conf/conf.d/access-control.conf <<'EOF'
server {
    listen 80;
    server_name _;

    # 公开内容（所有人可访问）
    location /public/ {
        alias /data/wwwroot/public/;
    }

    # 私有内容（仅允许特定 IP）
    location /private/ {
        alias /data/wwwroot/private/;

        allow 127.0.0.1;      # 允许本机
        allow 10.0.7.0/24;    # 允许 Docker 网段
        deny all;             # 拒绝其他所有 IP
    }

    # 内部内容（仅本机可访问）
    location /internal/ {
        alias /data/wwwroot/internal/;

        allow 127.0.0.1;
        deny all;
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
```

#### 4.1.4 测试访问控制

**测试 1：在 Rocky 容器内测试（本机访问）**

```bash
# 在 Rocky 容器内（10.0.7.41）

# 测试 1.1：公开内容（应该成功）
curl http://127.0.0.1/public/
# 输出：<h1>Public Content</h1>

# 测试 1.2：私有内容（本机应该成功）
curl http://127.0.0.1/private/
# 输出：<h1>Private Content</h1>

# 测试 1.3：内部内容（本机应该成功）
curl http://127.0.0.1/internal/
# 输出：<h1>Internal Only</h1>
```

**测试 2：在同网段测试（10.0.7.0/24 允许访问）**

```bash
# 在宿主机或 Nginx Ubuntu 容器测试（10.0.7.0/24 网段）

# 测试 2.1：公开内容（应该成功）
curl http://10.0.7.41/public/
# 输出：<h1>Public Content</h1>

# 测试 2.2：私有内容（10.0.7.0/24 网段允许，应该成功）
curl http://10.0.7.41/private/
# 输出：<h1>Private Content</h1>

# 测试 2.3：内部内容（仅 127.0.0.1 允许，应该被拒绝）
sudo docker compose exec -it nginx-ubuntu-vhost bash
curl http://10.0.7.41/internal/
# 输出：403 Forbidden
```

**测试 3：跨网段测试（验证 Docker 网络行为）**

```bash
# 进入 DNS client 容器（10.0.0.12，不在 10.0.7.0/24 网段）
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it client bash

# 测试 3.1：公开内容（应该成功）
curl http://10.0.7.41/public/
# 输出：<h1>Public Content</h1>

# 测试 3.2：私有内容（实际会成功，因为 Docker NAT）
curl http://10.0.7.41/private/
# 输出：<h1>Private Content</h1>
# 说明：虽然 client 的真实 IP 是 10.0.0.12，但由于 Docker 跨网络 NAT，
#       Nginx 看到的源 IP 是 10.0.7.1（Docker 网关），在白名单内

# 测试 3.3：内部内容（仅 127.0.0.1 允许，应该被拒绝）
curl http://10.0.7.41/internal/
# 输出：403 Forbidden

# 查看 Nginx 日志验证源 IP
exit

cd /home/www/docker-man/07.nginx/04.manual-vhost
sudo docker compose exec nginx-rocky-vhost tail -5 /data/server/nginx/logs/access.log
# 输出示例：
# 10.0.7.1 - - [14/Oct/2025:03:04:28 +0000] "GET /public/ HTTP/1.1" 200 24 "-" "curl/7.76.1"
# 10.0.7.1 - - [14/Oct/2025:03:04:31 +0000] "GET /private/ HTTP/1.1" 200 25 "-" "curl/7.76.1"
# 10.0.7.1 - - [14/Oct/2025:03:04:50 +0000] "GET /internal/ HTTP/1.1" 403 153 "-" "curl/7.76.1"
#  ↑ 注意：所有请求的源 IP 都是 10.0.7.1（Docker 网关）
```

**⚠️ Docker 网络 NAT 行为说明：**

当跨 Docker 网络访问时（如从 10.0.0.0/24 访问 10.0.7.0/24），由于 Docker 的 NAT（网络地址转换）机制：
- **客户端真实 IP**：10.0.0.12
- **Nginx 看到的 IP**：10.0.7.1（Docker 网关）
- **结果**：10.0.7.1 在 `10.0.7.0/24` 白名单内，所以 `/private/` 仍然可访问

这是 Docker 网络的正常行为，在生产环境中可以通过以下方式获取真实客户端 IP：
- 使用 `real_ip` 模块
- 配置 `X-Forwarded-For` 头
- 使用 Host 网络模式

**测试结果对比：**

| 访问源 | 真实 IP | Nginx 看到的 IP | /public/ | /private/ | /internal/ |
|-------|---------|----------------|----------|-----------|-----------|
| **Rocky 容器内** | 127.0.0.1 | 127.0.0.1 | ✅ 200 OK | ✅ 200 OK | ✅ 200 OK |
| **同网段（10.0.7.0/24）** | 10.0.7.x | 10.0.7.x | ✅ 200 OK | ✅ 200 OK | ❌ 403 Forbidden |
| **跨网段（Docker NAT）** | 10.0.0.12 | 10.0.7.1（网关） | ✅ 200 OK | ✅ 200 OK | ❌ 403 Forbidden |

**说明：**
- `/public/`：所有人可访问
- `/private/`：仅允许 127.0.0.1 和 10.0.7.0/24 网段
- `/internal/`：仅允许 127.0.0.1（本机）

  - 配置 `X-Forwarded-For` 头

#### 4.1.5 配置跨网络测试环境（防止 Docker NAT）

**问题背景**：

默认情况下，Docker 容器跨网络访问时会进行源地址转换（SNAT/MASQUERADE），导致：
- 客户端真实 IP：10.0.0.12
- Nginx 看到的 IP：10.0.7.1（网关 IP）

这使得无法真正测试基于源 IP 的访问控制。

**解决方案**：

通过配置 iptables 规则，让特定网段之间的流量不进行源地址转换。

##### 步骤 1：在宿主机查看当前 iptables 规则

```bash
# 查看 POSTROUTING 链的 NAT 规则
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers

# 输出示例（修复前）：
# Chain POSTROUTING (policy ACCEPT)
# num   pkts bytes target     prot opt in     out     source               destination
# 1        0     0 MASQUERADE  all  --  *      !br-81794e30740f  10.0.0.0/24  0.0.0.0/0
# 2        0     0 MASQUERADE  all  --  *      !br-b5823ba104e0  10.0.7.0/24  0.0.0.0/0
```

**说明**：
- 第 1 条规则：10.0.0.0/24 网段访问外部网络时，进行 MASQUERADE（源地址转换）
- 第 2 条规则：10.0.7.0/24 网段访问外部网络时，进行 MASQUERADE（源地址转换）
- **问题**：当 10.0.0.12 访问 10.0.7.41 时，会被第 1 条规则匹配，源 IP 被转换为 10.0.7.1

##### 步骤 2：添加 RETURN 规则（防止特定网段间的 NAT）

```bash
# 在 MASQUERADE 规则之前插入 RETURN 规则
sudo iptables -t nat -I POSTROUTING -s 10.0.0.0/24 -d 10.0.7.0/24 -j RETURN
sudo iptables -t raw -F
# 验证规则已添加
sudo iptables -t nat -L POSTROUTING -n -v --line-numbers

# 输出示例（修复后）：
# Chain POSTROUTING (policy ACCEPT)
# num   pkts bytes target     prot opt in     out     source               destination
# 1        0     0 RETURN     all  --  *      *       10.0.0.0/24          10.0.7.0/24
# 2        0     0 MASQUERADE  all  --  *      !br-81794e30740f  10.0.0.0/24  0.0.0.0/0
# 3        0     0 MASQUERADE  all  --  *      !br-b5823ba104e0  10.0.7.0/24  0.0.0.0/0
```

**规则解释**：
- **RETURN 规则**：当源 IP 为 10.0.0.0/24，目的 IP 为 10.0.7.0/24 时，直接返回，不继续匹配后面的 MASQUERADE 规则
- **结果**：10.0.0.12 访问 10.0.7.41 时，源 IP 保持为 10.0.0.12，不会被转换为 10.0.7.1

 

**从 DNS client 容器测试（10.0.0.12）：**

```bash
# 进入 DNS client 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it client bash

# 测试访问 /private/（现在应该被拒绝）
curl http://10.0.7.41/private/
# 输出：403 Forbidden
# 说明：Nginx 看到的源 IP 是 10.0.0.12（保留了真实 IP），不在 10.0.7.0/24 白名单内

# 测试访问 /public/（应该成功）
curl http://10.0.7.41/public/
# 输出：<h1>Public Content</h1>

exit
```

**查看 Nginx 日志验证源 IP：**

```bash
cd /home/www/docker-man/07.nginx/04.manual-vhost
sudo docker compose exec nginx-rocky-vhost tail -5 /data/server/nginx/logs/access.log

# 输出示例：
# 10.0.0.12 - - [14/Oct/2025:10:30:15 +0000] "GET /public/ HTTP/1.1" 200 24 "-" "curl/7.76.1"
# 10.0.0.12 - - [14/Oct/2025:10:30:20 +0000] "GET /private/ HTTP/1.1" 403 153 "-" "curl/7.76.1"
#  ↑ 注意：源 IP 现在是 10.0.0.12（真实客户端 IP），不再是 10.0.7.1（网关 IP）
```

##### 步骤 4：测试结果对比

| 配置状态 | 访问源 | 真实 IP | Nginx 看到的 IP | /private/ 结果 |
|---------|-------|---------|----------------|---------------|
| **修复前（默认 NAT）** | client (10.0.0.12) | 10.0.0.12 | 10.0.7.1 (网关) | ✅ 200 OK（网关在白名单内） |
| **修复后（添加 RETURN）** | client (10.0.0.12) | 10.0.0.12 | 10.0.0.12 (真实 IP) | ❌ 403 Forbidden（不在白名单内） |
 
  

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
chown nginx:nginx /data/server/nginx/conf/.htpasswd
```

#### 4.2.3 配置身份认证

```bash
cat > /data/server/nginx/conf/conf.d/auth-test.conf <<'EOF'
server {
    listen 80;
    server_name auth.test.com;

    # 公开区域（无需认证）
    location /public/ {
        alias /data/wwwroot/public/;
    }

    # 管理后台（需要认证）
    location /admin/ {
        alias /data/wwwroot/private/;

        auth_basic "Admin Area - Please Login";
        auth_basic_user_file /data/server/nginx/conf/.htpasswd;
    }

    # 结合 IP 白名单和身份认证
    location /secure/ {
        alias /data/wwwroot/internal/;

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

/data/server/nginx/sbin/nginx -s reload
```

#### 4.2.4 测试身份认证

```bash
# 在 Rocky 容器内测试（本机测试，需要添加 Host 头）

# 测试 1：公开区域（无需认证）
curl -H "Host: auth.test.com" http://127.0.0.1/public/
# 输出：<h1>Public Content</h1>

# 测试 2：管理后台（未提供认证，应该 401）
curl -I -H "Host: auth.test.com" http://127.0.0.1/admin/
# 输出：HTTP/1.1 401 Unauthorized
#      WWW-Authenticate: Basic realm="Admin Area - Please Login"

# 测试 3：管理后台（提供正确认证）
curl -u admin:admin123 -H "Host: auth.test.com" http://127.0.0.1/admin/
# 输出：<h1>Private Content</h1>

# 测试 4：管理后台（错误密码）
curl -u admin:wrongpass -H "Host: auth.test.com" http://127.0.0.1/admin/
# 输出：401 Unauthorized

# 测试 5：URL 中嵌入认证信息
curl -H "Host: auth.test.com" http://admin:admin123@127.0.0.1/admin/
# 输出：<h1>Private Content</h1>

# 测试 6：安全区域（需要 IP + 认证）
curl -u admin:admin123 -H "Host: auth.test.com" http://127.0.0.1/secure/
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
        alias /data/wwwroot/public/;
        access_log /data/server/nginx/logs/api_access.log basic;
    }

    # 位置 2：使用 JSON 格式
    location /json/ {
        alias /data/wwwroot/public/;
        access_log /data/server/nginx/logs/json_access.log json;
    }

    # 位置 3：性能监控
    location /monitor/ {
        alias /data/wwwroot/public/;
        access_log /data/server/nginx/logs/performance.log performance;
    }

    # 位置 4：不记录日志
    location /health {
        access_log off;
        return 200 "OK\n";
    }

    # 位置 5：条件日志（仅记录 4xx/5xx 错误）
    location /errors/ {
        alias /data/wwwroot/public/;
        access_log /data/server/nginx/logs/error_only.log detailed if=$loggable;
    }
}

# 定义条件变量
map $status $loggable {
    ~^[45]  1;
    default 0;
}
EOF

/data/server/nginx/sbin/nginx -s reload

exit
```

#### 5.1.3 配置 DNS（添加测试域名 log.test.com）

```bash
# 进入 DNS master 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it dns-master bash

# 配置 log.test.com 域名（指向 Rocky 容器）
setup-dns-master.sh --domain log.test.com --web-ip 10.0.7.41 \
                    --master-ip 10.0.0.13 --slave-ip 10.0.0.15

exit

# 配置 DNS slave 同步
sudo docker compose exec -it dns-slave bash

setup-dns-slave.sh --domain log.test.com --master-ip 10.0.0.13

exit
```

#### 5.1.4 测试日志记录（在 client 容器中）

**⚠️ 重要**：所有测试在 DNS client 容器中完成，直接使用域名访问。

```bash
# 进入 DNS client 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it client bash

# 生成测试请求（使用域名直接访问）
curl http://log.test.com/api/
curl http://log.test.com/json/
curl http://log.test.com/monitor/
curl http://log.test.com/health

# 测试条件日志（/errors/ 仅记录 4xx/5xx 错误）
curl http://log.test.com/errors/            # 200 成功，不应记录
curl http://log.test.com/errors/not-exist   # 404 错误，应该记录

# 验证 DNS 解析
nslookup log.test.com
# 输出：
# Server:         10.0.0.13
# Address:        10.0.0.13#53
#
# Name:   log.test.com
# Address: 10.0.7.41

exit
```

**查看日志（退出 client 容器，进入 Rocky 容器）：**

```bash
# 进入 Rocky 容器查看日志
cd /home/www/docker-man/07.nginx/04.manual-vhost
sudo docker compose exec -it nginx-rocky-vhost bash

# 查看基本格式日志
tail -1 /data/server/nginx/logs/api_access.log
# 输出：10.0.0.12 [12/Oct/2025:10:30:15 +0000] "GET /api/ HTTP/1.1" 200 25 "curl/7.76.1"

# 查看 JSON 格式日志（需要先安装 jq）
yum install -y jq
tail -1 /data/server/nginx/logs/json_access.log | jq .
# 输出：
# {
#   "timestamp": "2025-10-12T10:30:20+00:00",
#   "client_ip": "10.0.0.12",
#   "request": "GET /json/ HTTP/1.1",
#   "status": 200,
#   "bytes_sent": 25,
#   "request_time": 0.001,
#   "user_agent": "curl/7.76.1",
#   "referer": "",
#   "host": "log.test.com"
# }

# 查看性能日志
tail -1 /data/server/nginx/logs/performance.log
# 输出：10.0.0.12 - 0.001 - - [12/Oct/2025:10:30:25 +0000] "GET /monitor/ HTTP/1.1" 200 25

# 验证健康检查不记录日志
grep health /data/server/nginx/logs/*.log
# 输出：（无结果）

# 查看条件日志（仅记录 4xx/5xx 错误）
tail -5 /data/server/nginx/logs/error_only.log
# 输出示例：
# 10.0.0.12 - - [12/Oct/2025:10:30:38 +0000] "GET /errors/not-exist HTTP/1.1" 404 153 "-" "curl/7.76.1" 0.000 -
#  ↑ 注意：只记录了 404 错误请求，200 成功请求（/errors/）没有被记录

# 验证 200 成功请求确实没有被记录到 error_only.log
grep "GET /errors/ " /data/server/nginx/logs/error_only.log
# 输出：（无结果，说明 200 请求没有被记录）

# 但可以在详细日志中看到所有请求
grep "GET /errors/" /data/server/nginx/logs/detailed_access.log
# 输出示例：
# 10.0.0.12 - - [12/Oct/2025:10:30:35 +0000] "GET /errors/ HTTP/1.1" 200 25 "-" "curl/7.76.1" 0.000 -
# 10.0.0.12 - - [12/Oct/2025:10:30:38 +0000] "GET /errors/not-exist HTTP/1.1" 404 153 "-" "curl/7.76.1" 0.000 -

# 查看详细访问日志（包含所有请求）
tail -10 /data/server/nginx/logs/detailed_access.log
# 输出示例：
# 10.0.0.12 - - [12/Oct/2025:10:30:15 +0000] "GET /api/ HTTP/1.1" 200 25 "-" "curl/7.76.1" 0.000 -
# 10.0.0.12 - - [12/Oct/2025:10:30:20 +0000] "GET /json/ HTTP/1.1" 200 25 "-" "curl/7.76.1" 0.001 -
# 10.0.0.12 - - [12/Oct/2025:10:30:25 +0000] "GET /monitor/ HTTP/1.1" 200 25 "-" "curl/7.76.1" 0.001 -
# 10.0.0.12 - - [12/Oct/2025:10:30:28 +0000] "GET /health HTTP/1.1" 200 3 "-" "curl/7.76.1" 0.000 -
# 10.0.0.12 - - [12/Oct/2025:10:30:35 +0000] "GET /errors/ HTTP/1.1" 200 25 "-" "curl/7.76.1" 0.000 -
# 10.0.0.12 - - [12/Oct/2025:10:30:38 +0000] "GET /errors/not-exist HTTP/1.1" 404 153 "-" "curl/7.76.1" 0.000 -

exit
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

/data/server/nginx/sbin/nginx -s reload
```

#### 6.1.2 配置 DNS（添加测试域名 status.test.com）

```bash
# 进入 DNS master 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it dns-master bash

# 配置 status.test.com 域名（指向 Rocky 容器）
setup-dns-master.sh --domain status.test.com --web-ip 10.0.7.41 \
                    --master-ip 10.0.0.13 --slave-ip 10.0.0.15

exit

# 配置 DNS slave 同步
sudo docker compose exec -it dns-slave bash

setup-dns-slave.sh --domain status.test.com --master-ip 10.0.0.13

exit
```

#### 6.1.3 访问状态页（在 client 容器中）

**⚠️ 重要**：所有测试在 DNS client 容器中完成，直接使用域名访问。

```bash
# 进入 DNS client 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it client bash

# 访问状态页（使用域名直接访问）
curl http://status.test.com/nginx-status

# 输出：
# Active connections: 1
# server accepts handled requests
#  125 125 320
# Reading: 0 Writing: 1 Waiting: 0

# 测试健康检查端点
curl http://status.test.com/health
# 输出：healthy

# 验证 DNS 解析
nslookup status.test.com
# 输出：
# Server:         10.0.0.13
# Address:        10.0.0.13#53
#
# Name:   status.test.com
# Address: 10.0.7.41

exit
```

#### 6.1.4 状态指标解读

| 指标 | 说明 | 正常值 |
|------|------|--------|
| **Active connections** | 当前活动连接数 | < worker_connections |
| **accepts** | 累计接受的连接数 | 持续增长 |
| **handled** | 累计处理的连接数 | = accepts |
| **requests** | 累计处理的请求数 | ≥ handled |
| **Reading** | 正在读取请求头的连接数 | 较小值 |
| **Writing** | 正在发送响应的连接数 | 中等值 |
| **Waiting** | 空闲 keepalive 连接数 | 较大值 |

#### 6.1.5 监控脚本（在 Rocky 容器中）

**说明**：监控脚本在 Rocky 容器内运行，本地访问状态页。

```bash
# 进入 Rocky 容器
cd /home/www/docker-man/07.nginx/04.manual-vhost
sudo docker compose exec -it nginx-rocky-vhost bash

# 创建监控脚本
cat > /usr/local/bin/nginx-monitor.sh <<'EOF'
#!/bin/bash

while true; do
    echo "=== Nginx Status at $(date) ==="
    curl -s -H "Host: status.test.com" http://127.0.0.1/nginx-status | grep -v "^$"
    echo ""
    sleep 5
done
EOF

chmod +x /usr/local/bin/nginx-monitor.sh

# 运行监控（按 Ctrl+C 停止）
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
mkdir -p /data/wwwroot/{website,blog,api,admin}

# 创建测试文件
echo "<h1>Company Website</h1>" > /data/wwwroot/website/index.html
echo "<h1>Company Blog</h1>" > /data/wwwroot/blog/index.html
echo '{"status":"ok"}' > /data/wwwroot/api/index.json
echo "<h1>Admin Dashboard</h1>" > /data/wwwroot/admin/index.html

# 创建认证文件
htpasswd -bc /data/server/nginx/conf/.admin-passwd admin admin@2025

# 步骤 1：在 nginx.conf 的 http 块中添加限流配置
# 编辑 nginx.conf，在 http 块中添加（在 http 块的最后，关闭 } 之前）
sed -i '/^http {/a \    # API 限流配置（必须在 http 块中）\n    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;' /data/server/nginx/conf/nginx.conf

# 步骤 2：配置虚拟主机
cat > /data/server/nginx/conf/conf.d/enterprise.conf <<'EOF'
# 官网
server {
    listen 80;
    server_name www.company.com company.com;
    root /data/wwwroot/website;
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
    root /data/wwwroot/blog;
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
    root /data/wwwroot/api;

    access_log /data/server/nginx/logs/api_access.log json;

    location / {
        # 使用在 http 块中定义的限流 zone
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
    root /data/wwwroot/admin;
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

/data/server/nginx/sbin/nginx -s reload
```

#### 7.1.3 配置 DNS（添加测试域名）

**说明**：为企业域名配置 DNS 解析，使用 DNS 服务器进行域名解析测试。

```bash
# 退出 Rocky 容器
exit

# 进入 DNS master 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it dns-master bash

# 配置所有 company.com 域名（指向 Rocky 容器 10.0.7.41）
# 推荐：使用长选项（参数含义明确）
setup-dns-master.sh --domain company.com --web-ip 10.0.7.41 \
                    --master-ip 10.0.0.13 --slave-ip 10.0.0.15

# 或者：位置参数（快速输入）
# setup-dns-master.sh company.com 10.0.7.41 10.0.0.13 10.0.0.15

exit

# 配置 DNS slave 同步
sudo docker compose exec -it dns-slave bash

# 推荐：使用长选项
setup-dns-slave.sh --domain company.com --master-ip 10.0.0.13

# 或者：位置参数
# setup-dns-slave.sh company.com 10.0.0.13

exit
```

**⚠️ 说明**：
- 配置一次 `company.com` 即可，DNS 服务器会自动解析所有子域名：
  - `www.company.com` → 10.0.7.41
  - `blog.company.com` → 10.0.7.41
  - `api.company.com` → 10.0.7.41
  - `admin.company.com` → 10.0.7.41
- 所有子域名都指向同一个 IP（10.0.7.41），Nginx 通过 `server_name` 区分不同站点

---

#### 7.1.4 测试企业配置（在 client 容器中）

**⚠️ 重要**：所有测试在 DNS client 容器中完成，直接使用域名访问。

```bash
# 进入 DNS client 容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns
sudo docker compose exec -it client bash

# 验证 DNS 解析（所有子域名都应该解析到 10.0.7.41）
nslookup www.company.com
nslookup blog.company.com
nslookup api.company.com
nslookup admin.company.com
# 输出示例：
# Server:         10.0.0.13
# Address:        10.0.0.13#53
#
# Name:   www.company.com
# Address: 10.0.7.41

# 测试官网（使用域名直接访问）
curl http://www.company.com
# 输出：<h1>Company Website</h1>

# 测试不带 www 的官网
curl http://company.com
# 输出：<h1>Company Website</h1>

# 测试博客
curl http://blog.company.com
# 输出：<h1>Company Blog</h1>

# 测试 API
curl http://api.company.com/index.json
# 输出：{"status":"ok"}

# 测试 API 限流（快速发送多个请求）
for i in {1..25}; do
    curl -s http://api.company.com/index.json
    echo " - Request $i"
done
# 输出示例：
# {"status":"ok"} - Request 1
# ...
# {"status":"ok"} - Request 20
# <html>503 Service Temporarily Unavailable</html> - Request 21
#  ↑ 超过限流阈值（rate=10r/s, burst=20）后被拒绝

# 测试管理后台（未认证，应该 401）
curl -I http://admin.company.com
# 输出：
# HTTP/1.1 401 Unauthorized
# WWW-Authenticate: Basic realm="Admin Login Required"

# 测试管理后台（提供正确认证）
curl -u admin:admin@2025 http://admin.company.com
# 输出：<h1>Admin Dashboard</h1>

# 测试管理后台状态页（需要认证）
curl -u admin:admin@2025 http://admin.company.com/status
# 输出：
# Active connections: 2
# server accepts handled requests
#  150 150 380
# Reading: 0 Writing: 1 Waiting: 1

# 测试错误密码
curl -u admin:wrongpass http://admin.company.com
# 输出：401 Unauthorized

exit
```

**测试结果总结**：

| 域名 | 认证 | 限流 | 预期结果 |
|------|------|------|---------|
| **www.company.com** | 无需 | 无 | ✅ 200 OK（官网首页） |
| **blog.company.com** | 无需 | 无 | ✅ 200 OK（博客首页） |
| **api.company.com** | 无需 | 10r/s + burst 20 | ✅ 正常请求通过，超限 503 |
| **admin.company.com** | 需要（admin:admin@2025） | 无 | ✅ 未认证 401，认证后 200 OK |
| **admin.company.com/status** | 需要 | 无 | ✅ 显示 Nginx 状态信息 |

**查看访问日志（退出 client 容器，进入 Rocky 容器）**：

```bash
# 进入 Rocky 容器查看日志
cd /home/www/docker-man/07.nginx/04.manual-vhost
sudo docker compose exec -it nginx-rocky-vhost bash

# 查看官网访问日志
tail -5 /data/server/nginx/logs/website_access.log
# 输出示例：
# 10.0.0.12 - - [14/Oct/2025:12:00:15 +0000] "GET / HTTP/1.1" 200 26 "-" "curl/7.76.1" 0.000 -

# 查看博客访问日志
tail -5 /data/server/nginx/logs/blog_access.log
# 输出示例：
# 10.0.0.12 - - [14/Oct/2025:12:00:20 +0000] "GET / HTTP/1.1" 200 23 "-" "curl/7.76.1" 0.000 -

# 查看 API 访问日志（JSON 格式）
yum install -y jq
tail -5 /data/server/nginx/logs/api_access.log | jq .
# 输出示例：
# {
#   "timestamp": "2025-10-14T12:00:25+00:00",
#   "client_ip": "10.0.0.12",
#   "request": "GET /index.json HTTP/1.1",
#   "status": 200,
#   "bytes_sent": 16,
#   "request_time": 0.001,
#   "user_agent": "curl/7.76.1",
#   "referer": "",
#   "host": "api.company.com"
# }

# 查看管理后台访问日志
tail -5 /data/server/nginx/logs/admin_access.log
# 输出示例：
# 10.0.0.12 - - [14/Oct/2025:12:00:30 +0000] "GET / HTTP/1.1" 401 195 "-" "curl/7.76.1" 0.000 -
# 10.0.0.12 - admin [14/Oct/2025:12:00:35 +0000] "GET / HTTP/1.1" 200 25 "-" "curl/7.76.1" 0.000 -
# 10.0.0.12 - admin [14/Oct/2025:12:00:40 +0000] "GET /status HTTP/1.1" 200 97 "-" "curl/7.76.1" 0.000 -
#  ↑ 注意：认证成功后，日志中显示用户名 "admin"

# 查看错误日志（如果有限流拒绝）
tail -10 /data/server/nginx/logs/website_error.log
# 可能的输出：
# 2025/10/14 12:00:28 [error] 123#0: *456 limiting requests, excess: 20.500 by zone "api_limit", client: 10.0.0.12, server: api.company.com, request: "GET /index.json HTTP/1.1", host: "api.company.com"

exit
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
/data/server/nginx/sbin/nginx -T | grep -A 5 "location /"

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
ls -l /data/wwwroot/web1/test.html

# 解决：
chmod 644 /data/wwwroot/web1/test.html
chmod 755 /data/wwwroot/web1
```

**原因 2：deny 规则拒绝**

```bash
# 检查配置
/data/server/nginx/sbin/nginx -T | grep -A 10 "location"

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
/data/server/nginx/sbin/nginx -T | grep -B 5 "server_name"

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
sudo docker compose down

# 2. 删除 Volume（可选）
sudo docker compose down --volumes

# 3. 完全清理（包括镜像）
sudo docker compose down --volumes --rmi all
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
