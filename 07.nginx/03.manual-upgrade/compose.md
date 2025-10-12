# Docker Compose Nginx 平滑升级与模块扩展实践指南

## 📚 第一部分：基础知识

### 1.1 什么是 Nginx 平滑升级

Nginx 平滑升级（Graceful Upgrade）是一种**在不中断服务的情况下更新 Nginx 版本**的技术。

#### 1.1.1 平滑升级的特点

| 特性 | 说明 | 优势 |
|------|------|------|
| **零停机** | 升级过程中服务不中断 | 用户无感知 |
| **新旧共存** | 新旧版本进程同时运行 | 可随时回退 |
| **优雅关闭** | 旧连接处理完才退出 | 无连接丢失 |
| **信号控制** | 通过信号精确控制进程 | 操作可控 |

#### 1.1.2 为什么需要平滑升级

| 场景 | 说明 |
|------|------|
| **版本更新** | 安全补丁、性能改进、新功能 |
| **模块添加** | 需要新增第三方模块 |
| **配置变更** | 重大配置修改需要重启 |
| **性能优化** | 编译参数调整优化 |

---

### 1.2 Nginx 信号控制机制

#### 1.2.1 关键信号详解

| 信号 | 作用对象 | 功能 | 使用场景 |
|------|---------|------|---------|
| **USR2** | master | 启动新版本 master 进程 | 开始平滑升级 |
| **WINCH** | master | 优雅关闭所有 worker 进程 | 停止旧 worker |
| **QUIT** | master | 优雅退出 master 进程 | 完成升级 |
| **HUP** | master | 重新加载配置并重启 worker | 版本回退 |
| **TERM/INT** | master | 快速停止（强制） | 紧急停止 |

#### 1.2.2 平滑升级流程图

```
初始状态：
┌────────────────────────────────────┐
│ 旧 Master (PID 26077)              │
│  ├─ Worker 1 (PID 26078)           │
│  └─ Worker 2 (PID 26079)           │
└────────────────────────────────────┘

↓ kill -USR2 26077 (启动新版本)

新旧共存：
┌────────────────────────────────────┐
│ 旧 Master (PID 26077)              │
│  ├─ Worker 1 (PID 26078) ✓ 运行   │
│  └─ Worker 2 (PID 26079) ✓ 运行   │
└────────────────────────────────────┘
┌────────────────────────────────────┐
│ 新 Master (PID 31819)              │
│  ├─ Worker 1 (PID 31820) ✓ 运行   │
│  └─ Worker 2 (PID 31821) ✓ 运行   │
└────────────────────────────────────┘

↓ kill -WINCH 26077 (关闭旧 worker)

旧 worker 退出：
┌────────────────────────────────────┐
│ 旧 Master (PID 26077) 待退出       │
└────────────────────────────────────┘
┌────────────────────────────────────┐
│ 新 Master (PID 31819)              │
│  ├─ Worker 1 (PID 31820) ✓ 运行   │
│  └─ Worker 2 (PID 31821) ✓ 运行   │
└────────────────────────────────────┘

↓ kill -QUIT 26077 (退出旧 master)

完成升级：
┌────────────────────────────────────┐
│ 新 Master (PID 31819)              │
│  ├─ Worker 1 (PID 31820) ✓ 运行   │
│  └─ Worker 2 (PID 31821) ✓ 运行   │
└────────────────────────────────────┘
```

---

### 1.3 Nginx 模块扩展

#### 1.3.1 模块类型

| 类型 | 说明 | 编译参数 | 示例 |
|------|------|---------|------|
| **静态模块** | 编译时集成，启动即加载 | `--with-xxx` | `--with-http_ssl_module` |
| **动态模块** | 编译为 .so，按需加载 | `--with-xxx=dynamic` | `--with-stream=dynamic` |
| **第三方模块** | 外部开发的扩展 | `--add-module=path` | `--add-module=/path/to/echo` |

#### 1.3.2 常见第三方模块

| 模块 | 功能 | 适用场景 |
|------|------|---------|
| **echo-nginx-module** | 输出变量和调试信息 | 开发调试、简单接口 |
| **nginx-module-vts** | 流量监控统计 | 性能监控 |
| **ngx_http_geoip2_module** | IP 地理位置查询 | 地域访问控制 |
| **ngx_cache_purge** | 缓存清理 | CDN 缓存管理 |

---

## 🌐 第二部分：环境架构

### 2.1 网络拓扑

```
Docker Bridge 网络：nginx-net (10.0.7.0/24)
├── 10.0.7.1   - 网关（Docker 网桥）
├── 10.0.7.30  - Ubuntu 升级演示（nginx-ubuntu-upgrade）
│   └── 端口：8030:80
└── 10.0.7.31  - Rocky 模块扩展（nginx-rocky-module）
    └── 端口：8031:80
```

### 2.2 Docker Compose 配置说明

**关键配置项**：

| 配置 | 说明 | 必要性 |
|------|------|--------|
| `privileged: true` | 允许发送系统信号 | ✅ 平滑升级必需 |
| `tty: true` | 分配伪终端 | ✅ 交互式操作 |
| `stdin_open: true` | 保持 stdin 开启 | ✅ 交互式操作 |
| `tail -f /dev/null` | 保持容器运行 | ✅ 手动操作环境 |

---

## 🚀 第三部分：平滑升级实践（Ubuntu 容器）

### 3.1 环境启动

```bash
# 1. 进入项目目录
cd /home/www/docker-man/07.nginx/03.manual-upgrade

# 2. 启动服务
docker compose up -d

# 3. 检查服务状态
docker compose ps

# 4. 进入 Ubuntu 升级容器
docker compose exec -it nginx-ubuntu-upgrade bash
```

---

### 3.2 准备旧版本环境

#### 3.2.1 验证预装的 Nginx

```bash
# 1. 检查版本（容器已预装 Nginx）
nginx -v
# 输出：nginx version: nginx/1.24.0

# 2. 启动 Nginx
#nginx
/data/server/nginx/sbin/nginx

# 3. 检查进程
ps auxf | grep nginx
# 输出：
# root     26077  ... nginx: master process /data/server/nginx/sbin/nginx
# nobody   26078  ... nginx: worker process
# nobody   26079  ... nginx: worker process

# 4. 测试访问
curl -I 127.0.0.1
# 输出：Server: nginx/1.24.0

# 5. 查看配置路径
ls -la /data/server/nginx/conf/
ls -la /data/server/nginx/logs/
```

#### 3.2.2 准备测试文件（模拟长连接下载）

```bash
# 创建 100MB 测试文件
dd if=/dev/zero of=/data/server/nginx/html/test.img bs=1M count=100

# 查看文件
ls -lh /data/server/nginx/html/test.img
# 输出：-rw-r--r-- 1 root root 100M ...
```

---

### 3.3 准备新版本（1.25.0 源码编译）

#### 3.3.1 下载并编译新版本

```bash
# 1. 安装编译依赖
apt install -y build-essential libpcre3 libpcre3-dev zlib1g zlib1g-dev \
  libssl-dev libgd-dev libgeoip-dev libxml2-dev libxslt1-dev

# 2. 下载源码
mkdir -p /data/softs && cd /data/softs
wget http://nginx.org/download/nginx-1.25.0.tar.gz
tar xf nginx-1.25.0.tar.gz
cd nginx-1.25.0

# 3. 获取旧版本编译参数（关键步骤！）
nginx -V

# 输出示例：
# configure arguments: --prefix=/data/server/nginx --conf-path=/data/server/nginx/conf/nginx.conf ...

# 4. 使用相同参数编译新版本（复制上面的 configure arguments）
./configure \
  --prefix=/data/server/nginx \
  --conf-path=/data/server/nginx/conf/nginx.conf \
  --error-log-path=/data/server/nginx/logs/error.log \
  --http-log-path=/data/server/nginx/logs/access.log \
  --pid-path=/data/server/nginx/run/nginx.pid \
  --lock-path=/data/server/nginx/run/nginx.lock \
  --http-client-body-temp-path=/data/server/nginx/temp/client \
  --http-proxy-temp-path=/data/server/nginx/temp/proxy \
  --http-fastcgi-temp-path=/data/server/nginx/temp/fastcgi \
  --http-uwsgi-temp-path=/data/server/nginx/temp/uwsgi \
  --http-scgi-temp-path=/data/server/nginx/temp/scgi \
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_realip_module \
  --with-http_v2_module \
  --with-http_gzip_static_module \
  --with-threads

# 5. 编译（不要执行 make install）
make

# 编译时长约 2 分钟，耐心等待...

# 6. 确认生成的新可执行文件
ls -lh objs/nginx
# 输出：-rwxr-xr-x 1 root root 6.3M ... objs/nginx

# 7. 检查新版本
./objs/nginx -v
# 输出：nginx version: nginx/1.25.0
```

#### 3.3.2 对比新旧版本

```bash
# 旧版本文件
ls -lh /data/server/nginx/sbin/nginx
# -rwxr-xr-x 1 root root 1.3M ... /data/server/nginx/sbin/nginx

# 新版本文件
ls -lh /data/softs/nginx-1.25.0/objs/nginx
# -rwxr-xr-x 1 root root 6.3M ... objs/nginx

# 版本对比
/data/server/nginx/sbin/nginx -v      # nginx/1.24.0
/data/softs/nginx-1.25.0/objs/nginx -v # nginx/1.25.0
```

---

### 3.4 执行平滑升级

#### 3.4.1 备份旧可执行文件

```bash
# 备份旧版本
mv /data/server/nginx/sbin/nginx /data/server/nginx/sbin/nginx-1.24

# 复制新版本
cp /data/softs/nginx-1.25.0/objs/nginx /data/server/nginx/sbin/
chmod +x /data/server/nginx/sbin/nginx

# 验证切换成功
nginx -v
# 输出：nginx version: nginx/1.25.0


chown -R nginx:nginx /data/server/nginx
```

#### 3.4.2 创建长连接（模拟真实流量）

**打开第二个终端**（在宿主机或另一个容器内）：

```bash
# 限速下载（模拟长时间连接）
wget --limit-rate=100k http://10.0.7.30/test.img

# 下载会持续约 17 分钟（100MB ÷ 100KB/s）
# 保持此下载运行，不要中断
```

#### 3.4.3 启动新版本 Master 进程（信号 USR2）

**在服务器容器内执行**：

```bash
# 1. 查看当前进程
ps auxf | grep nginx
# 输出：
# root     26077  ... nginx: master process /data/server/nginx/sbin/nginx
# nobody   26078  ... nginx: worker process
# nobody   26079  ... nginx: worker process

# 2. 向旧 master 发送 USR2 信号
kill -USR2 26077

# 3. 查看新生成的进程
ps auxf | grep nginx
# 输出：
# root     26077  ... nginx: master process /data/server/nginx/sbin/nginx (旧)
# nobody   26078  ... nginx: worker process (旧)
# nobody   26079  ... nginx: worker process (旧)
# root     31819  ... nginx: master process /data/server/nginx/sbin/nginx (新)
# nobody   31820  ... nginx: worker process (新)
# nobody   31821  ... nginx: worker process (新)

# 4. 查看 PID 文件
ls -l /data/server/nginx/run/nginx.pid*
# -rw-r--r-- 1 root root 6 ... /data/server/nginx/run/nginx.pid       (新 master)
# -rw-r--r-- 1 root root 6 ... /data/server/nginx/run/nginx.pid.oldbin (旧 master)

cat /data/server/nginx/run/nginx.pid       # 31819 (新 master PID)
cat /data/server/nginx/run/nginx.pid.oldbin # 26077 (旧 master PID)

# 5. 此时访问仍然由新旧版本同时
curl -I 127.0.0.1
# 输出：Server
```

**关键点解释**：
- 新旧 master 同时存在
- 旧 worker 继续处理现有连接（如 wget 下载）
- 新 worker 已启动但暂不接收流量
- 服务无中断

#### 3.4.4 关闭旧 Worker 进程（信号 WINCH）

```bash
# 1. 向旧 master 发送 WINCH 信号
kill -WINCH 26077

# 2. 立即查看进程
ps auxf | grep nginx
# 输出：
# root     26077  ... nginx: master process (旧 master 保留)
# www-data 26079  ... nginx: worker process is shutting down (旧 worker 正在关闭)
# root     31819  ... nginx: master process (新 master)
# www-data 31820  ... nginx: worker process (新 worker)
# www-data 31821  ... nginx: worker process (新 worker)

# 3. 此时新请求已由新版本响应
curl -I 127.0.0.1
# 输出：Server: nginx/1.25.0 (新版本！)

# 4. 检查 wget 下载是否还在继续
# 在下载终端查看进度条应该持续增长，说明旧连接未中断
```

**关键观察**：
- 旧 worker 状态显示 `is shutting down`
- 旧 worker 会等待现有连接（wget）完成后才真正退出
- 新请求立即由新 worker 处理
- **零停机切换完成**

#### 3.4.5 等待旧连接结束

**场景 1：主动中断下载（模拟测试）**

```bash
# 在 wget 终端按 Ctrl+C 中断下载

# 回到服务器查看进程
ps auxf | grep nginx
# 输出：
# root     26077  ... nginx: master process (旧 master)
# root     31819  ... nginx: master process (新 master)
# www-data 31820  ... nginx: worker process (新 worker)
# www-data 31821  ... nginx: worker process (新 worker)

# 结果：旧 worker 已全部退出
```

**场景 2：等待下载完成（真实场景）**

```bash
# 让 wget 自然完成下载（约 17 分钟）

# 下载完成后查看进程
ps auxf | grep nginx
# 输出：所有旧 worker 自动退出
```

#### 3.4.6 完成升级（退出旧 Master）

```bash
# 1. 观察一段时间确认业务正常（建议 5-30 分钟）

# 2. 退出旧 master 进程
kill -QUIT 26077

# 3. 查看最终进程
ps auxf | grep nginx
# 输出：
# root     31819  ... nginx: master process (新 master)
# www-data 31820  ... nginx: worker process (新 worker)
# www-data 31821  ... nginx: worker process (新 worker)

# 4. 确认版本
curl -I 127.0.0.1
# 输出：Server: nginx/1.25.0

# ✅ 平滑升级完成！
```

---

### 3.5 平滑回退操作

#### 3.5.1 适用场景

| 场景 | 说明 |
|------|------|
| **新版本 bug** | 发现功能异常、性能下降 |
| **兼容性问题** | 配置不兼容、模块冲突 |
| **业务异常** | 升级后业务指标异常 |

#### 3.5.2 回退前提条件

⚠️ **必须在旧 master 进程未退出前执行回退！**

```bash
# 检查旧 master 是否还存在
ps aux | grep nginx | grep 26077

# 如果已执行 kill -QUIT，则无法回退，只能重新编译旧版本
```

#### 3.5.3 回退操作步骤

**场景重现**（从 USR2 信号后开始）：

```bash
# 1. 确认当前状态（新旧 master 共存）
ps auxf | grep nginx
# root     26077  ... nginx: master process (旧)
# root     31819  ... nginx: master process (新)
# www-data 31820  ... nginx: worker process (新)
# www-data 31821  ... nginx: worker process (新)

# 2. 切换回旧版本可执行文件
mv /data/server/nginx/sbin/nginx /data/server/nginx/sbin/nginx-1.25
mv /data/server/nginx/sbin/nginx-1.24 /data/server/nginx/sbin/nginx

# 3. 验证版本
nginx -v
# 输出：nginx version: nginx/1.24.0

# 4. 拉起旧 master 的 worker 进程（信号 HUP）
kill -HUP 26077

# 5. 查看进程
ps auxf | grep nginx
# 输出：
# root     26077  ... nginx: master process (旧 master)
# www-data 32109  ... nginx: worker process (旧 worker 重新启动)
# www-data 32110  ... nginx: worker process (旧 worker 重新启动)
# root     31819  ... nginx: master process (新 master 仍在)
# www-data 31820  ... nginx: worker process (新 worker 仍在)
# www-data 31821  ... nginx: worker process (新 worker 仍在)

# 6. 此时新请求仍由新版本处理
curl -I 127.0.0.1
# 输出：Server: nginx/1.25.0

# 7. 优雅退出新版本 master（信号 QUIT）
kill -QUIT 31819

# 8. 查看最终进程
ps auxf | grep nginx
# 输出：
# root     26077  ... nginx: master process (旧 master)
# www-data 32109  ... nginx: worker process (旧 worker)
# www-data 32110  ... nginx: worker process (旧 worker)

# 9. 确认版本回退成功
curl -I 127.0.0.1
# 输出：Server: nginx/1.24.0

# ✅ 版本回退完成！
```

---

## 🧩 第四部分：模块扩展实践（Rocky 容器）

### 4.1 环境准备

```bash
# 1. 进入 Rocky 模块容器
docker compose exec -it nginx-rocky-module bash

# 2. 验证预装的 Nginx（已在 Dockerfile 中完成源码安装）
nginx -v

# 3. 启动 Nginx
nginx

# 4. 检查版本和编译参数
nginx -V

# 5. 查看进程状态
ps aux | grep nginx
```

---

### 4.2 扩展 echo 模块

#### 4.2.1 echo 模块简介

**功能**：在 Nginx 中直接输出变量和文本，用于调试和简单接口。

**示例**：
```nginx
location /echo {
    echo "Request URI: $request_uri";
    echo "Client IP: $remote_addr";
}
```

#### 4.2.2 下载 echo 模块

```bash
# 1. 创建工作目录
mkdir -p /data/softs && cd /data/softs

# 2. 下载 Nginx 源码（与当前版本一致）
nginx -v  # 假设显示 nginx/1.24.0

wget http://nginx.org/download/nginx-1.24.0.tar.gz
tar xf nginx-1.24.0.tar.gz

# 3. 下载 echo 模块
wget https://github.com/openresty/echo-nginx-module/archive/refs/tags/v0.63.tar.gz
tar xf v0.63.tar.gz -C /usr/local
```

#### 4.2.3 编译安装 echo 模块

```bash
# 1. 进入源码目录
cd /data/softs/nginx-1.24.0

# 2. 获取原有编译参数并添加 echo 模块
nginx -V 2>&1 | grep "configure arguments:" | \
  sed 's/configure arguments://' > /tmp/nginx_args.txt

# 查看参数
cat /tmp/nginx_args.txt

# 3. 重新编译（添加 --add-module 参数）
./configure $(cat /tmp/nginx_args.txt) \
  --add-module=/usr/local/echo-nginx-module-0.63

# 4. 编译（不执行 make install）
make

# 5. 检查新生成的可执行文件
./objs/nginx -V 2>&1 | grep echo
# 应该能看到 --add-module=/usr/local/echo-nginx-module-0.63
```

#### 4.2.4 替换 Nginx 可执行文件

```bash
# 1. 备份旧版本
mv /data/server/nginx/sbin/nginx /data/server/nginx/sbin/nginx.bak

# 2. 安装新版本
cp objs/nginx /data/server/nginx/sbin/
chmod +x /data/server/nginx/sbin/nginx

# 3. 验证模块
nginx -V 2>&1 | grep echo

# 4. 测试配置
nginx -t
# 输出：syntax is ok, test is successful

# 5. 平滑重载（使用前面学到的方法）
# 使用信号完成平滑升级
kill -USR2 $(cat /data/server/nginx/run/nginx.pid)
kill -WINCH $(cat /data/server/nginx/run/nginx.pid.oldbin)
kill -QUIT $(cat /data/server/nginx/run/nginx.pid.oldbin)
```

#### 4.2.5 配置 echo 模块（使用 conf.d 目录）

```bash
# 1. 创建 conf.d 目录
mkdir -p /data/server/nginx/conf/conf.d

# 2. 创建 echo 模块配置
cat > /data/server/nginx/conf/conf.d/echo.conf <<'EOF'
server {
    listen 8080;              # 使用独立端口
    server_name _;

    location /echo {
        echo "Request URI: $request_uri";
        echo "Client IP: $remote_addr";
        echo "Server Time: $time_local";
        echo "Nginx Version: $nginx_version";
    }

    location /echo-post {
        echo "Method: $request_method";
        echo "Body: $request_body";
        echo_read_request_body;
    }
}
EOF

# 3. 修改主配置文件引入 conf.d 目录
cat >> /data/server/nginx/conf/nginx.conf <<'EOF'

# 引入 conf.d 目录下的所有配置
include /data/server/nginx/conf/conf.d/*.conf;
EOF

# 或手动编辑 nginx.conf，在 http 段的最后添加：
# include /data/server/nginx/conf/conf.d/*.conf;

# 4. 测试配置
nginx -t

# 5. 重载配置
nginx -s reload
```

#### 4.2.6 测试 echo 模块

```bash
# 测试 1：基本输出（注意使用 8080 端口）
curl http://127.0.0.1:8080/echo
# 输出：
# Request URI: /echo
# Client IP: 127.0.0.1
# Server Time: 12/Oct/2025:10:30:15 +0000
# Nginx Version: 1.24.0

# 测试 2：带参数
curl http://127.0.0.1:8080/echo?name=test&id=123
# 输出：
# Request URI: /echo?name=test&id=123
# Client IP: 127.0.0.1
# ...

# 测试 3：POST 请求
curl -X POST -d "username=admin&password=123456" http://127.0.0.1:8080/echo-post
# 输出：
# Method: POST
# Body: username=admin&password=123456

# 从宿主机访问（假设容器映射到 8031 端口）
curl http://10.0.7.31:8080/echo

# ✅ echo 模块安装成功！
```

---

### 4.3 扩展 VTS 流量监控模块

#### 4.3.1 VTS 模块简介

**功能**：实时监控 Nginx 流量、连接数、请求统计等。

**监控指标**：
- 每个 server 的流量统计
- 每个 upstream 的后端状态
- 每个 location 的请求统计
- 实时连接数、请求速率

#### 4.3.2 下载并编译 VTS 模块

```bash
# 1. 下载 VTS 模块
cd /data/softs
wget https://github.com/vozlt/nginx-module-vts/archive/refs/tags/v0.2.2.tar.gz
tar xf v0.2.2.tar.gz -C /usr/local/

# 2. 重新编译（添加 VTS 模块）
cd /data/softs/nginx-1.24.0

./configure $(cat /tmp/nginx_args.txt) \
  --add-module=/usr/local/echo-nginx-module-0.63 \
  --add-module=/usr/local/nginx-module-vts-0.2.2

# 3. 编译
make

# 4. 替换可执行文件（使用平滑升级方式）
# 备份当前版本
mv /data/server/nginx/sbin/nginx /data/server/nginx/sbin/nginx.echo

# 复制新版本
cp objs/nginx /data/server/nginx/sbin/
chmod +x /data/server/nginx/sbin/nginx

# 5. 验证模块
nginx -V 2>&1 | grep vts
# 应该能看到 --add-module=/usr/local/nginx-module-vts-0.2.2
```

#### 4.3.3 配置 VTS 模块（使用 conf.d 目录）

```bash
# 1. 修改主配置文件，在 http 段添加 VTS 全局配置
vim /data/server/nginx/conf/nginx.conf

# 在 http 段的开头添加（include 之前）：
http {
    # VTS 全局配置（必须在 http 段）
    vhost_traffic_status_zone;
    vhost_traffic_status_filter_by_host on;

    # 其他配置...
    include /data/server/nginx/conf/conf.d/*.conf;
}

# 2. 创建 VTS 监控 server 配置
cat > /data/server/nginx/conf/conf.d/vts.conf <<'EOF'
server {
    listen 9090;              # 使用独立端口，避免与 echo 冲突
    server_name _;

    # VTS 监控页面
    location /status {
        vhost_traffic_status_display;
        vhost_traffic_status_display_format html;
        access_log off;
    }

    # 测试页面
    location / {
        return 200 "VTS Module Test Page\n";
        add_header Content-Type text/plain;
    }
}
EOF

# 3. 测试配置
nginx -t

# 4. 平滑重载
nginx -s reload
```

**⚠️ 重要说明**：
- `vhost_traffic_status_zone` 必须在 `http` 段，不能在 `server` 段
- VTS 监控使用 **9090 端口**，echo 使用 8080 端口，避免冲突
- 如果 conf.d 已包含，无需重复 include

#### 4.3.4 访问监控页面

**容器内测试**：

```bash
# 访问 VTS 监控页面
curl http://127.0.0.1:9090/status

# 访问 echo 测试页面
curl http://127.0.0.1:8080/echo
```

**在宿主机浏览器访问**：

```
# VTS 监控页面（需要映射 9090 端口）
http://10.0.7.31:9090/status

# echo 测试页面（需要映射 8080 端口）
http://10.0.7.31:8080/echo
```

**应该看到类似以下内容**：

```
Nginx Vhost Traffic Status
==========================

Server Main
  Total: 150 requests
  Request: 10 req/s
  Bandwidth: 1.5 KB/s

Server Zones
  _:9090 (VTS 监控)
    Requests: 50
    1xx: 0, 2xx: 50, 3xx: 0, 4xx: 0, 5xx: 0
    In: 5 KB, Out: 10 KB

  _:8080 (echo 测试)
    Requests: 100
    1xx: 0, 2xx: 100, 3xx: 0, 4xx: 0, 5xx: 0
    In: 10 KB, Out: 20 KB
```

#### 4.3.5 生成测试流量

```bash
# 测试 1：访问 VTS 监控页面
curl http://127.0.0.1:9090/status

# 测试 2：访问 echo 页面（生成流量）
for i in {1..100}; do
  curl -s http://127.0.0.1:8080/echo > /dev/null
  echo "Request $i completed"
done

# 测试 3：并发请求（需要安装 ab）
yum install -y httpd-tools  # Rocky/CentOS
# 或
apt install -y apache2-utils  # Ubuntu

ab -c 10 -n 1000 http://127.0.0.1:8080/echo

# 测试 4：刷新监控页面查看实时数据
curl http://127.0.0.1:9090/status | grep -A 5 "Server Zones"
```

**端口规划总结**：

| 服务 | 端口 | 功能 | 访问地址 |
|------|------|------|---------|
| **默认站点** | 80 | Nginx 默认首页 | `http://127.0.0.1/` |
| **echo 模块** | 8080 | echo 测试接口 | `http://127.0.0.1:8080/echo` |
| **VTS 监控** | 9090 | 流量监控统计 | `http://127.0.0.1:9090/status` |

---

## 📊 第五部分：配置管理进阶

### 5.1 文件描述符限制配置

#### 5.1.1 概念解释

**文件描述符（File Descriptor）**：操作系统用于标识打开文件、网络连接等资源的唯一标识符。

**Nginx 中的文件描述符**：
- 每个客户端连接占用 1 个文件描述符
- 代理到后端时再占用 1 个（共 2 个）
- 打开的日志文件、配置文件等也占用

**并发连接数计算公式**：

```
理论最大并发数 = worker_processes × worker_connections
实际最大并发数 = min(理论最大并发数, worker_rlimit_nofile)
```

#### 5.1.2 查看当前限制

```bash
# 查看系统默认限制
ulimit -n
# 输出：1024 (软限制)

# 查看 Nginx master 进程限制
cat /proc/$(cat /data/server/nginx/run/nginx.pid)/limits | grep files
# 输出：Max open files  1024  524288  files
```

#### 5.1.3 配置文件描述符

**方法 1：修改 Nginx 配置**（推荐）

```bash
# 编辑 /data/server/nginx/conf/nginx.conf
vim /data/server/nginx/conf/nginx.conf

# 在最外层（main 段）添加：
worker_rlimit_nofile 65535;

# 在 events 段添加：
events {
    worker_connections 10240;  # 每个 worker 最大连接数
    multi_accept on;           # 允许一次接受多个连接
}

# 重载配置
nginx -s reload
```

**方法 2：修改系统限制**（容器环境）

```bash
# 修改系统限制
ulimit -n 65535

# 重启 Nginx
nginx -s stop && nginx
```

#### 5.1.4 验证配置

```bash
# 1. 重载后查看 master 进程限制
cat /proc/$(cat /data/server/nginx/run/nginx.pid)/limits | grep files
# 输出：Max open files  65535  65535  files

# 2. 查看 worker 进程限制
ps aux | grep "nginx: worker" | awk '{print $2}' | head -1 | xargs -I {} cat /proc/{}/limits | grep files
# 输出：Max open files  65535  65535  files

# 3. 计算理论并发数
# worker_processes × worker_connections = 2 × 10240 = 20480
```

---

### 5.2 CPU 绑定优化

#### 5.2.1 为什么需要 CPU 绑定

| 问题 | 说明 |
|------|------|
| **CPU 缓存失效** | worker 进程在不同 CPU 间切换导致缓存失效 |
| **上下文切换开销** | 频繁切换增加系统开销 |
| **NUMA 架构影响** | 跨 NUMA 节点访问内存延迟高 |

#### 5.2.2 查看 CPU 信息

```bash
# 查看 CPU 核心数
grep -c processor /proc/cpuinfo
# 输出：2

# 查看详细 CPU 信息
lscpu
# 输出：
# CPU(s):              2
# Thread(s) per core:  1
# Core(s) per socket:  2
```

#### 5.2.3 配置 CPU 绑定

```bash
# 编辑 /data/server/nginx/conf/nginx.conf
vim /data/server/nginx/conf/nginx.conf

# 设置 worker 进程数与 CPU 核心数一致
worker_processes 2;

# 绑定 worker 到 CPU（二进制掩码）
worker_cpu_affinity 01 10;
# 01 = 绑定到 CPU 0
# 10 = 绑定到 CPU 1

# 如果是 4 核 CPU：
# worker_processes 4;
# worker_cpu_affinity 0001 0010 0100 1000;

# 如果是 8 核 CPU：
# worker_processes 8;
# worker_cpu_affinity 00000001 00000010 00000100 00001000 00010000 00100000 01000000 10000000;

# 自动绑定（推荐，Nginx 1.9.10+）
worker_cpu_affinity auto;
```

#### 5.2.4 验证 CPU 绑定

```bash
# 1. 重载配置
nginx -s reload

# 2. 查看进程与 CPU 绑定关系
ps axo pid,cmd,psr | grep nginx
# 输出：
# 12345 nginx: master process  0
# 12346 nginx: worker process  0
# 12347 nginx: worker process  1
#                              ↑ PSR 列显示绑定的 CPU 核心

# 3. 压测观察（进程不应频繁切换 CPU）
# 打开第二个终端执行压测：
ab -c 100 -n 10000 http://127.0.0.1/

# 在服务器终端持续观察：
watch -n 0.5 'ps axo pid,cmd,psr | grep nginx'
# 观察 PSR 列是否稳定在各自的 CPU 核心上
```

---

### 5.3 worker 进程优先级调整

#### 5.3.1 优先级说明

Linux 进程优先级范围：**-20（最高）到 +19（最低）**，默认为 0。

#### 5.3.2 配置优先级

```bash
# 编辑 /data/server/nginx/conf/nginx.conf
vim /data/server/nginx/conf/nginx.conf

# 设置 worker 进程优先级（在 main 段）
worker_priority -10;  # 提高优先级（需要谨慎使用）

# 重载配置
nginx -s reload
```

#### 5.3.3 验证优先级

```bash
# 查看进程优先级（NI 列）
ps axo pid,cmd,ni | grep nginx
# 输出：
# 12345 nginx: master process   0  (master 保持默认)
# 12346 nginx: worker process -10  (worker 提高优先级)
# 12347 nginx: worker process -10
```

**⚠️ 注意事项**：
- 不要设置过高优先级（如 -20），可能影响系统稳定性
- 建议设置在 -5 到 -10 之间
- 仅在高负载场景需要时使用

---

## 🔧 第六部分：故障排除

### 6.1 平滑升级常见问题

#### 问题 1：USR2 信号无效，新 master 未启动

**症状**：
```bash
kill -USR2 <旧master PID>
# 没有新进程生成
```

**原因 1：编译参数差异过大**

```bash
# 检查新旧版本编译参数
/data/server/nginx/sbin/nginx-old -V 2>&1 | grep configure
/data/server/nginx/sbin/nginx -V 2>&1 | grep configure

# 对比差异，确保关键参数一致（尤其是路径相关）
```

**原因 2：跨大版本升级不支持**

```bash
# 例如从 1.18.x 升级到 1.25.x（跨 3 个主版本）
# 建议：逐步升级 1.18 → 1.20 → 1.22 → 1.25
```

**解决方法**：
```bash
# 重新编译，使用完全相同的参数
./configure $(nginx -V 2>&1 | grep "configure arguments:" | sed 's/.*arguments: //')
make
```

---

#### 问题 2：新 worker 启动失败

**症状**：
```bash
ps aux | grep nginx
# 只有新 master，没有新 worker
```

**原因：配置文件语法错误或兼容性问题**

```bash
# 检查错误日志
tail -f /data/server/nginx/logs/error.log

# 常见错误：
# - unknown directive "xxx"（新版本不支持旧指令）
# - invalid parameter "xxx"（参数值变更）
```

**解决方法**：
```bash
# 修复配置文件
vim /data/server/nginx/conf/nginx.conf

# 测试配置
nginx -t

# 如果无法修复，执行回退
kill -HUP <旧master PID>  # 重启旧 worker
kill -QUIT <新master PID>  # 退出新 master
```

---

#### 问题 3：WINCH 信号后旧 worker 不退出

**症状**：
```bash
kill -WINCH <旧master PID>
ps aux | grep nginx
# 旧 worker 仍显示为 running，而非 shutting down
```

**原因：存在长连接或挂起的请求**

```bash
# 检查连接数
ss -antp | grep nginx | wc -l

# 检查是否有 keepalive 连接
ss -antp | grep nginx | grep ESTABLISHED
```

**解决方法**：
```bash
# 方法 1：等待连接自然结束（推荐）
# 观察日志，等待旧 worker 自动退出

# 方法 2：强制关闭（不推荐，会中断连接）
kill -TERM <旧worker PID>

# 方法 3：调整 keepalive 超时
# 在发送 WINCH 前，修改配置：
keepalive_timeout 5;  # 缩短超时时间
nginx -s reload
```

---

### 6.2 模块扩展常见问题

#### 问题 1：编译时找不到模块源码

**错误信息**：
```bash
./configure: error: no /usr/local/echo-nginx-module-0.63/config was found
```

**原因：模块路径错误或未解压**

```bash
# 检查路径是否存在
ls -la /usr/local/echo-nginx-module-0.63/

# 确认 config 文件存在
ls -la /usr/local/echo-nginx-module-0.63/config
```

**解决方法**：
```bash
# 重新解压到正确路径
tar xf v0.63.tar.gz -C /usr/local/
ls -la /usr/local/echo-nginx-module-0.63/
```

---

#### 问题 2：编译成功但模块不生效

**症状**：
```bash
nginx -V 2>&1 | grep echo
# 能看到 --add-module=/usr/local/echo-nginx-module-0.63

# 但使用 echo 指令报错
nginx: [emerg] unknown directive "echo"
```

**原因 1：未替换可执行文件**

```bash
# 检查当前运行的是哪个文件
which nginx
# /usr/local/bin/nginx (软链接到 /data/server/nginx/sbin/nginx)

ls -l /data/server/nginx/sbin/nginx
# 检查修改时间是否是最近编译的
```

**原因 2：平滑升级未完成**

```bash
# 检查是否有新旧两个 master
ps aux | grep nginx

# 如果有两个 master，确保新的已生效
```

**解决方法**：
```bash
# 重新平滑升级
kill -USR2 $(cat /data/server/nginx/run/nginx.pid)
sleep 1
kill -WINCH $(cat /data/server/nginx/run/nginx.pid.oldbin)
sleep 1
kill -QUIT $(cat /data/server/nginx/run/nginx.pid.oldbin)
```

---

#### 问题 3：VTS 模块页面 404

**症状**：
```bash
curl http://127.0.0.1/status
# 404 Not Found
```

**原因 1：配置未生效**

```bash
# 检查配置是否加载
nginx -T | grep vhost_traffic_status

# 如果没有输出，说明配置未加载
```

**原因 2：配置位置错误**

```bash
# vhost_traffic_status_zone 必须在 http 段
# 不能在 server 或 location 段
```

**解决方法**：
```bash
# 正确配置示例
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
http {
    vhost_traffic_status_zone;  # ✅ 正确位置

    server {
        location /status {
            vhost_traffic_status_display;
        }
    }
}
EOF

# 测试并重载
nginx -t && nginx -s reload
```

---

### 6.3 调试技巧

#### 6.3.1 启用 debug 日志

```bash
# 1. 检查 Nginx 是否编译了 debug 模块
nginx -V 2>&1 | grep debug
# 应包含 --with-debug

# 2. 修改配置启用 debug 日志
vim /data/server/nginx/conf/nginx.conf

error_log /data/server/nginx/logs/error.log debug;  # 将 warn 改为 debug

# 3. 重载配置
nginx -s reload

# 4. 查看详细日志
tail -f /data/server/nginx/logs/error.log
```

#### 6.3.2 使用 strace 跟踪进程

```bash
# 跟踪 worker 进程
strace -p <worker PID> -f -e trace=network

# 跟踪 master 进程
strace -p $(cat /data/server/nginx/run/nginx.pid) -f -e trace=signal

# 实时查看系统调用
strace -p <PID> -f -tt -T
```

#### 6.3.3 使用 gdb 调试

```bash
# 安装 gdb
yum install -y gdb  # Rocky/CentOS
apt install -y gdb  # Ubuntu

# 附加到进程
gdb -p $(cat /data/server/nginx/run/nginx.pid)

# 查看线程
(gdb) info threads

# 查看调用栈
(gdb) bt

# 继续运行
(gdb) continue
```

---

## 📋 第七部分：测试检查清单

### 7.1 平滑升级检查清单

- [ ] **准备阶段**
  - [ ] 备份旧版本可执行文件
  - [ ] 编译新版本成功
  - [ ] 确认编译参数一致
  - [ ] 测试配置文件语法

- [ ] **升级阶段**
  - [ ] 发送 USR2 信号成功
  - [ ] 新 master 进程启动
  - [ ] 新 worker 进程启动
  - [ ] 新旧进程共存正常

- [ ] **切换阶段**
  - [ ] 发送 WINCH 信号成功
  - [ ] 旧 worker 显示 shutting down
  - [ ] 新请求由新版本响应
  - [ ] 旧连接继续正常处理

- [ ] **完成阶段**
  - [ ] 旧 worker 全部退出
  - [ ] 业务监控无异常
  - [ ] 退出旧 master 进程
  - [ ] 版本验证成功

- [ ] **回退能力**
  - [ ] 旧版本可执行文件已备份
  - [ ] 熟悉回退操作流程
  - [ ] 测试 HUP 信号回退

---

### 7.2 模块扩展检查清单

- [ ] **编译阶段**
  - [ ] 下载模块源码成功
  - [ ] 解压到正确路径
  - [ ] configure 添加 --add-module 参数
  - [ ] make 编译成功
  - [ ] 验证模块已编译进去

- [ ] **安装阶段**
  - [ ] 备份旧可执行文件
  - [ ] 替换新可执行文件
  - [ ] 使用平滑升级方式重载
  - [ ] 验证模块指令可用

- [ ] **配置阶段**
  - [ ] 添加模块配置
  - [ ] 测试配置语法
  - [ ] 重载配置成功
  - [ ] 功能测试通过

---

### 7.3 性能优化检查清单

- [ ] **文件描述符**
  - [ ] 设置 worker_rlimit_nofile
  - [ ] 设置 worker_connections
  - [ ] 验证进程限制生效
  - [ ] 计算理论并发数

- [ ] **CPU 绑定**
  - [ ] 设置 worker_processes = CPU 核心数
  - [ ] 配置 worker_cpu_affinity
  - [ ] 验证进程绑定到固定 CPU
  - [ ] 压测观察进程稳定性

- [ ] **优先级调整**
  - [ ] 设置 worker_priority
  - [ ] 验证优先级生效
  - [ ] 监控系统资源影响

---

## ❓ 第八部分：常见问题

### Q1: 平滑升级过程中服务会中断吗？

**答**：不会。整个过程中：
1. USR2 信号后，新旧进程共存，服务正常
2. WINCH 信号后，新请求由新进程处理，旧连接由旧进程处理，无中断
3. 旧连接处理完后，旧 worker 自动退出

---

### Q2: 什么情况下无法回退？

**答**：
- 已执行 `kill -QUIT` 退出旧 master 进程
- 旧版本可执行文件已删除

**避免方法**：
- 保留旧 master 进程观察一段时间（如 30 分钟）
- 始终备份旧版本可执行文件

---

### Q3: 添加模块一定要重新编译吗？

**答**：取决于模块类型：
- **动态模块**（.so 文件）：可以直接加载，无需重新编译 Nginx
- **静态模块**：必须重新编译 Nginx

**示例**（动态模块）：
```nginx
load_module modules/ngx_stream_module.so;
```

---

### Q4: worker_rlimit_nofile 设置多大合适？

**答**：根据实际需求计算：

```
worker_rlimit_nofile = worker_connections × 2 + 1024（预留）

示例：
worker_connections = 10240
worker_rlimit_nofile = 10240 × 2 + 1024 = 21504（可设置为 30000）
```

---

### Q5: CPU 绑定对性能提升有多大？

**答**：根据场景不同：
- **高并发场景**：性能提升 5-15%
- **低并发场景**：提升不明显（1-3%）
- **NUMA 架构服务器**：提升可达 20-30%

**建议**：生产环境开启，开发环境可不开启。

---

## 🎓 第九部分：学习总结

### 9.1 核心知识点

1. **平滑升级流程**：
   - USR2 启动新 master → WINCH 关闭旧 worker → QUIT 退出旧 master
   - 新旧进程共存机制
   - 长连接不中断原理

2. **版本回退流程**：
   - 切换可执行文件 → HUP 重启旧 worker → QUIT 退出新 master
   - 必须在旧 master 未退出前执行

3. **模块扩展方法**：
   - 下载模块源码 → 重新编译（添加 --add-module）→ 替换可执行文件 → 平滑重载

4. **性能优化配置**：
   - 文件描述符限制（worker_rlimit_nofile）
   - CPU 绑定（worker_cpu_affinity）
   - 进程优先级（worker_priority）

### 9.2 实战能力

通过本环境的学习，你应该能够：

✅ 独立完成 Nginx 版本的平滑升级和回退
✅ 为 Nginx 添加第三方模块（echo, VTS）
✅ 配置和优化 Nginx 性能参数
✅ 使用信号精确控制 Nginx 进程
✅ 排查平滑升级和模块扩展的常见问题
✅ 理解 Nginx 多进程模型和资源限制

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

- **Nginx 信号文档**: https://nginx.org/en/docs/control.html
- **Nginx 平滑升级文档**: https://nginx.org/en/docs/control.html#upgrade
- **echo 模块文档**: https://github.com/openresty/echo-nginx-module
- **VTS 模块文档**: https://github.com/vozlt/nginx-module-vts
- **Nginx 编译参数**: https://nginx.org/en/docs/configure.html

---

**完成时间**: 2025-10-12
**文档版本**: v1.0
**适用场景**: Nginx 版本升级、模块扩展、性能优化
