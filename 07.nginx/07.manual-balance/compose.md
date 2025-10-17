# sudo docker compose Nginx 负载均衡完整实践指南

## 📚 第一部分:负载均衡基础知识

### 1.1 负载均衡简介

**什么是负载均衡?**

负载均衡是一种分布式计算技术,用于将网络流量和用户请求分散到多台服务器上,以此来提高网络服务的可用性和可靠性。它通过优化资源使用、最大化吞吐量以及最小化响应时间,增强了网络、服务器和数据中心的伸缩性和灵活性。

### 1.2 Nginx 负载均衡工作原理

**反向代理模式实现**:
- 客户端发送请求到 Nginx 服务器
- Nginx 根据预设的负载均衡策略将请求转发给后端服务器
- 后端服务器处理请求并返回响应给 Nginx
- Nginx 将响应返回给客户端

### 1.3 负载均衡工作特点

| 特点 | 说明 |
|------|------|
| **提高可用性** | 通过将请求分散到多个服务器,即使部分服务器出现故障,整个系统仍然可以继续提供服务 |
| **增强性能** | 负载均衡可以提高系统处理大量并发请求的能力,从而提升整体性能 |
| **故障转移** | 当一台服务器发生故障时,负载均衡器可以自动将流量转移到其他健康的服务器上,以避免服务中断 |
| **降低延迟** | 通过选择最佳的服务器来处理请求,减少数据传输的延迟 |
| **资源优化** | 合理分配请求到各个服务器,避免某些服务器过载而其他服务器空闲,优化资源使用 |

---

## 🌐 第二部分:网络架构与环境说明

### 2.1 网络拓扑

```
Docker Bridge 网络:nginx-net (10.0.7.0/24)
├── 10.0.7.1   - 网关（Docker 网桥）
├── 10.0.7.70  - Nginx 负载均衡器（nginx-lb）
├── 10.0.7.71  - Web 服务器 1（nginx-web-1, Rocky）
├── 10.0.7.72  - Web 服务器 2（nginx-web-2, Ubuntu）
├── 10.0.7.73  - Web 服务器 3（nginx-web-3, Rocky, 备用）
├── 10.0.7.76  - MySQL 服务器（mysql-server, MySQL 8.0）
└── 10.0.7.77  - Redis 服务器（redis-server, Redis 7.0）
```

### 2.2 服务说明

| 服务名 | IP地址 | 端口映射 | 镜像/系统 | 角色 |
|--------|--------|----------|----------|------|
| nginx-lb | 10.0.7.70 | 8070:80, 3306:3306, 6379:6379, 9000:9000 | Ubuntu | 负载均衡器 + 四层代理 |
| nginx-web-1 | 10.0.7.71 | 8071:80 | Rocky | 后端 Web 服务器 |
| nginx-web-2 | 10.0.7.72 | 8072:80 | Ubuntu | 后端 Web 服务器 |
| nginx-web-3 | 10.0.7.73 | 8073:80 | Rocky | 备用 Web 服务器 |
| mysql-server | 10.0.7.76 | 3307:3306 | MySQL 8.0 | MySQL 数据库服务器 |
| redis-server | 10.0.7.77 | 6380:6379 | Redis 7.0 | Redis 缓存服务器 |

---

## 🚀 第三部分:环境启动

### 3.1 启动所有服务

```bash
# 1. 进入项目目录
cd /home/www/docker-man/07.nginx/07.manual-balance

# 2. 启动所有容器
sudo docker compose up -d

# 3. 检查容器状态
sudo docker compose ps

# 4. 查看网络配置
docker network inspect 07manual-balance_nginx-net
```

---

## ⚖️ 第四部分:负载均衡核心配置

### 4.1 upstream 核心指令

#### 4.1.1 upstream 基础语法

```nginx
upstream name {
    server address [parameters];
}
# 定义一个后端服务器组,可以包含多台服务器
# 定义好后在 proxy_pass 指令中引用
# 作用域:http
```

#### 4.1.2 server 指令详解

```nginx
server address [parameters];
# 在 upstream 中定义一个具体的后端服务器
# 作用域:upstream

# address 指定后端服务器,可以是:
# - IP地址:端口
# - 主机名:端口
# - Unix Socket
```

#### 4.1.3 server 参数详解

| 参数 | 说明 | 默认值 |
|------|------|--------|
| **weight=number** | 指定该 server 的权重 | 1 |
| **max_conns=number** | 该 Server 的最大活动连接数,达到后将不再给该 Server 发送请求<br>可以保持的连接数 = 代理服务器的进程数乘以max_conns | 0（不限制） |
| **max_fails=number** | 后端服务器的下线条件,后端服务器连续进行检测多少次失败,而后标记为不可用<br>当客户端访问时,才会利用TCP触发对探测后端服务器健康性检查,而非周期性的探测 | 1 |
| **fail_timeout=time** | 后端服务器的上线条件,后端服务器连续进行检测多少次成功,而后标记为可用 | 10s |
| **backup** | 标记该 Server 为备用,当所有后端服务器不可用时,才使用此服务器 | - |
| **down** | 标记该 Server 临时不可用,可用于平滑下线后端服务器<br>新请求不再调度到此服务器,原有连接不受影响 | - |

### 4.2 负载均衡调度算法

#### 4.2.1 调度算法配置属性

| 算法 | 说明 | 作用域 |
|------|------|--------|
| **默认（轮询）** | 按顺序逐一分配到不同的后端服务器 | upstream |
| **ip_hash** | 源地址hash调度方法,基于客户端的remote_addr做hash计算,以实现会话保持 | upstream |
| **least_conn** | 最少连接调度算法,优先将客户端请求调度到当前连接最少的后端服务器<br>相当于LVS中的WLC算法,配合权重,能实现类似于LVS中的LC算法 | upstream |
| **hash key [consistent]** | 使用自行指定的Key做hash运算后进行调度,Key可以是变量,比如请求头中的字段、URI等<br>如果对应的server条目配置发生了变化,会导致相同的key被重新hash<br>**consistent**:表示使用一致性hash,此参数确保该upstream中的server条目发生变化时,尽可能少的重新hash,适用于做缓存服务的场景,提高缓存命中率 | upstream |

#### 4.2.2 连接保持配置

| 配置 | 说明 | 默认值 | 作用域 |
|------|------|--------|--------|
| **keepalive connections** | 为每个worker进程保留最多多少个空闲保活连接数<br>超过此值,最近最少使用的连接将被关闭 | 不设置 | upstream |
| **keepalive_time time** | 空闲连接保持的时长,超过该时间,一直没使用的空闲连接将被销毁 | 1h | upstream |

### 4.3 健康检测机制

**Nginx upstream 健康检测特点**:

1. **被动检查**:当有客户端请求被调度到该服务器上时,会在TCP协议层的三次握手时检查该服务器是否可用
2. **不可用标记**:如果不可用就调度到别的服务器,当不可用的次数达到指定次数时（默认是1次,由 max_fails 决定）,在规定时间内（默认是10S,由 fail_timeout 决定）,不会再向该服务器调度请求
3. **恢复机制**:直到超过规定时间后再次向该服务器调度请求,如果再次调度该服务器还是不可用,则继续等待一个时间段,如果再次调度该服务器可用,则恢复该服务器到调度列表中

---

## 🔧 第五部分:负载均衡基础实践

### 5.1 环境准备

#### 5.1.1 配置 DNS 解析

```bash
# 启动 DNS 主从服务并配置域名解析
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose up -d

# 配置主 DNS：balance.com 及其子域名解析到负载均衡器 10.0.7.70
sudo docker compose exec -it dns-master /usr/local/bin/setup-dns-master.sh balance.com 10.0.7.70 10.0.0.13 10.0.0.15
sudo docker compose exec -it dns-master /usr/local/bin/setup-dns-master.sh group1.balance.com 10.0.7.70 10.0.0.13 10.0.0.15
sudo docker compose exec -it dns-master /usr/local/bin/setup-dns-master.sh group2.balance.com 10.0.7.70 10.0.0.13 10.0.0.15

# 配置从 DNS
sudo docker compose exec -it dns-slave /usr/local/bin/setup-dns-slave.sh balance.com 10.0.0.13
sudo docker compose exec -it dns-slave /usr/local/bin/setup-dns-slave.sh group1.balance.com 10.0.0.13
sudo docker compose exec -it dns-slave /usr/local/bin/setup-dns-slave.sh group2.balance.com 10.0.0.13

# 配置跨网段通信（允许 DNS 网段 10.0.0.0/24 与 Nginx 网段 10.0.7.0/24 通信）
sudo iptables -F -t raw
sudo iptables -F DOCKER
sudo iptables -F DOCKER-ISOLATION-STAGE-2
sudo iptables -P FORWARD ACCEPT
sudo iptables -t nat -I POSTROUTING -s 10.0.0.0/24 -d 10.0.7.0/24 -j RETURN

# 返回 Nginx 目录
cd /home/www/docker-man/07.nginx/07.manual-balance/
```

#### 5.1.2 配置后端服务器 1（nginx-web-1）

```bash
# 进入容器
sudo docker compose exec -it nginx-web-1 bash

# 创建测试页面
mkdir -p /data/wwwroot/backend
echo "RealServer-1" > /data/wwwroot/backend/index.html

# 配置 Nginx
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/backend;
        location / {
            return 200 "RealServer-1\n";
        }
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx
```

#### 5.1.3 配置后端服务器 2（nginx-web-2）

```bash
# 进入容器
sudo docker compose exec -it nginx-web-2 bash

# 创建测试页面
mkdir -p /data/wwwroot/backend
echo "RealServer-2" > /data/wwwroot/backend/index.html

# 配置 Nginx
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/backend;
        location / {
            return 200 "RealServer-2\n";
        }
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx
```

#### 5.1.4 配置后端服务器 3（nginx-web-3，备用）

```bash
# 进入容器
sudo docker compose exec -it nginx-web-3 bash

# 创建测试页面
mkdir -p /data/wwwroot/backend
echo "RealServer-3-Backup" > /data/wwwroot/backend/index.html

# 配置 Nginx
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/backend;
        location / {
            return 200 "RealServer-3-Backup\n";
        }
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx
```

### 5.2 配置负载均衡器（轮询）

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 配置 Nginx 负载均衡
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    # 定义后端服务器组
    upstream backend {
        server 10.0.7.71;
        server 10.0.7.72;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx
```

### 5.3 测试轮询效果

```bash
# 进入 DNS 客户端容器测试
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 测试负载均衡（轮询）
curl http://balance.com
# 预期输出:RealServer-1

curl http://balance.com
# 预期输出:RealServer-2

curl http://balance.com
# 预期输出:RealServer-1

curl http://balance.com
# 预期输出:RealServer-2
```

**结果说明**:客户端访问,轮询调度到后端服务器

---

## 💪 第六部分:权重负载实践

### 6.1 权重配置

**权重说明**:
- weight 参数用于指定服务器的权重
- 权重越高,被分配到的请求越多
- 默认权重为 1

### 6.2 配置权重负载（3:1）

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 配置权重负载
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    # 定义一个 3:1 的权重负载效果
    upstream backend {
        server 10.0.7.71 weight=3;
        server 10.0.7.72;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 6.3 测试权重效果

```bash
# 进入 DNS 客户端容器测试
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 测试负载均衡（3:1 权重）
curl http://balance.com
# 预期输出:RealServer-1

curl http://balance.com
# 预期输出:RealServer-1

curl http://balance.com
# 预期输出:RealServer-1

curl http://balance.com
# 预期输出:RealServer-2
```

**结果说明**:负载比例是 3:1

---

## 🔒 第七部分:最大连接数限制实践

### 7.1 max_conns 参数说明

**max_conns 作用**:
- 限制该 Server 的最大活动连接数
- 达到限制后将不再给该 Server 发送请求
- **可以保持的连接数 = 代理服务器的进程数 × max_conns**

### 7.2 配置负载均衡器

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 配置最大连接数限制
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    # 10.0.7.71 同时只能维持 2 个活动连接
    upstream backend {
        server 10.0.7.71 max_conns=2;
        server 10.0.7.72;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 7.3 配置后端服务器限速

#### 7.3.1 配置 nginx-web-1 限速

```bash
# 进入容器
sudo docker compose exec -it nginx-web-1 bash

# 创建 10MB 测试文件
mkdir -p /data/wwwroot/download
dd if=/dev/zero of=/data/wwwroot/download/10.img bs=10M count=1

# 配置限速 10KB/s
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/download;
        limit_rate 10k;
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

#### 7.3.2 配置 nginx-web-2 限速

```bash
# 进入容器
sudo docker compose exec -it nginx-web-2 bash

# 创建 10MB 测试文件
mkdir -p /data/wwwroot/download
dd if=/dev/zero of=/data/wwwroot/download/10.img bs=10M count=1

# 配置限速 10KB/s
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/download;
        limit_rate 10k;
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 7.4 CPU 核心数计算说明

**⚠️ max_conns 与 worker 进程的关系**:

可以保持的连接数 = 代理服务器的进程数 × max_conns

**示例说明**:
- 如果 Real Server 上有 2 个 CPU 核心
- worker_processes 设置为 auto（自动等于 CPU 核心数 = 2）
- max_conns = 2
- 那么该主机上最多连接数量 = 2 × 2 = 4

### 7.5 测试最大连接数效果

```bash
# 进入 DNS 客户端容器执行多次 wget（20次）
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 执行多次下载
for i in {1..20}; do wget http://balance.com/10.img & done

# 查看下载进程
ps aux | grep wget

# 退出客户端容器，进入 nginx-web-1 容器查看连接数量
exit
cd /home/www/docker-man/07.nginx/07.manual-balance/
sudo docker compose exec -it nginx-web-1 bash
ss -tnep | grep 80
```

**预期输出示例**（4条活动连接）:
```
ESTAB  0  0  10.0.7.71:80  10.0.7.70:45678  users:(("nginx",pid=123,fd=10))
ESTAB  0  0  10.0.7.71:80  10.0.7.70:45679  users:(("nginx",pid=123,fd=11))
ESTAB  0  0  10.0.7.71:80  10.0.7.70:45680  users:(("nginx",pid=124,fd=10))
ESTAB  0  0  10.0.7.71:80  10.0.7.70:45681  users:(("nginx",pid=124,fd=11))
```

**结果说明**:
- Real Server 上有 2 个 CPU 核心（2 个 worker 进程）
- 每个 worker 进程最大连接数为 2
- 该主机上最多连接数量 = 2 × 2 = 4
- 当达到 4 个连接后,新的请求会被调度到其他后端服务器

---

## 🔀 第六部分(补充):多 Upstream 实践

### 6.4 多 Upstream 场景说明

**应用场景**:
- 不同的域名或 URL 路径需要调度到不同的后端服务器组
- 实现多个应用的负载均衡
- 支持复杂的路由策略

### 6.5 准备后端服务器

```bash
# 重新配置 nginx-web-1（恢复简单响应）
sudo docker compose exec -it nginx-web-1 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/backend;
        location / {
            return 200 "RealServer-1\n";
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
exit

# 重新配置 nginx-web-2（恢复简单响应）
sudo docker compose exec -it nginx-web-2 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/backend;
        location / {
            return 200 "RealServer-2\n";
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
exit
```

### 6.6 配置多个 Upstream

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 配置两个独立的 upstream 组
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    # 定义第一个后端服务器组 group1
    upstream group1 {
        server 10.0.7.71;
    }

    # 定义第二个后端服务器组 group2
    upstream group2 {
        server 10.0.7.72;
    }

    # 使用 server_name 匹配 group1
    server {
        listen 80;
        server_name group1.balance.com;
        location / {
            proxy_pass http://group1;
        }
    }

    # 使用 server_name 匹配 group2
    server {
        listen 80;
        server_name group2.balance.com;
        location / {
            proxy_pass http://group2;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 6.7 测试多 Upstream 效果

```bash
# 进入 DNS 客户端容器测试
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 测试 group1（访问 group1.balance.com）
curl http://group1.balance.com
# 预期输出:RealServer-1

curl http://group1.balance.com
# 预期输出:RealServer-1

# 测试 group2（访问 group2.balance.com）
curl http://group2.balance.com
# 预期输出:RealServer-2

curl http://group2.balance.com
# 预期输出:RealServer-2
```

**结果说明**:
- 使用不同的 server_name 可以将请求调度到不同的 upstream 组
- group1.balance.com 的请求调度到 10.0.7.71
- group2.balance.com 的请求调度到 10.0.7.72
- 实现了基于域名的负载均衡分组

---

## 🛡️ 第八部分:备用主机实践

### 8.1 backup 参数说明

**backup 作用**:
- 标记该 Server 为备用
- 当所有后端服务器不可用时,才使用此服务器

### 8.2 配置备用服务器

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 配置备用服务器
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    # 10.0.7.73 平常不用,作为备用
    upstream backend {
        server 10.0.7.71;
        server 10.0.7.72;
        server 10.0.7.73 backup;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 8.3 测试备用服务器（正常情况）

```bash
# 进入 DNS 客户端容器测试
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

curl http://balance.com
# 预期输出:RealServer-1

curl http://balance.com
# 预期输出:RealServer-2

curl http://balance.com
# 预期输出:RealServer-1
```

**结果说明**:正常访问时,都是主服务器响应

### 8.4 测试备用服务器（故障情况）

```bash
# 停止 nginx-web-1 服务
sudo docker compose exec -it nginx-web-1 bash
/data/server/nginx/sbin/nginx -s stop
exit

# 停止 nginx-web-2 服务
sudo docker compose exec -it nginx-web-2 bash
/data/server/nginx/sbin/nginx -s stop
exit

# 在 DNS 客户端容器中测试
curl http://balance.com
# 预期输出:RealServer-3-Backup

curl http://balance.com
# 预期输出:RealServer-3-Backup
```

**结果说明**:当正常提供服务的主机服务异常之后,携带backup标识的主机才会响应服务

---

## 🔽 第九部分:应用平滑下线实践

### 9.1 down 参数说明

**down 作用**:
- 标记该 Server 临时不可用
- 可用于平滑下线后端服务器
- **新请求不再调度到此服务器,原有连接不受影响**

### 9.2 准备下载测试环境

```bash
# 配置 nginx-web-1 提供下载服务（限速 1MB/s）
sudo docker compose exec -it nginx-web-1 bash

# 创建 100MB 测试文件
mkdir -p /data/wwwroot/download
dd if=/dev/zero of=/data/wwwroot/download/large-file.bin bs=1M count=100

# 配置 Nginx（限速 1MB/s，100MB 需要约 100 秒下载）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/download;
        limit_rate 1m;  # 限速 1MB/s

        location / {
            autoindex on;
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit

# 配置 nginx-web-2 提供下载服务（限速 1MB/s）
sudo docker compose exec -it nginx-web-2 bash

# 创建 100MB 测试文件
mkdir -p /data/wwwroot/download
dd if=/dev/zero of=/data/wwwroot/download/large-file.bin bs=1M count=100

# 配置 Nginx（限速 1MB/s）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/download;
        limit_rate 1m;  # 限速 1MB/s

        location / {
            autoindex on;
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit

# 配置负载均衡器（轮询）
sudo docker compose exec -it nginx-lb bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    upstream backend {
        server 10.0.7.71;
        server 10.0.7.72;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit
```

### 9.3 测试平滑下线效果

```bash
# 进入 DNS 客户端容器
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 启动第 1 个下载（后台运行，约 100 秒完成）
wget -O file1.bin http://balance.com/large-file.bin &

# 稍等 2 秒，启动第 2 个下载（确保调度到另一台服务器）
sleep 2
wget -O file2.bin http://balance.com/large-file.bin &

# 查看正在下载的进程
ps aux | grep wget

# 预期输出：
# root  123  wget -O file1.bin http://balance.com/large-file.bin
# root  124  wget -O file2.bin http://balance.com/large-file.bin

# 保持当前终端，打开新终端执行平滑下线
```

**在另一个终端中执行平滑下线**：

```bash
# 等待 10 秒后（下载进行中），标记 nginx-web-2 为 down
sleep 10

cd /home/www/docker-man/07.nginx/07.manual-balance/
sudo docker compose exec -it nginx-lb bash

# 配置平滑下线（10.0.7.72 准备下线）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    # 10.0.7.72 标记为 down，已有连接继续，新连接不再分配
    upstream backend {
        server 10.0.7.71;
        server 10.0.7.72 down;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit

# 在客户端容器中启动第 3 个下载（验证新连接不分配到 down 服务器）
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

wget -O file3.bin http://balance.com/large-file.bin &

# 查看所有下载进程
ps aux | grep wget

# 等待所有下载完成
wait

# 验证文件完整性（所有文件应为 100MB）
ls -lh file*.bin

# 预期输出：
# -rw-r--r-- 1 root root 100M Oct 18 10:00 file1.bin  # ✅ 完整下载
# -rw-r--r-- 1 root root 100M Oct 18 10:01 file2.bin  # ✅ 完整下载
# -rw-r--r-- 1 root root 100M Oct 18 10:02 file3.bin  # ✅ 新连接，只从 web-1 下载
```

### 9.4 验证平滑下线

```bash
# 在负载均衡器容器中查看连接分布
cd /home/www/docker-man/07.nginx/07.manual-balance/
sudo docker compose exec -it nginx-lb bash

# 查看到后端的连接数
ss -tn | grep -E "10.0.7.71|10.0.7.72"

# 预期观察：
# - file1.bin 和 file2.bin 的连接继续保持（可能分别在 .71 和 .72）
# - file3.bin 的新连接只会建立到 .71（因为 .72 已标记 down）
```

**结果说明**:
- ✅ **已有连接继续完成**：标记 down 前的下载任务（file1.bin, file2.bin）能正常完成
- ✅ **新连接不再分配**：标记 down 后的新下载（file3.bin）只会调度到 10.0.7.71
- ✅ **平滑下线成功**：10.0.7.72 可以在不影响正在进行的连接的情况下从容下线

---

## 🔐 第十部分:源IP地址hash实践

### 10.1 ip_hash 算法说明

**ip_hash 工作原理**:
- 源地址hash调度方法
- 基于客户端的 remote_addr 做hash计算
- **以实现会话保持（Session Sticky）**

### 10.2 准备后端服务器

```bash
# 恢复 nginx-web-1 为简单响应
sudo docker compose exec -it nginx-web-1 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/backend;
        location / {
            return 200 "RealServer-1\n";
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit

# 恢复 nginx-web-2 为简单响应
sudo docker compose exec -it nginx-web-2 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/backend;
        location / {
            return 200 "RealServer-2\n";
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit
```

### 10.3 配置 ip_hash

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 配置 ip_hash
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    upstream backend {
        ip_hash;  # 启用源IP地址hash
        server 10.0.7.71;
        server 10.0.7.72;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 10.4 测试 ip_hash 效果

```bash
# 进入 DNS 客户端容器测试
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 客户端测试（同一 IP 会固定到同一后端）
curl http://balance.com
# 预期输出:RealServer-1 或 RealServer-2（固定其中一个）

curl http://balance.com
# 预期输出:与上次相同（固定）

curl http://balance.com
# 预期输出:与上次相同（固定）

# 客户端2测试（进入 nginx-web-1 容器测试）
sudo docker compose exec -it nginx-web-1 bash
curl 10.0.7.70
# 预期输出:RealServer-2（固定）

curl 10.0.7.70
# 预期输出:RealServer-2（固定）
```

**结果说明**:
- 相同客户端 IP,请求始终调度到同一台后端服务器
- 实现了会话保持（Session Sticky）

---

## 🔑 第十一部分:自定义 Key Hash 实践

### 11.1 hash 指令说明

```nginx
hash key [consistent];
# 使用自行指定的 Key 做 hash 运算后进行调度
# Key 可以是变量,比如请求头中的字段、URI等
# 如果对应的server条目配置发生了变化,会导致相同的 key 被重新 hash
# consistent 表示使用一致性 hash
# 此参数确保该 upstream 中的 server 条目发生变化时,尽可能少的重新 hash
# 适用于做缓存服务的场景,提高缓存命中率
# 作用域:upstream
```

### 11.2 准备后端服务器

```bash
# 恢复 nginx-web-1 为简单响应
sudo docker compose exec -it nginx-web-1 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/backend;
        location / {
            return 200 "RealServer-1\n";
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit

# 恢复 nginx-web-2 为简单响应
sudo docker compose exec -it nginx-web-2 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/wwwroot/backend;
        location / {
            return 200 "RealServer-2\n";
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit
```

### 11.3 配置自定义 Key Hash（基于 $remote_addr）

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 配置自定义 Key Hash
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    upstream backend {
        hash $remote_addr;  # 使用客户端IP做hash
        server 10.0.7.71;
        server 10.0.7.72;
    }

    server {
        listen 80;
        server_name balance.com;
        add_header X-Remote-Addr $remote_addr;
        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 11.4 测试自定义 Key Hash 效果

```bash
# 进入 DNS 客户端容器测试
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 客户端测试（基于 $remote_addr Hash，同一客户端IP固定到同一后端）
curl http://balance.com
# 预期输出:RealServer-1 或 RealServer-2（固定其中一个）

curl http://balance.com
# 预期输出:与上次相同（固定）

curl 10.0.7.70
# 预期输出:RealServer-2（固定）
```

**结果说明**:
- 使用 `$remote_addr` 作为 hash key
- 效果与 `ip_hash` 相同
- 但可以灵活更换为其他变量（如 $request_uri）

---

## 🔄 第十二部分:Hash 算法详解

### 12.1 准备测试环境

```bash
# 配置 nginx-web-1（返回服务器标识和 URI）
sudo docker compose exec -it nginx-web-1 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        location / {
            return 200 "Server: web-1, URI: $uri\n";
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit

# 配置 nginx-web-2（返回服务器标识和 URI）
sudo docker compose exec -it nginx-web-2 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        location / {
            return 200 "Server: web-2, URI: $uri\n";
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit

# 启动 nginx-web-3（用于后续测试）
sudo docker compose exec -it nginx-web-3 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        location / {
            return 200 "Server: web-3-backup, URI: $uri\n";
        }
    }
}
EOF

/data/server/nginx/sbin/nginx
exit
```

### 12.2 普通 Hash 原理分析

#### 12.2.1 配置普通 Hash（基于 $uri）

```bash
# 进入负载均衡器容器
cd /home/www/docker-man/07.nginx/07.manual-balance/
sudo docker compose exec -it nginx-lb bash

# 配置普通 Hash（基于 $uri，使用 2 台服务器）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    upstream backend {
        hash $uri;  # 基于 URI 做 hash
        server 10.0.7.71;
        server 10.0.7.72;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit
```

**调度算法**：hash($uri) % 2

#### 12.2.2 测试普通 Hash（2 台服务器）

```bash
# 进入 DNS 客户端容器测试
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 测试多个不同的 URI（记录调度结果）
for i in {1..10}; do
  echo "=== Test /file$i ==="
  curl http://balance.com/file$i
done

# 预期输出示例（记录每个 URI 被调度到哪台服务器）：
# === Test /file1 ===
# Server: web-1, URI: /file1     ← hash("/file1") % 2 = 0
# === Test /file2 ===
# Server: web-2, URI: /file2     ← hash("/file2") % 2 = 1
# === Test /file3 ===
# Server: web-1, URI: /file3     ← hash("/file3") % 2 = 0
# ...
```

**记录调度结果**（实际测试）：

| URI | 调度服务器 |
|-----|----------|
| /file1 | web-2 |
| /file2 | web-1 |
| /file3 | web-2 |
| /file4 | web-2 |
| /file5 | web-1 |
| /file6 | web-2 |
| /file7 | web-1 |
| /file8 | web-2 |
| /file9 | web-1 |
| /file10 | web-1 |

#### 12.2.3 增加第 3 台服务器测试

```bash
# 退出客户端容器
exit

# 进入负载均衡器，增加第 3 台服务器
cd /home/www/docker-man/07.nginx/07.manual-balance/
sudo docker compose exec -it nginx-lb bash

# 修改配置，增加 web-3
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    upstream backend {
        hash $uri;  # 基于 URI 做 hash
        server 10.0.7.71;
        server 10.0.7.72;
        server 10.0.7.73;  # 新增第 3 台服务器
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit

# 重新测试相同的 URI
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

for i in {1..10}; do
  echo "=== Test /file$i ==="
  curl http://balance.com/file$i
done
 
```

**对比调度结果**（实际测试）：

| URI | 2 台服务器时 | 3 台服务器时 | 是否变化 |
|-----|------------|------------|---------|
| /file1 | web-2 | **web-3-backup** | ✗ 变化 |
| /file2 | web-1 | **web-2** | ✗ 变化 |
| /file3 | web-2 | **web-3-backup** | ✗ 变化 |
| /file4 | web-2 | web-2 | ✓ 不变 |
| /file5 | web-1 | web-1 | ✓ 不变 |
| /file6 | web-2 | web-2 | ✓ 不变 |
| /file7 | web-1 | web-1 | ✓ 不变 |
| /file8 | web-2 | **web-1** | ✗ 变化 |
| /file9 | web-1 | **web-2** | ✗ 变化 |
| /file10 | web-1 | **web-2** | ✗ 变化 |

**统计结果**：
- ✓ **保持不变**：4 个 URI（file4, file5, file6, file7）- 40%
- ✗ **重新调度**：6 个 URI（file1, file2, file3, file8, file9, file10）- 60%
- 📊 **变化率**：**60%**

**问题分析**：
- 💥 **缓存失效率高**：增加 1 台服务器（33% 容量增长），导致 **60%** 的 URI 被重新调度
- 💥 **缓存大量失效**：如果这些 URI 对应的是缓存数据（如图片、视频、API 响应），60% 的缓存失效
- 💥 **缓存穿透风险**：大量请求会击穿到后端数据库或存储，导致压力激增
- 💥 **用户体验下降**：原本命中缓存的请求变慢，响应时间增加

**实际影响示例**：
- 假设原来 10 万个 URL 缓存在 2 台服务器
- 增加第 3 台服务器后，6 万个 URL 的缓存失效
- 这 6 万个请求需要重新从源站获取数据
- 可能导致源站瞬时压力激增 60%

#### 12.2.4 新增服务器后的问题（理论分析）

**算法变化**：hash($uri) % 2 → hash($uri) % 3

| hash($uri) 值 | 原调度 (% 2) | 新调度 (% 3) | 变化 |
|-------------------|------------------------|--------|
| 4, 8 | 0, 0 | 10.0.0.111 |
| 1, 5, 9 | 1, 1, 1 | 10.0.0.112 |
| 2, 6 | 2, 2 | 10.0.0.113 |
| 3, 7 | 3, 3 | 10.0.0.114 |

**问题说明**:
- 新增后端服务器后,总权重发生变化
- 所有前端的请求都会被重新计算
- 调度到和原来不同的后端服务器上了
- **这样会导致在原来后端服务器上创建的数据,在新的服务器上没有了**
- 减少后端服务器或修改后端服务器权重,都会导致重新调度
- **会导致原有缓存数据失效（例如登录状态、购物车等）**

### 12.2 加权 Hash 效果

```nginx
upstream backend {
    hash $remote_addr;
    server 10.0.0.111 weight=1;
    server 10.0.0.112 weight=2;
    server 10.0.0.113 weight=3;
}
```

**调度算法**:hash($remote_addr) % (1+2+3) = hash($remote_addr) % 6

**详细调度说明**:

| hash($remote_addr) % 6 | server | 权重说明 |
|------------------------|--------|---------|
| 0 | 10.0.0.111 | 权重为 1,分配 1 个槽位 |
| 1 | 10.0.0.112 | 权重为 2,分配 2 个槽位 |
| 2 | 10.0.0.112 | 权重为 2,分配 2 个槽位 |
| 3 | 10.0.0.113 | 权重为 3,分配 3 个槽位 |
| 4 | 10.0.0.113 | 权重为 3,分配 3 个槽位 |
| 5 | 10.0.0.113 | 权重为 3,分配 3 个槽位 |

**调度规则**:
- **hash 结果为 0**: 调度到 10.0.0.111（权重 1）
- **hash 结果为 1-2**: 调度到 10.0.0.112（权重 2）
- **hash 结果为 3-4-5**: 调度到 10.0.0.113（权重 3）

**结果说明**:
- 总权重 = 1 + 2 + 3 = 6
- 10.0.0.111 占比 = 1/6 ≈ 16.7%
- 10.0.0.112 占比 = 2/6 ≈ 33.3%
- 10.0.0.113 占比 = 3/6 = 50%

---

## 🔁 第十三部分:一致性哈希详解

### 13.1 一致性哈希简介

一致性哈希（Consistent Hashing）是一种用于分布式系统中数据分片和负载均衡的算法,其中的"hash环"是该算法的核心概念之一。

### 13.2 一致性 Hash 实践测试

#### 13.2.1 配置一致性 Hash（2 台服务器）

```bash
# 进入负载均衡器容器
cd /home/www/docker-man/07.nginx/07.manual-balance/
sudo docker compose exec -it nginx-lb bash

# 配置一致性 Hash（基于 $uri，使用 2 台服务器）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    upstream backend {
        hash $uri consistent;  # 一致性 hash
        server 10.0.7.71;
        server 10.0.7.72;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit
```

#### 13.2.2 测试一致性 Hash（2 台服务器）

```bash
# 进入 DNS 客户端容器测试
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 测试多个不同的 URI（记录调度结果）
for i in {1..10}; do
  echo "=== Test /file$i ==="
  curl http://balance.com/file$i
done

# 记录调度结果（示例）
```

**记录调度结果**（实际测试）：

| URI | 调度服务器 |
|-----|----------|
| /file1 | web-2 |
| /file2 | web-1 |
| /file3 | web-2 |
| /file4 | web-2 |
| /file5 | web-2 |
| /file6 | web-2 |
| /file7 | web-1 |
| /file8 | web-1 |
| /file9 | web-2 |
| /file10 | web-2 |

#### 13.2.3 增加第 3 台服务器测试

```bash
# 退出客户端容器
exit

# 进入负载均衡器，增加第 3 台服务器
cd /home/www/docker-man/07.nginx/07.manual-balance/
sudo docker compose exec -it nginx-lb bash

# 修改配置，增加 web-3（使用一致性 hash）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    upstream backend {
        hash $uri consistent;  # 一致性 hash
        server 10.0.7.71;
        server 10.0.7.72;
        server 10.0.7.73;  # 新增第 3 台服务器
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit

# 重新测试相同的 URI
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

for i in {1..10}; do
  echo "=== Test /file$i ==="
  curl http://balance.com/file$i
done
```

**对比调度结果**（实际测试）：

| URI | 2 台服务器时 | 3 台服务器时 | 是否变化 |
|-----|------------|------------|---------|
| /file1 | web-2 | **web-3-backup** | ✗ 变化 |
| /file2 | web-1 | web-1 | ✓ 不变 |
| /file3 | web-2 | web-2 | ✓ 不变 |
| /file4 | web-2 | **web-3-backup** | ✗ 变化 |
| /file5 | web-2 | **web-3-backup** | ✗ 变化 |
| /file6 | web-2 | web-2 | ✓ 不变 |
| /file7 | web-1 | web-1 | ✓ 不变 |
| /file8 | web-1 | web-1 | ✓ 不变 |
| /file9 | web-2 | web-2 | ✓ 不变 |
| /file10 | web-2 | **web-3-backup** | ✗ 变化 |

**统计结果**：
- ✓ **保持不变**：6 个 URI（file2, file3, file6, file7, file8, file9）- **60%**
- ✗ **重新调度**：4 个 URI（file1, file4, file5, file10）- **40%**
- 📊 **变化率**：**40%**

**优势对比**：
- ✅ **缓存失效率低**：增加 1 台服务器（33% 容量增长），只有 **40%** 的 URI 被重新调度
- ✅ **大部分缓存保留**：**60%** 的请求仍然调度到原服务器，缓存命中率高
- ✅ **平滑扩容**：相比普通 hash（60% 失效），一致性 hash 减少 **20%** 失效率
- ✅ **减轻穿透压力**：源站压力仅增加 40%，而非 60%

#### 13.2.4 普通 Hash vs 一致性 Hash 对比总结

**实际测试结果对比**：

| 对比项 | 普通 Hash（实测） | 一致性 Hash（实测） |
|--------|------------------|------------------|
| **算法** | hash % n | 基于 hash 环 |
| **2→3 台扩容影响** | **60%** 请求重新调度 | **40%** 请求重新调度 |
| **缓存失效率** | ❌ **高（60% 失效）** | ✅ **低（40% 失效）** |
| **保留率** | 仅 40% 保持不变 | **60%** 保持不变 |
| **适用场景** | 固定服务器数量 | 动态扩缩容、缓存服务 |
| **配置方式** | `hash $key` | `hash $key consistent` |

**实测数据说明**（10 个 URI 测试）：
- **普通 Hash**：4 个不变，6 个变化（**60% 变化率**）
- **一致性 Hash**：6 个不变，4 个变化（**40% 变化率**）
- **改善效果**：失效率降低 **20%**（从 60% 降到 40%）

**性能影响对比**（基于实测数据）：

| 场景 | 普通 Hash | 一致性 Hash | 差异 |
|------|----------|------------|------|
| 10 万 URL 扩容 | 6 万缓存失效 | **4 万缓存失效** | 减少 2 万（33% 改善） |
| 源站压力 | 瞬时增加 60% | 瞬时增加 **40%** | 减少 20% 压力 |
| 用户体验 | 60% 请求变慢 | **40%** 请求变慢 | 改善 20% |
| 缓存命中率 | 从 100% 降至 40% | 从 100% 降至 **60%** | 保留 20% 更多命中 |

**最佳实践**：
- 🎯 **缓存服务器**：强烈建议一致性 hash（Redis、Memcached 集群）
- 🎯 **动态扩容场景**：必须使用一致性 hash（容器环境、云平台）
- 🎯 **固定服务器**：普通 hash 即可（服务器数量稳定、无扩缩容需求）
- 🎯 **CDN 缓存**：使用一致性 hash（节点频繁增删）

---

**工作原理**:
1. 所有可能的数据节点或服务器被映射到一个虚拟的环上
2. 这个环的范围通常是一个固定的哈希空间,比如 0 到 2^32-1
3. 每个数据节点或服务器被映射到环上的一个点,通过对其进行哈希计算得到
4. 这个哈希值的范围也是在 0 到 2^32-1 之间

### 13.2 数据存储与查询

**存储数据**:
- 通过哈希计算得到该数据的哈希值
- 在环上找到离这个哈希值最近的节点
- 将数据存储在这个节点上

**查询数据**:
- 通过哈希计算得到数据的哈希值
- 找到最近的节点进行查询

### 13.3 一致性哈希的优势

**节点变化影响小**:
- 由于哈希环是一个环形结构,节点的添加和删除对整体的影响相对较小
- 当添加或删除节点时,只有相邻的节点受到影响,而其他节点保持不变
- 这使得一致性哈希算法在分布式系统中能够提供较好的负载均衡性能
- 同时减小了数据迁移的开销

### 13.4 一致性哈希配置

```nginx
# 完整配置示例
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    upstream backend {
        # 添加一致性 hash 参数
        hash $remote_addr consistent;
        server 10.0.0.210;
        server 10.0.0.159;
        server 10.0.0.213;
    }

    server {
        listen 80;
        location / {
            proxy_pass http://backend;
            proxy_set_header Host $http_host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
```

**配置说明**:
- 使用 `consistent` 参数启用一致性哈希
- 添加/删除服务器时,只影响相邻节点
- 最小化缓存失效范围

### 13.5 一致性哈希调度表

| hash($remote_addr) | hash($remote_addr) % (2^32-1) | Node | Server |
|-------------------|------------------------------|------|--------|
| 1 | 1 | 1 | 顺时针第一个 |
| 2 | 2 | 2 | 顺时针第一个 |
| 3 | 3 | 3 | 顺时针第一个 |
| 4 | 4 | 4 | 顺时针第一个 |
| 5 | 5 | 5 | 顺时针第一个 |

### 13.6 哈希环示意图

```
                    0/2^32
                      ↑
                      |
        2^32×3/4 ←----+----→ 2^32×1/4
                      |
                      |
                   2^32×1/2
```

### 13.7 环偏移问题与虚拟节点

**环偏移（Ring Wrapping）**:
- 哈希环上的某个区域过于拥挤,而其他区域相对空闲
- 这可能导致负载不均衡

**解决方案 - 虚拟节点（Virtual Nodes）**:
- 为每个物理节点创建多个虚拟节点
- 将它们均匀地分布在哈希环上
- 每个物理节点在环上的位置会有多个副本,而不是只有一个位置
- 即使哈希环上的某个区域过于拥挤,也可以通过调整虚拟节点的数量来使得负载更均衡

#### 13.7.1 虚拟节点工作原理

**传统问题**:
- 物理节点直接映射到哈希环上
- 如果节点分布不均,可能导致某些节点负载过高

**虚拟节点解决方案**:

假设有 3 个物理节点:Server-A、Server-B、Server-C

```
物理节点 → 虚拟节点映射
Server-A → Server-A#1, Server-A#2, Server-A#3 (创建3个虚拟节点)
Server-B → Server-B#1, Server-B#2, Server-B#3 (创建3个虚拟节点)
Server-C → Server-C#1, Server-C#2, Server-C#3 (创建3个虚拟节点)
```

**映射过程**:
1. 每个物理节点被复制为多个虚拟节点
2. 对每个虚拟节点进行 hash 运算:hash("Server-A#1")、hash("Server-A#2")...
3. 将虚拟节点均匀分布在哈希环上
4. 客户端请求通过 hash 定位到某个虚拟节点
5. 虚拟节点映射回对应的物理节点处理请求

**优势说明**:
- **更均匀分布**:虚拟节点数量越多,负载分布越均匀
- **减少偏移影响**:即使某个物理节点负载高,其虚拟节点分散在环上,整体负载仍可均衡
- **动态调整**:可以为高性能服务器创建更多虚拟节点,实现加权负载均衡

**⚠️ Nginx 实现说明**:
- Nginx 的一致性哈希实现已经内置虚拟节点机制
- 使用 `hash $key consistent;` 时,Nginx 会自动创建虚拟节点
- 无需手动配置虚拟节点数量

---

## 🔍 第十四部分:Server 健康检测详解

### 14.1 nginx_upstream_check_module 模块简介

**模块说明**:
- nginx_upstream_check_module 是一个第三方模块（非 Nginx 官方核心模块）
- 用于实现对后端服务器的主动健康检查功能
- 通过定期发送探测请求并分析响应,自动识别不健康的服务器并将其从负载均衡池中临时移除
- 待恢复正常后再重新加入负载均衡池
- 项目地址: https://github.com/yaoweibin/nginx_upstream_check_module

**与 Nginx 被动健康检查的区别**:

| 特性 | 被动健康检查 (Nginx 原生) | 主动健康检查 (check 模块) |
|------|-------------------------|------------------------|
| **检查方式** | 仅在实际请求失败时标记 | 主动定期探测后端服务器 |
| **检测时机** | 用户请求触发 | 后台定时任务 |
| **响应速度** | 慢（需要用户请求失败） | 快（主动发现故障） |
| **配置复杂度** | 简单（fail_timeout, max_fails） | 复杂（需要第三方模块） |
| **适用场景** | 小规模、低要求 | 生产环境、高可用要求 |

---

### 14.2 工作原理

#### 14.2.1 主动健康检查机制

```
┌─────────────────────────────────────────────────────────────┐
│                    Nginx 负载均衡器                          │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  nginx_upstream_check_module                          │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │  Health Check Timer (每 interval 毫秒)          │  │  │
│  │  └──────────────┬──────────────────────────────────┘  │  │
│  │                 ↓                                       │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  发送探测请求到所有后端服务器                     │  │  │
│  │  │  - HTTP: GET /health_check                        │  │  │
│  │  │  - TCP: 建立连接                                  │  │  │
│  │  └──────────────┬───────────────────────────────────┘  │  │
│  │                 ↓                                       │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  分析响应结果                                     │  │  │
│  │  │  - 成功: success_count++                          │  │  │
│  │  │  - 失败: fail_count++                             │  │  │
│  │  └──────────────┬───────────────────────────────────┘  │  │
│  │                 ↓                                       │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  更新服务器状态                                   │  │  │
│  │  │  - fail_count >= fall: 标记为 DOWN               │  │  │
│  │  │  - success_count >= rise: 标记为 UP              │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
           ↓                    ↓                    ↓
   ┌───────────────┐    ┌───────────────┐    ┌───────────────┐
   │ Backend 1     │    │ Backend 2     │    │ Backend 3     │
   │ 10.0.7.71     │    │ 10.0.7.72     │    │ 10.0.7.73     │
   │ Status: UP ✅ │    │ Status: DOWN ❌│   │ Status: UP ✅ │
   └───────────────┘    └───────────────┘    └───────────────┘
```

#### 14.2.2 状态转换流程

```
初始状态: UNKNOWN
     ↓ (首次检查成功)
状态: UP (健康)
     ↓ (连续失败 fall 次)
状态: DOWN (不健康) ← 不接收新请求
     ↓ (连续成功 rise 次)
状态: UP (健康) ← 重新接收请求
```

---

### 14.3 环境准备

#### 14.3.1 进入负载均衡器容器

```bash
# 进入 nginx-lb 容器
sudo docker compose exec -it nginx-lb bash
```

#### 14.3.2 检查当前 Nginx 版本和编译参数

```bash
# 检查版本
/data/server/nginx/sbin/nginx -v

# 查看编译参数（用于后续重新编译）
/data/server/nginx/sbin/nginx -V

# 预期输出类似:
# nginx version: nginx/1.24.0
# configure arguments: --prefix=/data/server/nginx ...
```

---

### 14.4 下载健康检查模块

#### 14.4.1 创建工作目录

```bash
# 创建软件存放目录
mkdir -p /data/softs && cd /data/softs
```

#### 14.4.2 下载 nginx_upstream_check_module

```bash
# 下载健康检查模块（使用 GitHub）
wget https://github.com/yaoweibin/nginx_upstream_check_module/archive/refs/heads/master.zip -O check-module.zip

# 或使用 git clone（如果有 git 命令）
# git clone https://github.com/yaoweibin/nginx_upstream_check_module.git

# 安装 unzip（如果没有）
apt update && apt install -y unzip

# 解压模块
unzip check-module.zip

# 查看解压后的目录
ls -la nginx_upstream_check_module-master/

# 预期输出应包含:
# - config           (模块配置文件)
# - ngx_http_upstream_check_module.c
# - check_1.20.1+.patch (针对不同版本的补丁文件)
```

#### 14.4.3 下载 Nginx 源码

```bash
# 下载与当前版本一致的 Nginx 源码
cd /data/softs

# 检查当前 Nginx 版本
/data/server/nginx/sbin/nginx -v
# 输出: nginx version: nginx/1.24.0

# 下载对应版本源码
wget http://nginx.org/download/nginx-1.24.0.tar.gz
tar xf nginx-1.24.0.tar.gz
cd nginx-1.24.0

# 查看目录结构
ls -la
```

---

### 14.5 应用补丁文件

#### 14.5.1 选择合适的补丁

**重要说明**: nginx_upstream_check_module 需要对 Nginx 源码打补丁才能编译

```bash
# 查看可用的补丁文件
ls -la /data/softs/nginx_upstream_check_module-master/*.patch

# 预期输出:
# check_1.20.1+.patch     (适用于 Nginx 1.20.1 及以上版本)
# check_1.16.1+.patch
# check_1.14.0+.patch
```

#### 14.5.2 应用补丁（针对 Nginx 1.24.0）

```bash
# 进入 Nginx 源码目录
cd /data/softs/nginx-1.24.0

# 应用补丁（使用 1.20.1+ 的补丁）
patch -p1 < /data/softs/nginx_upstream_check_module-master/check_1.20.1+.patch

# 预期输出:
# patching file src/http/modules/ngx_http_upstream_ip_hash_module.c
# patching file src/http/modules/ngx_http_upstream_least_conn_module.c
# patching file src/http/ngx_http_upstream_round_robin.c
# patching file src/http/ngx_http_upstream_round_robin.h

# 如果打补丁失败,可能是版本不匹配,尝试其他补丁文件
```

**⚠️ 如果打补丁失败**:

```bash
# 错误示例:
# patching file ... FAILED

# 解决方法 1: 尝试更低版本的补丁
patch -p1 < /data/softs/nginx_upstream_check_module-master/check_1.16.1+.patch

# 解决方法 2: 使用 --dry-run 测试补丁
patch -p1 --dry-run < /data/softs/nginx_upstream_check_module-master/check_1.20.1+.patch

# 解决方法 3: 查看 GitHub Issues 寻找解决方案
# https://github.com/yaoweibin/nginx_upstream_check_module/issues
```

---

### 14.6 重新编译 Nginx

#### 14.6.1 获取原有编译参数

```bash
# 获取当前 Nginx 的编译参数
/data/server/nginx/sbin/nginx -V 2>&1 | grep "configure arguments:"

# 将参数保存到文件（方便复制）
/data/server/nginx/sbin/nginx -V 2>&1 | grep "configure arguments:" | \
  sed 's/configure arguments://' > /tmp/nginx_args.txt

# 查看参数
cat /tmp/nginx_args.txt
```

#### 14.6.2 配置编译（添加健康检查模块）

```bash
# 进入源码目录
cd /data/softs/nginx-1.24.0

# 重新配置（添加 --add-module 参数）
./configure $(cat /tmp/nginx_args.txt) \
  --add-module=/data/softs/nginx_upstream_check_module-master

# 预期输出最后应包含:
# Configuration summary
#   + ngx_http_upstream_check_module was configured
```

**⚠️ 如果配置失败,可能缺少依赖**:

```bash
# 安装编译依赖
apt update && apt install -y build-essential libpcre3 libpcre3-dev \
  zlib1g zlib1g-dev libssl-dev
```

#### 14.6.3 编译（不要执行 make install）

```bash
# 编译（仅执行 make,不执行 make install）
make

# 编译时长约 2-5 分钟,请耐心等待...

# 检查生成的新可执行文件
ls -lh objs/nginx
# 预期输出:
# -rwxr-xr-x 1 root root 6.5M Oct 17 10:00 objs/nginx

# 验证新编译的 nginx 包含健康检查模块
./objs/nginx -V 2>&1 | grep check
# 预期输出应包含:
# --add-module=/data/softs/nginx_upstream_check_module-master
```

---

### 14.7 平滑升级 Nginx（参考第三部分升级文档）

#### 14.7.1 备份旧可执行文件

```bash
# 备份旧版本
mv /data/server/nginx/sbin/nginx /data/server/nginx/sbin/nginx.bak

# 复制新版本
cp /data/softs/nginx-1.24.0/objs/nginx /data/server/nginx/sbin/
chmod +x /data/server/nginx/sbin/nginx

# 验证版本
/data/server/nginx/sbin/nginx -V 2>&1 | grep check
# 应该能看到 --add-module=.../nginx_upstream_check_module-master
```

#### 14.7.2 平滑升级（使用信号控制）

```bash
# 如果 Nginx 还未启动,直接启动
/data/server/nginx/sbin/nginx

# 如果 Nginx 已启动,执行平滑升级
# 1. 获取旧 master 进程 PID
OLD_PID=$(cat /data/server/nginx/run/nginx.pid)

# 2. 发送 USR2 信号（启动新 master）
kill -USR2 $OLD_PID

# 3. 等待 1 秒
sleep 1

# 4. 发送 WINCH 信号（关闭旧 worker）
kill -WINCH $OLD_PID

# 5. 等待 1 秒
sleep 1

# 6. 发送 QUIT 信号（退出旧 master）
kill -QUIT $OLD_PID

# 7. 验证进程
ps aux | grep nginx
```

**⚠️ 详细的平滑升级流程请参考**:
- `@/home/www/docker-man/07.nginx/03.manual-upgrade/compose.md` 第三部分

---

### 14.8 配置后端 Web 服务器

#### 14.8.1 配置后端服务器（返回服务器标识和健康检查）

**在宿主机执行**（打开新终端）:

```bash
# 进入项目目录
cd /home/www/docker-man/07.nginx/07.manual-balance

# 配置 nginx-web-1（返回服务器标识和健康检查）
sudo docker compose exec -it nginx-web-1 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
pid /data/server/nginx/run/nginx.pid;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;

        # 主路径：返回服务器标识
        location / {
            return 200 "Server: web-1, URI: $uri\n";
        }

        # 健康检查路径
        location /health_check {
            access_log off;  # 健康检查不记录访问日志
            return 200 "OK\n";
        }
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx
exit

# 配置 nginx-web-2（返回服务器标识和健康检查）
sudo docker compose exec -it nginx-web-2 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
pid /data/server/nginx/run/nginx.pid;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;

        # 主路径：返回服务器标识
        location / {
            return 200 "Server: web-2, URI: $uri\n";
        }

        # 健康检查路径
        location /health_check {
            access_log off;  # 健康检查不记录访问日志
            return 200 "OK\n";
        }
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx
exit

# 配置 nginx-web-3（用于后续测试，标记为 backup）
sudo docker compose exec -it nginx-web-3 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
pid /data/server/nginx/run/nginx.pid;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;

        # 主路径：返回服务器标识
        location / {
            return 200 "Server: web-3-backup, URI: $uri\n";
        }

        # 健康检查路径
        location /health_check {
            access_log off;  # 健康检查不记录访问日志
            return 200 "OK\n";
        }
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx
exit
```

**配置说明**:
- **location /** : 返回服务器标识和请求的 URI,用于负载均衡测试
- **location /health_check** : 返回 "OK",用于健康检查探测
  - 使用 `access_log off;` 避免产生大量日志
  - 使用 `return 200` 指令,简洁高效,无需创建 HTML 文件

#### 14.8.2 验证后端服务器

**在 nginx-lb 容器内执行**:

```bash
# 测试后端服务器 1
curl http://10.0.7.71/
curl http://10.0.7.71/health_check

# 预期输出:
# Server: web-1, URI: /
# OK

# 测试后端服务器 2
curl http://10.0.7.72/
curl http://10.0.7.72/health_check

# 预期输出:
# Server: web-2, URI: /
# OK

# 测试后端服务器 3
curl http://10.0.7.73/
curl http://10.0.7.73/health_check

# 预期输出:
# Server: web-3-backup, URI: /
# OK

# 测试不同的 URI（验证 $uri 变量）
curl http://10.0.7.71/test/path

# 预期输出:
# Server: web-1, URI: /test/path
```

---

### 14.9 配置负载均衡器健康检查

#### 14.9.1 配置域名解析（可选）

**在宿主机上配置** (方便从宿主机直接访问 balance.com):

```bash
# 编辑 /etc/hosts 文件
sudo vim /etc/hosts

# 添加以下行（将 balance.com 指向负载均衡器）
127.0.0.1  balance.com

# 保存后测试
ping balance.com

# 预期输出:
# PING balance.com (127.0.0.1) ...
```

**说明**:
- 这一步是可选的,仅用于方便从宿主机访问
- 容器内部不需要配置 hosts,直接使用 `-H "Host: balance.com"` 即可
- 如果不配置 hosts,宿主机访问时需要带 Host 头

#### 14.9.2 创建负载均衡配置

**在 nginx-lb 容器内执行**:

```bash
# 1. 备份原配置
cp /data/server/nginx/conf/nginx.conf /data/server/nginx/conf/nginx.conf.bak

# 2. 创建健康检查配置
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /data/server/nginx/logs/error.log warn;
pid /data/server/nginx/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /data/server/nginx/conf/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'upstream: $upstream_addr';

    access_log /data/server/nginx/logs/access.log main;

    sendfile        on;
    keepalive_timeout 65;

    # 定义后端服务器组（包含健康检查）
    upstream web_backend {
        server 10.0.7.71:80 weight=1;
        server 10.0.7.72:80 weight=1;
        server 10.0.7.73:80 weight=1 backup;

        # 健康检查配置
        check interval=3000 rise=2 fall=3 timeout=2000 type=http;
        # interval=3000    - 每 3 秒检查一次
        # rise=2           - 连续成功 2 次认为服务器恢复
        # fall=3           - 连续失败 3 次认为服务器不可用
        # timeout=2000     - 超时时间 2 秒
        # type=http        - HTTP 健康检查

        # HTTP 健康检查请求
        check_http_send "GET /health_check HTTP/1.1\r\nHost: balance.com\r\nConnection: close\r\n\r\n";

        # 期望的健康响应（2xx 或 3xx 状态码）
        check_http_expect_alive http_2xx http_3xx;
    }

    # 负载均衡服务器
    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://web_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        # 健康检查状态页面
        location /upstream_status {
            check_status;
            access_log off;
        }
    }
}
EOF

# 3. 测试配置
/data/server/nginx/sbin/nginx -t

# 预期输出:
# nginx: the configuration file /data/server/nginx/conf/nginx.conf syntax is ok
# nginx: configuration file /data/server/nginx/conf/nginx.conf test is successful

# 4. 重载配置
/data/server/nginx/sbin/nginx -s reload
```

**配置说明**:
- **server_name balance.com**: 使用预先配置的域名,与文档其他部分保持一致
- **check_http_send**: 健康检查请求中的 Host 头也使用 `balance.com`
- 所有测试命令都需要带 `-H "Host: balance.com"` 参数（除非配置了 /etc/hosts）

#### 14.9.3 健康检查参数详解

| 参数 | 说明 | 默认值 | 推荐值 |
|------|------|--------|--------|
| **interval** | 健康检查间隔（毫秒） | 30000 | 3000-5000 |
| **rise** | 连续成功多少次认为服务器恢复 | 2 | 2-3 |
| **fall** | 连续失败多少次认为服务器不可用 | 5 | 3-5 |
| **timeout** | 超时时间（毫秒） | 1000 | 2000-5000 |
| **type** | 检查类型 | tcp | http/tcp/ssl_hello/mysql/ajp |

**type 类型说明**:

| 类型 | 说明 | 适用场景 |
|------|------|---------|
| **tcp** | TCP 连接检查（只检查端口） | 简单检查、四层代理 |
| **http** | HTTP 请求检查（发送 GET 请求） | Web 服务器、应用服务器 |
| **ssl_hello** | SSL 握手检查 | HTTPS 服务 |
| **mysql** | MySQL 协议检查 | MySQL 数据库 |
| **ajp** | AJP 协议检查 | Tomcat 等 Java 应用 |

---

### 14.10 测试健康检查功能

#### 14.10.1 查看健康状态页面

```bash
# 在 nginx-lb 容器内执行
curl -H "Host: balance.com" http://127.0.0.1/upstream_status

# 或从宿主机访问（使用 balance.com 域名）
curl -H "Host: balance.com" http://localhost:8070/upstream_status

# 如果已配置 /etc/hosts 解析 balance.com
curl http://balance.com:8070/upstream_status
```

**预期输出**:

```html
<!DOCTYPE html>
<html>
<head>
<title>Nginx http upstream check status</title>
</head>
<body>
<h1>Nginx http upstream check status</h1>
<h2>Check upstream server number: 3, generation: 1</h2>
<table>
    <tr>
        <th>Index</th>
        <th>Upstream</th>
        <th>Name</th>
        <th>Status</th>
        <th>Rise counts</th>
        <th>Fall counts</th>
        <th>Check type</th>
        <th>Check port</th>
    </tr>
    <tr>
        <td>0</td>
        <td>web_backend</td>
        <td>10.0.7.71:80</td>
        <td>up</td>        ← 健康状态
        <td>2</td>         ← 连续成功次数
        <td>0</td>         ← 连续失败次数
        <td>http</td>
        <td>80</td>
    </tr>
    <tr>
        <td>1</td>
        <td>web_backend</td>
        <td>10.0.7.72:80</td>
        <td>up</td>
        <td>2</td>
        <td>0</td>
        <td>http</td>
        <td>80</td>
    </tr>
    <tr>
        <td>2</td>
        <td>web_backend</td>
        <td>10.0.7.73:80</td>
        <td>up</td>
        <td>2</td>
        <td>0</td>
        <td>http</td>
        <td>80</td>
    </tr>
</table>
</body>
</html>
```

#### 14.10.2 测试负载均衡

```bash
# 连续请求 10 次,观察响应的服务器（需要带 Host 头）
for i in {1..10}; do
    curl -s -H "Host: balance.com" http://127.0.0.1/
done

# 预期输出（轮询模式）:
# Server: web-1, URI: /
# Server: web-2, URI: /
# Server: web-1, URI: /
# Server: web-2, URI: /
# ...
# 注意: Server: web-3-backup 不会出现（因为是 backup）

# 或使用 grep 过滤查看服务器名称
for i in {1..10}; do
    curl -s -H "Host: balance.com" http://127.0.0.1/ | grep -o "web-[0-9]"
done

# 预期输出:
# web-1
# web-2
# web-1
# web-2
# ...
```

---

### 14.11 模拟服务器故障

#### 14.11.1 停止后端服务器 1

**在新终端执行**:

```bash
# 停止 nginx-web-1 的 Nginx 服务
sudo docker compose exec nginx-web-1 /data/server/nginx/sbin/nginx -s stop

# 或进入容器手动停止
sudo docker compose exec -it nginx-web-1 bash
/data/server/nginx/sbin/nginx -s stop
ps aux | grep nginx  # 确认已停止
exit
```

#### 14.11.2 观察健康检查状态变化

```bash
# 在 nginx-lb 容器内持续监控状态页面
watch -n 1 'curl -s -H "Host: balance.com" http://127.0.0.1/upstream_status | grep -A 3 "10.0.7.71"'

# 预期变化过程:
# 初始状态: Status=up, Rise=2, Fall=0
#    ↓ (等待约 3 秒,第一次检查失败)
# 第 1 次失败: Status=up, Rise=0, Fall=1
#    ↓ (等待约 3 秒,第二次检查失败)
# 第 2 次失败: Status=up, Rise=0, Fall=2
#    ↓ (等待约 3 秒,第三次检查失败)
# 第 3 次失败: Status=down, Rise=0, Fall=3 ← 标记为不可用
```

**完整的状态页面输出**:

```html
<tr>
    <td>0</td>
    <td>web_backend</td>
    <td>10.0.7.71:80</td>
    <td>down</td>      ← 状态变为 down
    <td>0</td>
    <td>3</td>         ← 连续失败 3 次
    <td>http</td>
    <td>80</td>
</tr>
```

#### 14.11.3 验证流量切换

```bash
# 连续请求 10 次,确认流量不再发送到 server 1
for i in {1..10}; do
    curl -s -H "Host: balance.com" http://127.0.0.1/
done

# 预期输出（只有 server 2 响应,server 1 不再出现）:
# Server: web-2, URI: /
# Server: web-2, URI: /
# Server: web-2, URI: /
# ...

# 或使用 grep 确认只有 web-2 响应
for i in {1..10}; do
    curl -s -H "Host: balance.com" http://127.0.0.1/ | grep -o "web-[0-9]"
done

# 预期输出（只有 web-2）:
# web-2
# web-2
# web-2
# ...
```

#### 14.11.4 查看 Nginx 日志

```bash
# 查看访问日志（可以看到 upstream 地址）
tail -f /data/server/nginx/logs/access.log

# 预期输出（服务器故障期间）:
# 10.0.0.12 - - [17/Oct/2025:03:14:32 +0000] "GET / HTTP/1.1" 200 22 "-" "curl/7.76.1" "-" upstream: 10.0.7.71:80, 10.0.7.72:80
# 10.0.0.12 - - [17/Oct/2025:03:14:33 +0000] "GET / HTTP/1.1" 200 22 "-" "curl/7.76.1" "-" upstream: 10.0.7.72:80
# 10.0.0.12 - - [17/Oct/2025:03:14:34 +0000] "GET / HTTP/1.1" 200 22 "-" "curl/7.76.1" "-" upstream: 10.0.7.72:80
# 10.0.0.12 - - [17/Oct/2025:03:14:35 +0000] "GET / HTTP/1.1" 200 22 "-" "curl/7.76.1" "-" upstream: 10.0.7.72:80
# 10.0.0.12 - - [17/Oct/2025:03:14:36 +0000] "GET / HTTP/1.1" 200 22 "-" "curl/7.76.1" "-" upstream: 10.0.7.71:80, 10.0.7.72:80

# 查看错误日志（可以看到健康检查失败和故障转移的完整过程）
tail -f /data/server/nginx/logs/error.log

# 预期输出（真实故障场景）:
# 2025/10/17 03:14:36 [error] 3447#0: *679 connect() failed (111: Connection refused) while connecting to upstream, client: 10.0.0.12, server: balance.com, request: "GET / HTTP/1.1", upstream: "http://10.0.7.71:80/", host: "balance.com"
# 2025/10/17 03:14:36 [warn] 3447#0: *679 upstream server temporarily disabled while connecting to upstream, client: 10.0.0.12, server: balance.com, request: "GET / HTTP/1.1", upstream: "http://10.0.7.71:80/", host: "balance.com"
# 2025/10/17 03:14:37 [error] 3447#0: send() failed (111: Connection refused)
# 2025/10/17 03:14:40 [error] 3447#0: send() failed (111: Connection refused)
# 2025/10/17 03:14:40 [error] 3447#0: disable check peer: 10.0.7.71:80
# 2025/10/17 03:14:43 [error] 3447#0: send() failed (111: Connection refused)
# 2025/10/17 03:14:46 [error] 3447#0: send() failed (111: Connection refused)
# 2025/10/17 03:14:49 [error] 3447#0: send() failed (111: Connection refused)
# 2025/10/17 03:14:52 [error] 3447#0: send() failed (111: Connection refused)
# 2025/10/17 03:14:55 [error] 3447#0: send() failed (111: Connection refused)
```

**错误日志详细分析**:

#### 1. 故障检测时间线

```
03:14:36  [error] connect() failed (111: Connection refused)
          ↓ 用户请求尝试连接 10.0.7.71 失败

03:14:36  [warn] upstream server temporarily disabled
          ↓ Nginx 立即临时禁用该服务器（被动健康检查）

03:14:37  [error] send() failed (111: Connection refused)
          ↓ 主动健康检查第 1 次失败（interval=3000ms）

03:14:40  [error] send() failed (111: Connection refused)
          ↓ 主动健康检查第 2 次失败（+3 秒）

03:14:40  [error] disable check peer: 10.0.7.71:80
          ↓ 连续失败 3 次，正式标记为 down（fall=3）

03:14:43  [error] send() failed (111: Connection refused)
03:14:46  [error] send() failed (111: Connection refused)
03:14:49  [error] send() failed (111: Connection refused)
          ↓ 持续健康检查，等待服务器恢复
```

#### 2. 日志类型说明

| 日志类型 | 触发原因 | 影响 |
|---------|---------|------|
| **[error] connect() failed** | 用户请求连接失败 | 触发故障转移（重试到其他服务器） |
| **[warn] temporarily disabled** | 被动健康检查（max_fails） | 临时禁用服务器（短期） |
| **[error] send() failed** | 主动健康检查失败 | 每 3 秒探测一次 |
| **[error] disable check peer** | 连续失败达到 fall 阈值 | 正式标记为 down（长期） |

#### 3. 错误码说明

| 错误码 | 含义 | 原因 |
|-------|------|------|
| **111: Connection refused** | 连接被拒绝 | 目标服务器未运行或端口未监听 |
| **110: Connection timed out** | 连接超时 | 网络不通或服务器响应慢 |
| **104: Connection reset by peer** | 连接被重置 | 服务器主动断开连接 |

#### 4. 被动健康检查 vs 主动健康检查

**被动健康检查**（Nginx 原生）:
```
03:14:36 [warn] upstream server temporarily disabled
```
- 触发条件: 用户请求失败时触发
- 禁用时间: 短期（默认 10 秒）
- 配置参数: `max_fails=1 fail_timeout=10s`

**主动健康检查**（nginx_upstream_check_module）:
```
03:14:37 [error] send() failed (111: Connection refused)
03:14:40 [error] send() failed (111: Connection refused)
03:14:40 [error] disable check peer: 10.0.7.71:80
```
- 触发条件: 定时器主动探测（interval=3000ms）
- 禁用时间: 长期（直到连续 rise 次成功）
- 配置参数: `check interval=3000 rise=2 fall=3`

#### 5. 故障转移机制

```
┌─────────────────────────────────────────────────────────────┐
│  03:14:36  用户请求到达                                      │
│            ↓                                                 │
│  分配到 10.0.7.71 → connect() failed                         │
│            ↓                                                 │
│  触发被动健康检查 → temporarily disabled                     │
│            ↓                                                 │
│  自动重试到 10.0.7.72 → 成功返回 200                         │
│            ↓                                                 │
│  用户体验: 无感知（自动故障转移）                            │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  03:14:37  主动健康检查开始                                  │
│            ↓                                                 │
│  第 1 次检查失败 (fall_count=1)                              │
│            ↓ +3 秒                                           │
│  第 2 次检查失败 (fall_count=2)                              │
│            ↓ +3 秒                                           │
│  第 3 次检查失败 (fall_count=3)                              │
│            ↓                                                 │
│  正式标记为 down → disable check peer: 10.0.7.71:80         │
│            ↓                                                 │
│  后续请求不再分配到该服务器                                  │
└─────────────────────────────────────────────────────────────┘
```

**日志格式说明**:

| upstream 格式 | 含义 | 说明 |
|--------------|------|------|
| `upstream: 10.0.7.72:80` | 请求直接发送到该服务器并成功 | 健康服务器正常响应 |
| `upstream: 10.0.7.71:80, 10.0.7.72:80` | 请求先发送到 10.0.7.71 失败,自动重试到 10.0.7.72 成功 | **故障转移过程** |

**upstream 双地址详解**:

```
upstream: 10.0.7.71:80, 10.0.7.72:80
           ↑              ↑
       首次尝试        重试成功
     （连接失败）      （返回 200）
```

**为什么会出现双地址?**

1. **故障发生瞬间**: 健康检查模块尚未检测到故障,请求仍然被分配到 10.0.7.71
2. **连接失败**: 10.0.7.71 已停止服务,连接失败或超时
3. **自动重试**: Nginx 自动将请求重试到下一个健康的服务器 10.0.7.72
4. **最终成功**: 10.0.7.72 成功响应,返回 200 状态码

**时间线分析**:

```
03:14:32  请求 → 10.0.7.71 失败 → 重试 10.0.7.72 成功  (双地址)
03:14:33  请求 → 直接发送到 10.0.7.72 成功           (单地址)
03:14:34  请求 → 直接发送到 10.0.7.72 成功           (单地址)
03:14:35  请求 → 直接发送到 10.0.7.72 成功           (单地址)
03:14:36  请求 → 10.0.7.71 失败 → 重试 10.0.7.72 成功  (双地址)
          ↑ 可能是健康检查尝试,或者负载均衡算法仍分配少量流量
```

**关键观察**:

- **03:14:32 和 03:14:36** 出现双地址,表示故障转移正在发生
- **03:14:33 到 03:14:35** 只有单地址,表示健康检查已生效,流量完全切换到 10.0.7.72
- 用户请求不会失败,Nginx 会自动重试到健康服务器
- 这证明了负载均衡的高可用性和故障自愈能力

**⚠️ 重要提示**:

即使健康检查已标记服务器为 down,在以下情况下仍可能出现双地址：
1. **负载均衡算法的惯性**: 某些请求可能在健康检查更新前已经被分配
2. **并发请求**: 多个 worker 进程可能存在短暂的状态不一致
3. **重试机制**: Nginx 的 `proxy_next_upstream` 指令会自动重试失败的请求

这是**正常现象**,不会影响用户体验,因为最终请求都成功了（返回 200）。

---

### 14.12 模拟服务器恢复

#### 14.12.1 启动后端服务器 1

```bash
# 在新终端执行
sudo docker compose exec nginx-web-1 /data/server/nginx/sbin/nginx

# 或进入容器手动启动
sudo docker compose exec -it nginx-web-1 bash
/data/server/nginx/sbin/nginx
ps aux | grep nginx  # 确认已启动
exit
```

#### 14.12.2 观察健康检查恢复过程

```bash
# 在 nginx-lb 容器内持续监控
watch -n 1 'curl -s -H "Host: balance.com" http://127.0.0.1/upstream_status | grep -A 3 "10.0.7.71"'

# 预期变化过程:
# 初始状态: Status=down, Rise=0, Fall=3
#    ↓ (等待约 3 秒,第一次检查成功)
# 第 1 次成功: Status=down, Rise=1, Fall=0
#    ↓ (等待约 3 秒,第二次检查成功)
# 第 2 次成功: Status=up, Rise=2, Fall=0 ← 恢复为可用
```

#### 14.12.3 验证流量恢复

```bash
# 连续请求 20 次,确认 server 1 重新接收流量
for i in {1..20}; do
    curl -s -H "Host: balance.com" http://127.0.0.1/
done

# 预期输出（server 1 和 server 2 轮询）:
# Server: web-1, URI: /
# Server: web-2, URI: /
# Server: web-1, URI: /
# Server: web-2, URI: /
# ...

# 或使用 grep 确认 web-1 和 web-2 都在响应
for i in {1..20}; do
    curl -s -H "Host: balance.com" http://127.0.0.1/ | grep -o "web-[0-9]"
done

# 预期输出（web-1 和 web-2 轮询）:
# web-1
# web-2
# web-1
# web-2
# ...
```

---

### 14.13 高级配置示例

**⚠️ 重要提示**:
- `nginx_upstream_check_module` 只支持 **HTTP 七层负载均衡**的健康检查
- `check` 指令只能用在 `http {}` 块中的 `upstream {}`，不能用在 `stream {}` 块
- Stream 四层代理需要使用 Nginx 原生的被动健康检查（max_fails + fail_timeout）

---

#### 14.13.1 自定义 HTTP 检查路径

**场景**: API 服务通常提供专门的健康检查端点（如 `/api/health`, `/health`, `/status`）

**步骤 1: 配置后端服务器（添加自定义健康检查路径）**

```bash
# 进入 nginx-web-1 容器
sudo docker compose exec -it nginx-web-1 bash

# 修改配置，添加 /api/health 路径
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
pid /data/server/nginx/run/nginx.pid;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;

        # 主路径
        location / {
            return 200 "Server: web-1, URI: $uri\n";
        }

        # 标准健康检查路径
        location /health_check {
            access_log off;  # 健康检查不记录访问日志
            return 200 "OK\n";
        }

        # API 健康检查路径（返回 JSON 格式）
        location /api/health {
            access_log off;  # 健康检查不记录访问日志
            default_type application/json;
            return 200 '{"status":"healthy","server":"web-1","timestamp":"$time_iso8601"}\n';
        }
    }
}
EOF

# 重载配置
/data/server/nginx/sbin/nginx -s reload
exit

# 对 nginx-web-2 执行相同操作
sudo docker compose exec -it nginx-web-2 bash

cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
pid /data/server/nginx/run/nginx.pid;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;

        location / {
            return 200 "Server: web-2, URI: $uri\n";
        }

        location /health_check {
            access_log off;  # 健康检查不记录访问日志
            return 200 "OK\n";
        }

        location /api/health {
            access_log off;  # 健康检查不记录访问日志
            default_type application/json;
            return 200 '{"status":"healthy","server":"web-2","timestamp":"$time_iso8601"}\n';
        }
    }
}
EOF

/data/server/nginx/sbin/nginx -s reload
exit
```

**步骤 2: 验证后端 API 健康检查端点**

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 测试 web-1 的 API 健康检查
curl http://10.0.7.71/api/health

# 预期输出:
# {"status":"healthy","server":"web-1","timestamp":"2025-10-17T03:20:00+00:00"}

# 测试 web-2 的 API 健康检查
curl http://10.0.7.72/api/health

# 预期输出:
# {"status":"healthy","server":"web-2","timestamp":"2025-10-17T03:20:00+00:00"}
```

**步骤 3: 配置负载均衡器使用自定义检查路径**

```bash
# 在 nginx-lb 容器内，修改配置
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /data/server/nginx/logs/error.log warn;
pid /data/server/nginx/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /data/server/nginx/conf/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'upstream: $upstream_addr';

    access_log /data/server/nginx/logs/access.log main;

    sendfile        on;
    keepalive_timeout 65;

    # 使用自定义 API 健康检查路径
    upstream web_backend {
        server 10.0.7.71:80 weight=1;
        server 10.0.7.72:80 weight=1;

        # 健康检查配置（使用 /api/health 路径）
        check interval=3000 rise=2 fall=3 timeout=2000 type=http;

        # 自定义检查请求（检查 /api/health 路径）
        check_http_send "GET /api/health HTTP/1.1\r\nHost: balance.com\r\nConnection: close\r\n\r\n";

        # 期望的响应（2xx 或 3xx 状态码）
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://web_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        location /upstream_status {
            check_status;
            access_log off;
        }
    }
}
EOF

# 测试配置
/data/server/nginx/sbin/nginx -t

# 重载配置
/data/server/nginx/sbin/nginx -s reload
```

**步骤 4: 验证自定义健康检查**

```bash
# 查看健康状态页面
curl -H "Host: balance.com" http://127.0.0.1/upstream_status

# windows chrome访问
balance.com/upstream_status

# 预期输出（Check type 仍为 http，但探测路径已变为 /api/health）:
# <td>10.0.7.71:80</td>
# <td>up</td>
# <td>2</td>
# <td>0</td>
# <td>http</td>

# 查看错误日志（确认使用了 /api/health 路径）
tail -f /data/server/nginx/logs/error.log
# 如果健康检查失败，日志会显示类似:
# check protocol http error with peer: 10.0.7.71:80 (GET /api/health)
```

**配置说明**:
- **check_http_send**: 指定健康检查发送的 HTTP 请求，包括路径、Host 头、Connection 头
- **check_http_expect_alive**: 期望的健康响应状态码（http_2xx 表示 200-299）
- 适用于 RESTful API、微服务健康检查端点

---

#### 14.13.2 不同 upstream 使用不同健康检查策略

**场景**: 针对不同的服务特点，配置不同的健康检查参数

**步骤 1: 配置多个 upstream（不同检查策略）**

```bash
# 在 nginx-lb 容器内配置
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /data/server/nginx/logs/error.log warn;
pid /data/server/nginx/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /data/server/nginx/conf/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'upstream: $upstream_addr';

    access_log /data/server/nginx/logs/access.log main;
    sendfile        on;
    keepalive_timeout 65;

    # Upstream 1: 快速响应的 API 服务（检查频率高、超时短）
    upstream api_backend {
        server 10.0.7.71:80 weight=1;
        server 10.0.7.72:80 weight=1;

        # 高频率健康检查（适合快速 API）
        check interval=2000 rise=2 fall=2 timeout=1000 type=http;
        # interval=2000    - 每 2 秒检查一次（高频）
        # rise=2           - 连续成功 2 次即恢复
        # fall=2           - 连续失败 2 次即下线（快速响应）
        # timeout=1000     - 超时时间 1 秒

        check_http_send "GET /health_check HTTP/1.1\r\nHost: api.balance.com\r\nConnection: close\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    # Upstream 2: 慢速的后台任务服务（检查频率低、超时长）
    upstream task_backend {
        server 10.0.7.71:80 weight=1;
        server 10.0.7.72:80 weight=1;

        # 低频率健康检查（适合慢速服务）
        check interval=10000 rise=3 fall=5 timeout=5000 type=http;
        # interval=10000   - 每 10 秒检查一次（低频）
        # rise=3           - 连续成功 3 次才恢复（谨慎）
        # fall=5           - 连续失败 5 次才下线（容忍偶发故障）
        # timeout=5000     - 超时时间 5 秒（允许慢响应）

        check_http_send "GET /health_check HTTP/1.1\r\nHost: task.balance.com\r\nConnection: close\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    # Upstream 3: 核心业务服务（包含 backup 服务器）
    upstream web_backend {
        server 10.0.7.71:80 weight=2;
        server 10.0.7.72:80 weight=1;
        server 10.0.7.73:80 backup;  # 备用服务器

        # 标准健康检查
        check interval=3000 rise=2 fall=3 timeout=2000 type=http;
        check_http_send "GET /health_check HTTP/1.1\r\nHost: balance.com\r\nConnection: close\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    # API 服务器（快速响应）
    server {
        listen 80;
        server_name api.balance.com;

        location / {
            proxy_pass http://api_backend;
            proxy_set_header Host $host;
            proxy_connect_timeout 2s;  # API 连接超时 2 秒
            proxy_read_timeout 5s;     # API 读取超时 5 秒
        }
    }

    # 后台任务服务器（慢速响应）
    server {
        listen 80;
        server_name task.balance.com;

        location / {
            proxy_pass http://task_backend;
            proxy_set_header Host $host;
            proxy_connect_timeout 10s;  # 任务连接超时 10 秒
            proxy_read_timeout 60s;     # 任务读取超时 60 秒
        }
    }

    # 核心业务服务器
    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://web_backend;
            proxy_set_header Host $host;
        }

        # 健康状态页面（显示所有 upstream）
        location /upstream_status {
            check_status;
            access_log off;
        }
    }
}
EOF

# 测试配置
/data/server/nginx/sbin/nginx -t

# 重载配置
/data/server/nginx/sbin/nginx -s reload
```

**步骤 2: 测试不同 upstream 的健康检查**

```bash
# 查看所有 upstream 的健康状态
curl -H "Host: balance.com" http://127.0.0.1/upstream_status

# 预期输出（显示 3 个 upstream）:
# api_backend - 2 个后端服务器（检查间隔 2 秒）
# task_backend - 2 个后端服务器（检查间隔 10 秒）
# web_backend - 3 个后端服务器（包括 1 个 backup）

# 测试 API 服务（快速响应）
for i in {1..5}; do
    curl -s -H "Host: api.balance.com" http://127.0.0.1/
done

# 测试任务服务（慢速响应）
for i in {1..5}; do
    curl -s -H "Host: task.balance.com" http://127.0.0.1/
done

# 测试核心业务服务
for i in {1..5}; do
    curl -s -H "Host: balance.com" http://127.0.0.1/
done
```

**步骤 3: 观察不同策略的故障响应**

```bash
# 停止一台后端服务器
sudo docker compose exec nginx-web-1 /data/server/nginx/sbin/nginx -s stop

# 观察 api_backend 的快速下线（2 秒检查间隔 × 2 次失败 = 4 秒）
watch -n 1 'curl -s -H "Host: balance.com" http://127.0.0.1/upstream_status | grep -A 8 "api_backend"'

# 观察 task_backend 的慢速下线（10 秒检查间隔 × 5 次失败 = 50 秒）
watch -n 1 'curl -s -H "Host: balance.com" http://127.0.0.1/upstream_status | grep -A 8 "task_backend"'
```

**配置说明**:

| 参数组合 | 适用场景 | 故障发现时间 | 恢复确认时间 |
|---------|---------|-------------|-------------|
| `interval=2000 rise=2 fall=2` | API/快速服务 | 4 秒 | 4 秒 |
| `interval=3000 rise=2 fall=3` | 标准 Web 服务 | 9 秒 | 6 秒 |
| `interval=10000 rise=3 fall=5` | 后台任务/慢服务 | 50 秒 | 30 秒 |

**选择建议**:
1. **API 服务**: 高频检查 + 快速下线，避免影响用户体验
2. **Web 服务**: 中频检查 + 标准容错，平衡性能和可靠性
3. **后台任务**: 低频检查 + 高容错，避免误判慢响应

---

#### 14.13.3 backup 服务器健康检查行为

**场景**: 验证 backup 服务器是否会被健康检查，以及何时会接收流量

**关键问题**:
1. backup 服务器会被健康检查吗？
2. backup 服务器什么时候接收流量？
3. 如果 backup 服务器也 down 了会怎样？

**步骤 1: 配置 backup 服务器并启用健康检查**

```bash
# 在 nginx-lb 容器内配置
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /data/server/nginx/logs/error.log warn;
pid /data/server/nginx/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /data/server/nginx/conf/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'upstream: $upstream_addr';

    access_log /data/server/nginx/logs/access.log main;
    sendfile        on;
    keepalive_timeout 65;

    upstream web_backend {
        server 10.0.7.71:80 weight=1;
        server 10.0.7.72:80 weight=1;
        server 10.0.7.73:80 weight=1 backup;  # backup 服务器

        # 健康检查（包括 backup 服务器）
        check interval=3000 rise=2 fall=3 timeout=2000 type=http;
        check_http_send "GET /health_check HTTP/1.1\r\nHost: balance.com\r\nConnection: close\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://web_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }

        location /upstream_status {
            check_status;
            access_log off;
        }
    }
}
EOF

# 测试并重载
/data/server/nginx/sbin/nginx -t
/data/server/nginx/sbin/nginx -s reload
```

**步骤 2: 验证初始状态（所有服务器正常）**

```bash
# 查看健康状态
curl -s -H "Host: balance.com" http://127.0.0.1/upstream_status | grep -A 3 "10.0.7.7[123]"

# 预期输出（所有服务器都 up，包括 backup）:
# <td>10.0.7.71:80</td>
# <td class="success">up</td>
# ...
# <td>10.0.7.72:80</td>
# <td class="success">up</td>
# ...
# <td>10.0.7.73:80</td>  ← backup 服务器也被检查
# <td class="success">up</td>

# 测试流量分发（backup 不接收流量）
for i in {1..10}; do curl -s -H "Host: balance.com" http://127.0.0.1/; done

# 预期输出（只有 71 和 72，没有 73）:
# Server: web-1, URI: /
# Server: web-2, URI: /
# Server: web-1, URI: /
# Server: web-2, URI: /
# ...（73 不会出现）
```

**步骤 3: 模拟主服务器故障（backup 接管流量）**

```bash
# 停止 nginx-web-1 和 nginx-web-2
sudo docker compose exec nginx-web-1 /data/server/nginx/sbin/nginx -s stop
sudo docker compose exec nginx-web-2 /data/server/nginx/sbin/nginx -s stop

# 等待 9 秒（fail=3 * interval=3s）后查看状态
sleep 10
curl -s -H "Host: balance.com" http://127.0.0.1/upstream_status | grep -A 3 "10.0.7.7[123]"

# 预期输出（71 和 72 down，73 up）:
# <td>10.0.7.71:80</td>
# <td class="error">down</td>
# ...
# <td>10.0.7.72:80</td>
# <td class="error">down</td>
# ...
# <td>10.0.7.73:80</td>  ← backup 服务器健康
# <td class="success">up</td>

# 测试流量分发（所有流量到 backup）
for i in {1..10}; do curl -s -H "Host: balance.com" http://127.0.0.1/; done

# 预期输出（全部是 73）:
# Server: web-3, URI: /
# Server: web-3, URI: /
# Server: web-3, URI: /
# ...（所有流量都到 backup）
```

**步骤 4: 模拟 backup 服务器也故障**

```bash
# 停止 nginx-web-3
sudo docker compose exec nginx-web-3 /data/server/nginx/sbin/nginx -s stop

# 等待 9 秒后查看状态
sleep 10
curl -s -H "Host: balance.com" http://127.0.0.1/upstream_status | grep -A 3 "10.0.7.7[123]"

# 预期输出（所有服务器都 down）:
# <td>10.0.7.71:80</td>
# <td class="error">down</td>
# ...
# <td>10.0.7.72:80</td>
# <td class="error">down</td>
# ...
# <td>10.0.7.73:80</td>  ← backup 服务器也 down
# <td class="error">down</td>

# 尝试访问（会返回 502 Bad Gateway）
curl -i -H "Host: balance.com" http://127.0.0.1/

# 预期输出:
# HTTP/1.1 502 Bad Gateway
# Server: nginx
# ...
# <html>
# <head><title>502 Bad Gateway</title></head>
# <body>
# <center><h1>502 Bad Gateway</h1></center>
# </body>
# </html>
```

**步骤 5: 恢复服务并观察 backup 行为**

```bash
# 恢复主服务器
sudo docker compose exec nginx-web-1 /data/server/nginx/sbin/nginx
sudo docker compose exec nginx-web-2 /data/server/nginx/sbin/nginx

# 等待 6 秒（rise=2 * interval=3s）后查看状态
sleep 7
curl -s -H "Host: balance.com" http://127.0.0.1/upstream_status | grep -A 3 "10.0.7.7[123]"

# 预期输出（71 和 72 恢复 up，73 仍然 down）:
# <td>10.0.7.71:80</td>
# <td class="success">up</td>
# ...
# <td>10.0.7.72:80</td>
# <td class="success">up</td>
# ...
# <td>10.0.7.73:80</td>  ← backup 服务器仍然 down
# <td class="error">down</td>

# 测试流量分发（backup 不再接收流量）
for i in {1..10}; do curl -s -H "Host: balance.com" http://127.0.0.1/; done

# 预期输出（71 和 72，没有 73）:
# Server: web-1, URI: /
# Server: web-2, URI: /
# Server: web-1, URI: /
# ...（即使 73 down，也不影响主服务器）
```

**配置总结**:

| 场景 | 主服务器状态 | backup 服务器状态 | 流量分配 | 访问结果 |
|------|------------|----------------|---------|---------|
| **正常** | up | up | 仅主服务器 | 200 OK（71, 72） |
| **主故障** | down | up | 全部到 backup | 200 OK（73） |
| **全故障** | down | down | 无可用服务器 | 502 Bad Gateway |
| **主恢复** | up | down | 仅主服务器 | 200 OK（71, 72） |

**关键发现**:
1. ✅ **backup 服务器会被健康检查**: 即使不接收流量，健康状态也实时更新
2. ✅ **backup 仅在主服务器全部 down 时接收流量**: 只要有一台主服务器 up，backup 就不会接收流量
3. ✅ **backup 故障不影响主服务器**: 即使 backup 是 down 状态，主服务器正常工作不受影响
4. ✅ **主服务器恢复后立即切回**: 不需要 backup 恢复，主服务器 up 后立即接管流量

---

#### 14.13.4 限制访问健康状态页面

**场景**: 健康状态页面包含敏感信息（后端服务器 IP、状态），需要限制访问

**步骤 1: 配置访问控制**

```bash
# 在 nginx-lb 容器内修改配置
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /data/server/nginx/logs/error.log warn;
pid /data/server/nginx/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /data/server/nginx/conf/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'upstream: $upstream_addr';

    access_log /data/server/nginx/logs/access.log main;
    sendfile        on;
    keepalive_timeout 65;

    upstream web_backend {
        server 10.0.7.71:80 weight=1;
        server 10.0.7.72:80 weight=1;
        check interval=3000 rise=2 fall=3 timeout=2000 type=http;
        check_http_send "GET /health_check HTTP/1.1\r\nHost: balance.com\r\nConnection: close\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    # 业务服务器（80 端口）
    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://web_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }

    # 监控服务器（8080 端口，受限访问）
    server {
        listen 8080;
        server_name _;

        location /upstream_status {
            check_status;
            access_log off;

            # 访问控制列表（ACL）
            allow 127.0.0.1;           # 允许本地访问
            allow 10.0.7.0/24;         # 允许容器内网访问
            allow 10.0.0.0/16;         # 允许办公网访问（根据实际情况修改）
            deny all;                  # 拒绝其他所有 IP
        }
    }
}
EOF

# 测试配置
/data/server/nginx/sbin/nginx -t

# 重载配置
/data/server/nginx/sbin/nginx -s reload
```

**步骤 2: 测试访问控制**

```bash
# 测试 1: 容器内访问（127.0.0.1，应该允许）
curl http://127.0.0.1:8080/upstream_status

# 预期输出: 正常显示健康状态页面
# <html>
# <h1>Nginx http upstream check status</h1>
# ...

# 测试 2: 容器间访问（10.0.7.x，应该允许）
curl http://10.0.7.70:8080/upstream_status

# 预期输出: 正常显示健康状态页面

# 测试 3: 业务端口访问（80 端口，应该拒绝）
curl -H "Host: balance.com" http://127.0.0.1:80/upstream_status

# 预期输出: 404 Not Found（/upstream_status 不在业务服务器上）
```

**步骤 3: 从宿主机测试访问控制**

```bash
# 在宿主机执行（假设 compose.yml 映射了 8080 端口）
# 需要先修改 compose.yml 添加端口映射:
# ports:
#   - "8080:8080"

# 从宿主机访问（10.0.0.x 网段，根据 ACL 配置）
curl http://localhost:8080/upstream_status

# 如果宿主机 IP 在允许列表内，返回健康状态页面
# 如果不在允许列表内，返回 403 Forbidden:
# <html>
# <head><title>403 Forbidden</title></head>
# <body>
# <center><h1>403 Forbidden</h1></center>
# <center>nginx</center>
# </body>
# </html>
```

**步骤 4: 使用 HTTP Basic Auth 增强安全性（可选）**

```bash
# 安装 htpasswd 工具
apt update && apt install -y apache2-utils

# 创建密码文件
htpasswd -c /data/server/nginx/conf/.htpasswd admin
# 输入密码: admin123

# 修改配置添加 Basic Auth（重写整个配置文件）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /data/server/nginx/logs/error.log warn;
pid /data/server/nginx/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /data/server/nginx/conf/mime.types;
    default_type  application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'upstream: $upstream_addr';

    access_log /data/server/nginx/logs/access.log main;
    sendfile        on;
    keepalive_timeout 65;

    upstream web_backend {
        server 10.0.7.71:80 weight=1;
        server 10.0.7.72:80 weight=1;
        check interval=3000 rise=2 fall=3 timeout=2000 type=http;
        check_http_send "GET /health_check HTTP/1.1\r\nHost: balance.com\r\nConnection: close\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }

    # 业务服务器（80 端口）
    server {
        listen 80;
        server_name balance.com;

        location / {
            proxy_pass http://web_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }

    # 监控服务器（8080 端口，受限访问 + Basic Auth）
    server {
        listen 8080;
        server_name _;

        location /upstream_status {
            check_status;
            access_log off;

            # HTTP Basic Auth（用户名密码认证）
            auth_basic "Nginx Monitoring";
            auth_basic_user_file /data/server/nginx/conf/.htpasswd;

            # IP 白名单（IP 访问控制）
            allow 127.0.0.1;           # 允许本地访问
            allow 10.0.7.0/24;         # 允许容器内网访问
            allow 10.0.0.0/16;         # 允许办公网访问（根据实际情况修改）
            allow 192.168.0.0/16;
            deny all;                  # 拒绝其他所有 IP
        }
    }
}
EOF

# 测试配置
/data/server/nginx/sbin/nginx -t

# 重载配置
/data/server/nginx/sbin/nginx -s reload

# 测试（需要输入用户名和密码）
curl -u admin:admin123 http://127.0.0.1:8080/upstream_status

# 预期输出: 正常显示健康状态页面

# 不带认证访问（应该返回 401）
curl http://127.0.0.1:8080/upstream_status

# 预期输出:
# <html>
# <head><title>401 Authorization Required</title></head>
# <body>
# <center><h1>401 Authorization Required</h1></center>
# </body>
# </html>
```

**配置说明**:
- **allow/deny**: 基于 IP 的访问控制（按顺序匹配，第一个匹配的规则生效）
- **auth_basic**: HTTP 基本认证（用户名+密码）
- **双重保护**: IP 白名单 + 密码认证，更安全
- **access_log off**: 监控页面不记录访问日志，减少日志量

**安全建议**:
1. **最小权限原则**: 只允许必要的 IP 访问
2. **使用 HTTPS**: 避免密码明文传输（需要配置 SSL 证书）
3. **定期更换密码**: 避免密码泄露
4. **使用强密码**: 避免使用弱密码（如 admin/123456）
5. **监控访问日志**: 定期检查是否有异常访问

---

### 14.14 监控与告警

#### 14.14.1 编写健康检查脚本

```bash
# 创建监控脚本
cat > /tmp/check_upstream.sh <<'EOF'
#!/bin/bash
# Nginx upstream 健康检查监控脚本

STATUS_URL="http://127.0.0.1/upstream_status"
ALERT_EMAIL="admin@example.com"

# 获取状态页面（需要带 Host 头）
STATUS=$(curl -s -H "Host: balance.com" $STATUS_URL)

# 检查是否有 down 的服务器
DOWN_COUNT=$(echo "$STATUS" | grep -c "<td>down</td>")

if [ $DOWN_COUNT -gt 0 ]; then
    echo "警告: 有 $DOWN_COUNT 台后端服务器不可用"
    echo "$STATUS" | grep -B 2 "<td>down</td>"

    # 发送告警（需要配置邮件服务）
    # echo "$STATUS" | mail -s "Nginx Upstream Alert" $ALERT_EMAIL
fi
EOF

chmod +x /tmp/check_upstream.sh

# 测试脚本
/tmp/check_upstream.sh
```

#### 14.14.2 使用 cron 定期检查

```bash
# 添加 cron 任务（每分钟检查一次）
# crontab -e
# 添加以下行:
# */1 * * * * /tmp/check_upstream.sh >> /var/log/upstream_check.log 2>&1
```

---

### 14.15 故障排除

#### 问题 1: 编译失败 "unknown directive check"

**原因**: 补丁未成功应用或编译时未添加模块

```bash
# 解决方法 1: 确认补丁已应用
cd /data/softs/nginx-1.24.0
grep -r "ngx_http_upstream_check" src/http/

# 如果没有输出,说明补丁未应用,重新打补丁
patch -p1 < /data/softs/nginx_upstream_check_module-master/check_1.20.1+.patch

# 解决方法 2: 确认 configure 包含 --add-module
/data/server/nginx/sbin/nginx -V 2>&1 | grep check
```

#### 问题 2: 健康检查状态一直是 down

**原因**: 后端服务器未响应健康检查请求

```bash
# 排查步骤 1: 确认后端服务器正常运行
curl http://10.0.7.71/health_check

# 排查步骤 2: 检查健康检查路径是否存在
sudo docker compose exec nginx-web-1 cat /data/server/nginx/html/health_check

# 排查步骤 3: 查看 Nginx 错误日志
tail -f /data/server/nginx/logs/error.log | grep check

# 排查步骤 4: 使用 tcpdump 抓包
tcpdump -i eth0 -nn host 10.0.7.71 and port 80
```

#### 问题 3: check_status 页面 404

**原因**: check_status 指令未正确配置

```bash
# 检查配置
/data/server/nginx/sbin/nginx -T | grep check_status

# 确认 location 配置正确
location /upstream_status {
    check_status;  # 必须在 location 内
    access_log off;
}

# 重载配置
/data/server/nginx/sbin/nginx -s reload
```

---

### 14.16 性能优化建议

| 参数 | 默认值 | 推荐值 | 说明 |
|------|--------|--------|------|
| **interval** | 30000ms | 3000-5000ms | 检查间隔越短,故障发现越快,但负载越高 |
| **timeout** | 1000ms | 2000-5000ms | 超时时间应 < interval |
| **fall** | 5 | 3-5 | 失败次数越少,下线越快,但误判风险增加 |
| **rise** | 2 | 2-3 | 成功次数越少,恢复越快,但误判风险增加 |

**计算公式**:

```
故障发现时间 = interval × fall
最小故障时间 = 3 秒 × 3 次 = 9 秒

恢复发现时间 = interval × rise
最小恢复时间 = 3 秒 × 2 次 = 6 秒
```

---

### 14.17 测试检查清单

- [ ] **模块安装**
  - [ ] 下载 nginx_upstream_check_module 模块
  - [ ] 应用补丁文件成功
  - [ ] 重新编译 Nginx 成功
  - [ ] 验证模块已加载（nginx -V 包含 check）

- [ ] **健康检查配置**
  - [ ] 配置 check 指令
  - [ ] 配置 check_http_send
  - [ ] 配置 check_http_expect_alive
  - [ ] 配置 check_status 页面

- [ ] **功能测试**
  - [ ] 访问 /upstream_status 页面成功
  - [ ] 所有后端服务器状态为 up
  - [ ] 负载均衡正常工作

- [ ] **故障场景测试**
  - [ ] 停止一台后端服务器
  - [ ] 观察状态从 up 变为 down
  - [ ] 确认流量不再发送到故障服务器
  - [ ] 启动故障服务器
  - [ ] 观察状态从 down 变为 up
  - [ ] 确认流量恢复到该服务器

---

### 14.18 常见问题

**Q1: nginx_upstream_check_module 是否支持所有 Nginx 版本?**

**答**: 不完全支持。建议使用以下版本:
- Nginx 1.20.x 及以上（使用 check_1.20.1+.patch）
- Nginx 1.16.x - 1.19.x（使用 check_1.16.1+.patch）
- 最新版本可能需要等待模块更新

**Q2: 健康检查会影响性能吗?**

**答**: 影响很小。每个后端服务器每 interval 毫秒接收一次探测请求,负载可以忽略不计。

**Q3: 可以同时配置主动和被动健康检查吗?**

**答**: 可以。建议配置:
```nginx
upstream backend {
    server 10.0.7.71:80 max_fails=3 fail_timeout=30s;  # 被动检查
    check interval=5000 rise=2 fall=3 timeout=2000 type=http;  # 主动检查
}
```

**Q4: backup 服务器会进行健康检查吗?**

**答**: 会。backup 服务器也会定期进行健康检查,只是在主服务器可用时不接收流量。

---

## 🌐 第十五部分:四层代理与负载

### 15.1 四层代理基础知识

**简介**:
- Nginx 在 1.9.0 版本开始支持 tcp 模式的负载均衡
- 在 1.9.13 版本开始支持 udp 协议的负载
- udp 主要用于 DNS 的域名解析
- 其配置方式和指令和 http 代理类似
- 基于 ngx_stream_proxy_module 模块实现 tcp 负载
- 基于 ngx_stream_upstream_module 模块实现后端服务器分组转发、权重分配、状态监测、调度算法等高级功能

**配置位置**:
- **stream 指令应该位于与 http 指令平行的顶层上下文中**
- 默认情况下,stream 指令和 http 指令都是顶层指令
- 它们不能嵌套在彼此内部,也不能位于 server 或 location 块中

### 15.2 编译安装注意事项

**stream 模块编译选项完整说明**:

| 编译选项 | 说明 | 使用场景 |
|---------|------|---------|
| **--with-stream** | 静态编译 stream 模块到 nginx 二进制文件中 | 编译安装 Nginx |
| **--with-stream=dynamic** | 动态编译 stream 模块为独立的 .so 文件 | apt/yum 安装 Nginx |
| **--with-stream_ssl_module** | 启用 stream SSL/TLS 支持 | 四层 SSL 代理 |
| **--with-stream_realip_module** | 启用真实 IP 获取功能 | 获取客户端真实 IP |
| **--with-stream_geoip_module** | 启用 GeoIP 地理位置功能 | 基于地理位置调度 |

**静态编译方式**（编译安装）:
```bash
# 编译时需要指定 --with-stream 选项才能支持 ngx_stream_proxy_module 模块
./configure --prefix=/data/server/nginx \
    --with-stream \           # enable TCP/UDP proxy module
    --with-stream_ssl_module  # enable stream SSL support
make
make install
```

**动态加载方式**（apt 安装）:
- 如果用 apt 方式安装的 nginx,默认是 --with-stream=dynamic 动态加载
- 需要通过如下命令加载模块:
```nginx
# 在 nginx.conf 最顶部添加
load_module /usr/lib/nginx/modules/ngx_stream_module.so;
```

**参考资料**:
- http://nginx.org/en/docs/stream/ngx_stream_proxy_module.html （非http协议的反向代理）
- https://nginx.org/en/docs/stream/ngx_stream_upstream_module.html （非http协议的负载均衡）

### 15.3 Stream 模块环境准备

#### 15.3.1 检查 stream 模块

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 检查 nginx 编译参数
/data/server/nginx/sbin/nginx -V 2>&1 | grep -o 'with-stream[^ ]*'

# 预期输出应包含:
# --with-stream 或 --with-stream=dynamic
```

#### 15.3.2 Stream 模块排查步骤

**步骤 1: 测试配置文件语法**

```bash
# 测试配置
/data/server/nginx/sbin/nginx -t
```

**如果出现错误**:
```
nginx: [emerg] unknown directive "stream" in /data/server/nginx/conf/nginx.conf:10
nginx: configuration file /data/server/nginx/conf/nginx.conf test failed
```

**步骤 2: 检查编译参数**

```bash
# 查看 nginx 编译参数
/data/server/nginx/sbin/nginx -V

# 预期输出应包含:
# --with-stream 或 --with-stream=dynamic
```

**步骤 3: 检查模块文件位置**

```bash
# 如果是动态模块,检查模块文件是否存在
ls -l /usr/lib/nginx/modules/ngx_stream_module.so

# 预期输出:
# -rw-r--r-- 1 root root 123456 Oct 12 10:00 /usr/lib/nginx/modules/ngx_stream_module.so
```

**步骤 4: 重新编译（如果没有 stream 支持）**

```bash
# 进入 nginx 源码目录
cd /path/to/nginx-source

# 重新配置
./configure --prefix=/data/server/nginx \
    --with-stream \
    --with-stream_ssl_module

# 编译
make

# 备份旧的 nginx 二进制文件
mv /data/server/nginx/sbin/nginx /data/server/nginx/sbin/nginx.bak

# 复制新的 nginx 二进制文件
cp objs/nginx /data/server/nginx/sbin/nginx

# 验证编译参数
/data/server/nginx/sbin/nginx -V | grep stream
```

**步骤 5: 加载 stream 模块（动态模块）**

**⚠️ 重要提示: load_module 指令必须在配置文件的最顶部（在所有其他指令之前）**

```bash
# 编辑 nginx 配置文件（全局配置段）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
# 加载 stream 模块（必须在最顶部）
load_module /usr/lib/nginx/modules/ngx_stream_module.so;

worker_processes auto;
events {
    worker_connections 1024;
}

# http 配置段
http {
    server {
        listen 80;
        location / {
            return 200 "HTTP Server\n";
        }
    }
}

# stream 配置段（与 http 平级）
stream {
    include /data/server/nginx/conf/stream_configs/*.conf;
}
EOF

# 创建 stream 配置目录
mkdir -p /data/server/nginx/conf/stream_configs

# 测试配置
/data/server/nginx/sbin/nginx -t
```

**步骤 6: 测试成功的输出**

```bash
# 预期输出:
nginx: the configuration file /data/server/nginx/conf/nginx.conf syntax is ok
nginx: configuration file /data/server/nginx/conf/nginx.conf test is successful
```

### 15.4 准备 MySQL 服务器

本示例使用官方 MySQL 8.0 镜像,已通过 docker-compose.yaml 自动配置。

#### 15.4.1 查看 MySQL 服务状态

```bash
# 查看 MySQL 容器状态
docker ps | grep mysql-server

# 预期输出:
# CONTAINER ID   IMAGE        COMMAND                  STATUS         PORTS
# abc123def456   mysql:8.0    "docker-entrypoint.s…"   Up 2 minutes   0.0.0.0:3307->3306/tcp
```

#### 15.4.2 测试 MySQL 连接

**MySQL 配置说明**（已在 compose.yaml 中配置）:
- 根用户: `root` / `rootpass123`
- 普通用户: `testuser` / `testpass`
- 默认数据库: `testdb`
- 监听地址: `0.0.0.0` （允许远程连接）

```bash
# 方式1: 从容器内部连接
sudo docker compose exec -it mysql-server bash
mysql -u testuser -ptestpass -e "SELECT VERSION();"

# 预期输出:
+-----------+
| VERSION() |
+-----------+
| 8.0.40    |
+-----------+

 

# 查看容器内 MySQL 监听端口
sudo docker compose exec -it mysql-server bash
ss -tnlp | grep 3306

# 预期输出:
# LISTEN  0  151  0.0.0.0:3306  0.0.0.0:*  users:(("mysqld",pid=1,fd=23))
```

#### 15.4.3 测试 MySQL 数据操作

```bash
# 连接并执行 SQL 语句
mysql -h 127.0.0.1 -P 3306 -u testuser -ptestpass testdb <<EOF
CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50)
);
INSERT INTO users (name) VALUES ('Alice'), ('Bob'), ('Charlie');
SELECT * FROM users;
EOF

# 预期输出:
+----+---------+
| id | name    |
+----+---------+
|  1 | Alice   |
|  2 | Bob     |
|  3 | Charlie |
+----+---------+
```

### 15.5 准备 Redis 服务器

本示例使用官方 Redis 7.0 镜像,已通过 docker-compose.yaml 自动配置。

#### 15.5.1 查看 Redis 服务状态

```bash
# 查看 Redis 容器状态
docker ps | grep redis-server

# 预期输出:
# CONTAINER ID   IMAGE        COMMAND                  STATUS         PORTS
# def456abc789   redis:7.0    "docker-entrypoint.s…"   Up 2 minutes   0.0.0.0:6380->6379/tcp
```

#### 15.5.2 测试 Redis 连接

**Redis 配置说明**（已在 compose.yaml 中配置）:
- 监听地址: `0.0.0.0` （允许远程连接）
- 保护模式: `no` （允许无密码连接）
- 默认端口: `6379`

```bash
# 方式1: 从容器内部连接
sudo docker compose exec -it redis-server bash
redis-cli ping

# 预期输出:
PONG
 

# 查看容器内 Redis 监听端口
sudo docker compose exec -it redis-server bash
ss -tnlp | grep 6379

# 预期输出:
# LISTEN  0  511  0.0.0.0:6379  0.0.0.0:*  users:(("redis-server",pid=1,fd=6))
```

#### 15.5.3 测试 Redis 基本操作

```bash
# 测试 SET/GET 命令（从宿主机）
redis-cli -h 127.0.0.1 -p 6379 SET mykey "Hello Nginx Load Balancer"
redis-cli -h 127.0.0.1 -p 6379 GET mykey

# 预期输出:
OK
"Hello Nginx Load Balancer"

# 测试更多命令
redis-cli -h 127.0.0.1 -p 6379 <<EOF
SET counter 100
INCR counter
INCR counter
GET counter
MSET key1 "value1" key2 "value2" key3 "value3"
MGET key1 key2 key3
EOF

# 预期输出:
OK
(integer) 101
(integer) 102
"102"
OK
1) "value1"
2) "value2"
3) "value3"

# 查看 Redis 服务器信息
redis-cli -h 127.0.0.1 -p 6379 INFO SERVER

# 预期输出:
# Server
redis_version:7.0.15
redis_git_sha1:00000000
redis_git_dirty:0
redis_build_id:1234567890abcdef
redis_mode:standalone
os:Linux 6.14.0-33-generic x86_64
arch_bits:64
monotonic_clock:POSIX clock_gettime
multiplexing_api:epoll
atomicvar_api:c11-builtin
gcc_version:12.2.0
process_id:1
process_supervised:no
run_id:1234567890abcdef1234567890abcdef12345678
tcp_port:6379
server_time_usec:1728740123456789
uptime_in_seconds:120
uptime_in_days:0
hz:10
configured_hz:10
lru_clock:1234567
executable:/usr/local/bin/redis-server
config_file:
io_threads_active:0
```

### 15.6 配置四层代理

#### 15.6.1 配置负载均衡器的四层代理

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# ⚠️ 前置条件检查: 确认 nginx.conf 已包含 stream 配置块
# 如果以下命令没有输出，请先执行 15.3.2 节的步骤 5
grep -A 2 "stream {" /data/server/nginx/conf/nginx.conf

# 预期输出应包含:
stream {
    include /data/server/nginx/conf/stream_configs/*.conf;
}

# 确认 stream_configs 目录存在
ls -ld /data/server/nginx/conf/stream_configs

# 预期输出:
# drwxr-xr-x 2 root root 4096 Oct 17 10:00 /data/server/nginx/conf/stream_configs

# 如果以上检查失败，请返回 15.3.2 节完成 stream 模块配置

# 创建 stream 配置文件
cat > /data/server/nginx/conf/stream_configs/tcp.conf <<'EOF'
upstream mysqlserver {
    server 10.0.7.76:3306;
}

upstream redisserver {
    server 10.0.7.77:6379;
}

server {
    listen 3306;
    proxy_pass mysqlserver;
}

server {
    listen 6379;
    proxy_pass redisserver;
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload

# 检查监听端口
netstat -tnlp | grep nginx
# 预期输出应包含:
# tcp  0  0.0.0.0:3306  0.0.0.0:*  LISTEN  xxx/nginx: master
# tcp  0  0.0.0.0:6379  0.0.0.0:*  LISTEN  xxx/nginx: master
```

### 15.7 安装客户端工具

#### 15.7.1 安装 MySQL 客户端

```bash
# Ubuntu 系统
apt update
apt install -y mysql-client

# Rocky/CentOS 系统
yum install -y mysql
```

#### 15.7.2 安装 Redis 客户端

```bash
# Ubuntu 系统
apt update
apt install -y redis-tools

# Rocky/CentOS 系统
yum install -y redis
```

### 15.8 测试四层代理效果

#### 15.8.1 测试 MySQL 四层代理

**测试连接**:

```bash
# 在宿主机使用 mysql 客户端通过负载均衡器连接
# 注意：这里连接的是负载均衡器的 3306 端口，会被代理到 10.0.7.76:3306
mysql -h 10.0.7.70 -P 3306 -u testuser -ptestpass -e "SELECT VERSION();"

# 预期输出:
+-----------+
| VERSION() |
+-----------+
| 8.0.40    |
+-----------+
```

**测试数据库操作**:

```bash
# 通过负载均衡器创建数据库和表
mysql -h 10.0.7.70 -P 3306 -u testuser -ptestpass <<EOF
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;
CREATE TABLE IF NOT EXISTS users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO users (name) VALUES ('Alice'), ('Bob'), ('Charlie');
SELECT * FROM users;
EOF

# 预期输出:
+----+---------+---------------------+
| id | name    | created_at          |
+----+---------+---------------------+
|  1 | Alice   | 2025-10-16 10:00:00 |
|  2 | Bob     | 2025-10-16 10:00:00 |
|  3 | Charlie | 2025-10-16 10:00:00 |
+----+---------+---------------------+
```

**验证代理路径**:

```bash
# 1. 在负载均衡器容器中查看连接
sudo docker compose exec -it nginx-lb bash
ss -tnep | grep 3306

# 预期输出（显示到后端 MySQL 的连接）:
# ESTAB  0  0  10.0.7.70:45678  10.0.7.76:3306  users:(("nginx",pid=123,fd=10))

# 2. 在 MySQL 容器中查看连接
sudo docker compose exec -it mysql-server bash
ss -tnep | grep 3306

# 预期输出（显示来自负载均衡器的连接）:
# ESTAB  0  0  10.0.7.76:3306  10.0.7.70:45678  users:(("mysqld",pid=1,fd=25))
```

#### 15.8.2 测试 Redis 四层代理

**测试连接**:

```bash
# 在宿主机使用 redis-cli 通过负载均衡器连接
# 注意：这里连接的是负载均衡器的 6379 端口，会被代理到 10.0.7.77:6379
redis-cli -h 10.0.7.70 -p 6379 ping

# 预期输出:
PONG
```

**测试 Redis 基本操作**:

```bash
# 测试 SET/GET 命令
redis-cli -h 10.0.7.70 -p 6379 SET proxykey "Hello Nginx Proxy"
redis-cli -h 10.0.7.70 -p 6379 GET proxykey

# 预期输出:
OK
"Hello Nginx Proxy"

# 测试更多复杂命令
redis-cli -h 10.0.7.70 -p 6379 <<EOF
LPUSH mylist "item1" "item2" "item3"
LRANGE mylist 0 -1
HSET myhash field1 "value1" field2 "value2"
HGETALL myhash
EOF

# 预期输出:
(integer) 3
1) "item3"
2) "item2"
3) "item1"
(integer) 2
1) "field1"
2) "value1"
3) "field2"
4) "value2"

# 查看 Redis 服务器信息
redis-cli -h 10.0.7.70 -p 6379 INFO SERVER | head -15

# 预期输出:
# Server
redis_version:7.0.15
redis_git_sha1:00000000
redis_git_dirty:0
redis_build_id:1234567890abcdef
redis_mode:standalone
os:Linux 6.14.0-33-generic x86_64
arch_bits:64
multiplexing_api:epoll
process_id:1
tcp_port:6379
uptime_in_seconds:600
...
```

**验证代理路径**:

```bash
# 1. 在负载均衡器容器中查看连接
sudo docker compose exec -it nginx-lb bash
ss -tnep | grep 6379

# 预期输出（显示到后端 Redis 的连接）:
# ESTAB  0  0  10.0.7.70:56789  10.0.7.77:6379  users:(("nginx",pid=124,fd=11))

# 2. 在 Redis 容器中查看连接
sudo docker compose exec -it redis-server bash
ss -tnep | grep 6379

# 预期输出（显示来自负载均衡器的连接）:
# ESTAB  0  0  10.0.7.77:6379  10.0.7.70:56789  users:(("redis-server",pid=1,fd=8))
```

**测试结果说明**:
- ✅ MySQL 四层代理成功将 3306 端口的请求转发到后端 MySQL 服务器（10.0.7.76:3306）
- ✅ Redis 四层代理成功将 6379 端口的请求转发到后端 Redis 服务器（10.0.7.77:6379）
- ✅ 四层代理完全透明,客户端无需知道后端服务器的真实 IP
- ✅ Nginx stream 模块支持 TCP 协议的完整双向通信
- ✅ 数据库和缓存操作完全正常,无任何功能限制

---

## 🐘 第十六部分:FastCGI 代理（PHP）

### 16.1 FastCGI 基础知识

**FastCGI 简介**:
- Nginx 的 FastCGI 代理是一项关键功能
- 它允许 Nginx 将客户端的请求路由并转发给运行 FastCGI 协议的后端服务
- 从而处理动态内容请求
- 这些后端服务通常由各种框架和编程语言（如 PHP）构建

**参考资料**:
- http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html

### 16.2 FastCGI 核心指令

#### 16.2.1 fastcgi_index

```nginx
fastcgi_index name;
# 后端 FastCGI 服务器默认资源,默认值为空
# 作用域:http, server, location
```

#### 16.2.2 fastcgi_pass

```nginx
fastcgi_pass address;
# 指定后端 FastCGI 服务器地址,可以写 IP:port,也可以指定 socket 文件
# 作用域:location, if in location
```

#### 16.2.3 fastcgi_param

```nginx
fastcgi_param parameter value [if_not_empty];
# 设置传递给 FastCGI 服务器的参数值
# 作用域:http, server, location
# 可用于将 Nginx 的内置变量赋值给自定义 key
```

### 16.3 PHP-FPM 配置文件

**注意**:本示例中,我们将使用模拟方式演示 FastCGI 配置,因为容器环境中安装 PHP-FPM 较为复杂。实际生产环境中需要安装 PHP-FPM。

#### 16.3.1 PHP-FPM 主要配置项

**查看主配置文件**:

```bash
# 查看 PHP-FPM 主配置文件（Ubuntu 系统）
grep -E "^[^;]" /etc/php/8.3/fpm/php-fpm.conf

# 预期输出:
[global]
pid = /run/php/php8.3-fpm.pid
error_log = /var/log/php8.3-fpm.log
syslog.facility = daemon
syslog.ident = php-fpm
log_level = notice
emergency_restart_threshold = 0
emergency_restart_interval = 0
process_control_timeout = 0
process.max = 128
process.priority = -19
daemonize = yes
rlimit_files = 1024
rlimit_core = 0
events.mechanism = epoll
systemd_interval = 10
include=/etc/php/8.3/fpm/pool.d/*.conf
```

**主要参数说明**:

| 参数 | 说明 | 默认值 | 推荐值 |
|------|------|--------|--------|
| **pid** | PID 文件位置 | /run/php/php-fpm.pid | - |
| **error_log** | 错误日志文件 | /var/log/php-fpm.log | - |
| **log_level** | 日志级别 | notice | notice |
| **emergency_restart_threshold** | 紧急重启阈值（子进程在此时间内异常退出的数量） | 0（不重启） | 10 |
| **emergency_restart_interval** | 紧急重启时间间隔 | 0 | 1m |
| **process_control_timeout** | 子进程接收主进程信号的超时时间 | 0 | 10s |
| **process.max** | 最大进程数（包括所有 pool） | 128 | 根据内存调整 |
| **process.priority** | 进程优先级（-19 到 20） | -19 | -19 |
| **daemonize** | 是否后台运行 | yes | yes |
| **rlimit_files** | 文件描述符限制 | 1024 | 65535 |
| **events.mechanism** | 事件机制 | epoll（Linux） | epoll |

#### 16.3.2 Web 配置详解（Pool 配置）

**查看 Pool 配置文件**:

```bash
# 查看默认 Pool 配置
grep -E "^[^;]" /etc/php/8.3/fpm/pool.d/www.conf

# 主要配置参数
```

**Pool 主要参数说明**:

| 参数 | 说明 | 默认值 | 推荐值 |
|------|------|--------|--------|
| **[www]** | Pool 名称 | www | 自定义 |
| **user** | 运行用户 | www-data | www-data |
| **group** | 运行组 | www-data | www-data |
| **listen** | 监听地址 | /run/php/php8.3-fpm.sock | 127.0.0.1:9000 或 socket |
| **listen.owner** | Socket 文件所有者 | www-data | www-data |
| **listen.group** | Socket 文件所属组 | www-data | www-data |
| **listen.mode** | Socket 文件权限 | 0660 | 0660 |
| **pm** | 进程管理方式 | dynamic | dynamic |
| **pm.max_children** | 最大子进程数 | 5 | 50-100 |
| **pm.start_servers** | 启动时进程数 | 2 | 10-20 |
| **pm.min_spare_servers** | 最小空闲进程数 | 1 | 5-10 |
| **pm.max_spare_servers** | 最大空闲进程数 | 3 | 20-35 |
| **pm.max_requests** | 每个子进程处理的最大请求数 | 500 | 10000 |
| **request_terminate_timeout** | 请求超时时间 | 0（不限制） | 300s |
| **request_slowlog_timeout** | 慢日志阈值 | 0（不记录） | 5s |
| **slowlog** | 慢日志文件 | /var/log/php-fpm-slow.log | - |

**重要配置详解**:

```ini
; 进程管理方式
pm = dynamic                      ; 动态管理（根据负载调整进程数）
; pm = static                     ; 静态管理（固定进程数）
; pm = ondemand                   ; 按需启动（无请求时无进程）

; 动态模式配置
pm.max_children = 50              ; 最大子进程数
pm.start_servers = 10             ; 启动时进程数
pm.min_spare_servers = 5          ; 最小空闲进程数
pm.max_spare_servers = 20         ; 最大空闲进程数
pm.max_requests = 10000           ; 每个进程最多处理10000个请求后重启

; 健康检查
ping.path = /ping                 ; Ping 路径
ping.response = pong              ; Ping 响应内容

; 状态页面
pm.status_path = /status          ; 状态页面路径

; 日志配置
access.log = /var/log/php-fpm-access.log
access.format = "%R - %u %t \"%m %r\" %s"
slowlog = /var/log/php-fpm-slow.log
request_slowlog_timeout = 5s      ; 超过5秒记录慢日志

; 安全设置
chdir = /                         ; 启动时切换到的目录
catch_workers_output = yes        ; 捕获worker输出
clear_env = no                    ; 不清除环境变量
security.limit_extensions = .php .phar  ; 限制可执行的文件扩展名
```

### 16.4 Nginx 和 PHP 集成配置模板

#### 16.4.1 配置模板 1（使用 socket）

```nginx
location ~ \.php$ {
    include /data/server/nginx/conf/fastcgi.conf;
    fastcgi_pass unix:/run/php/php8.3-fpm.sock;  # 或者其他版本的 socket 路径
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include fastcgi_params;  # 引用预定义的 FastCGI 参数
}
```

#### 16.4.2 配置模板 2（使用 TCP）

```nginx
location ~ \.php$ {
    fastcgi_pass 127.0.0.1:9000;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include fastcgi_params;
}
```

### 16.5 FastCGI 配置文件说明

#### 16.5.1 文件对比说明

```bash
# 在容器中查看区别
sudo docker compose exec -it nginx-lb bash

# 查看文件是否存在
ls /data/server/nginx/conf/fastcgi*

# 对比两个文件的差异
diff /data/server/nginx/conf/fastcgi.conf /data/server/nginx/conf/fastcgi_params

# 预期输出（唯一的差异）:
1d0
< fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;
```

**差异说明**:
- `fastcgi.conf` 比 `fastcgi_params` 多一行: `SCRIPT_FILENAME` 参数
- 其他内容完全相同

#### 16.5.2 SCRIPT_FILENAME 参数的重要性

**⚠️ SCRIPT_FILENAME 是 PHP-FPM 必需的参数**:

| 参数 | 说明 | 重要性 |
|------|------|--------|
| **SCRIPT_FILENAME** | 指定 PHP 脚本的完整路径 | ✅ **必需** |
| **作用** | PHP-FPM 通过此参数找到要执行的 PHP 文件 | 缺少会导致 404 或 500 错误 |
| **值** | `$document_root$fastcgi_script_name` | 组合网站根目录和请求的脚本名 |

**示例**:
```
请求: http://example.com/test.php
$document_root = /data/server/nginx/html
$fastcgi_script_name = /test.php
SCRIPT_FILENAME = /data/server/nginx/html/test.php
```

#### 16.5.3 创建配置文件

**如果文件不存在,创建 fastcgi_params**:
cat > /data/server/nginx/conf/fastcgi_params <<'EOF'
fastcgi_param  QUERY_STRING       $query_string;
fastcgi_param  REQUEST_METHOD     $request_method;
fastcgi_param  CONTENT_TYPE       $content_type;
fastcgi_param  CONTENT_LENGTH     $content_length;

fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param  REQUEST_URI        $request_uri;
fastcgi_param  DOCUMENT_URI       $document_uri;
fastcgi_param  DOCUMENT_ROOT      $document_root;
fastcgi_param  SERVER_PROTOCOL    $server_protocol;
fastcgi_param  REQUEST_SCHEME     $scheme;
fastcgi_param  HTTPS              $https if_not_empty;

fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

fastcgi_param  REMOTE_ADDR        $remote_addr;
fastcgi_param  REMOTE_PORT        $remote_port;
fastcgi_param  SERVER_ADDR        $server_addr;
fastcgi_param  SERVER_PORT        $server_port;
fastcgi_param  SERVER_NAME        $server_name;

# PHP only, required if PHP was built with --enable-force-cgi-redirect
fastcgi_param  REDIRECT_STATUS    200;
EOF

# 创建 fastcgi.conf（包含 SCRIPT_FILENAME）
cat > /data/server/nginx/conf/fastcgi.conf <<'EOF'
fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;
fastcgi_param  QUERY_STRING       $query_string;
fastcgi_param  REQUEST_METHOD     $request_method;
fastcgi_param  CONTENT_TYPE       $content_type;
fastcgi_param  CONTENT_LENGTH     $content_length;

fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param  REQUEST_URI        $request_uri;
fastcgi_param  DOCUMENT_URI       $document_uri;
fastcgi_param  DOCUMENT_ROOT      $document_root;
fastcgi_param  SERVER_PROTOCOL    $server_protocol;
fastcgi_param  REQUEST_SCHEME     $scheme;
fastcgi_param  HTTPS              $https if_not_empty;

fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

fastcgi_param  REMOTE_ADDR        $remote_addr;
fastcgi_param  REMOTE_PORT        $remote_port;
fastcgi_param  SERVER_ADDR        $server_addr;
fastcgi_param  SERVER_PORT        $server_port;
fastcgi_param  SERVER_NAME        $server_name;

# PHP only, required if PHP was built with --enable-force-cgi-redirect
fastcgi_param  REDIRECT_STATUS    200;
EOF
```

**两个文件的区别**:
- `fastcgi.conf` 包含了 `SCRIPT_FILENAME` 参数
- `fastcgi_params` 不包含 `SCRIPT_FILENAME` 参数
- 如果使用 `fastcgi_params`,需要额外添加一行:
  ```nginx
  fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
  ```

#### 16.5.4 文件包含顺序的详细解释

**⚠️ 重要: 理解配置覆盖机制**

**场景 1: 错误的包含顺序（会导致问题）**

```nginx
location ~ \.php$ {
    # 先包含 fastcgi.conf（包含 SCRIPT_FILENAME）
    include /data/server/nginx/conf/fastcgi.conf;

    # 再包含 fastcgi_params（不包含 SCRIPT_FILENAME）
    include /data/server/nginx/conf/fastcgi_params;

    fastcgi_pass 127.0.0.1:9000;
    fastcgi_index index.php;
}
```

**问题分析**:
1. `fastcgi.conf` 定义了 `SCRIPT_FILENAME` 参数
2. `fastcgi_params` 中所有相同名称的参数会覆盖前面的设置
3. 虽然 `fastcgi_params` 没有定义 `SCRIPT_FILENAME`,但它重新定义了其他所有参数
4. **Nginx 在后包含的文件中遇到相同的 fastcgi_param 指令时会覆盖之前的设置**
5. 最终 `SCRIPT_FILENAME` 保留（因为 fastcgi_params 没有重新定义它）

**⚠️ 但这种方式不推荐**:虽然技术上可行,但容易造成混乱

**场景 2: 正确的包含顺序（推荐方式 1）**

```nginx
location ~ \.php$ {
    # 方式1: 只包含 fastcgi.conf（已包含所有必需参数）
    include /data/server/nginx/conf/fastcgi.conf;

    fastcgi_pass 127.0.0.1:9000;
    fastcgi_index index.php;
}
```

**优点**:
- ✅ 简洁明了
- ✅ `SCRIPT_FILENAME` 已包含
- ✅ 所有标准 FastCGI 参数已包含

**场景 3: 正确的包含顺序（推荐方式 2）**

```nginx
location ~ \.php$ {
    # 方式2: 先手动设置 SCRIPT_FILENAME,再包含 fastcgi_params
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include /data/server/nginx/conf/fastcgi_params;

    fastcgi_pass 127.0.0.1:9000;
    fastcgi_index index.php;
}
```

**优点**:
- ✅ 明确指定 `SCRIPT_FILENAME`
- ✅ 其他参数从 `fastcgi_params` 继承
- ✅ 易于理解和维护

**场景 4: 错误示例（缺少 SCRIPT_FILENAME）**

```nginx
location ~ \.php$ {
    # ❌ 错误: 只包含 fastcgi_params,没有定义 SCRIPT_FILENAME
    include /data/server/nginx/conf/fastcgi_params;

    fastcgi_pass 127.0.0.1:9000;
    fastcgi_index index.php;
}
```

**后果**:
- ❌ PHP-FPM 收不到 `SCRIPT_FILENAME` 参数
- ❌ 无法找到要执行的 PHP 文件
- ❌ 返回 404 或 500 错误

**最佳实践总结**:

| 方式 | 配置 | 优缺点 | 推荐度 |
|------|------|--------|--------|
| **方式1** | 只包含 `fastcgi.conf` | 简单,所有参数齐全 | ⭐⭐⭐⭐⭐ |
| **方式2** | 手动设置 `SCRIPT_FILENAME` + `fastcgi_params` | 灵活,易于自定义 | ⭐⭐⭐⭐ |
| **方式3** | 先 `fastcgi.conf` 后 `fastcgi_params` | 容易混淆,不推荐 | ⭐⭐ |
| **方式4** | 只包含 `fastcgi_params` | ❌ 缺少必需参数 | ❌ 错误 |

**⚠️ 建议**:
- **生产环境推荐**: 只包含 `fastcgi.conf`,简单可靠
- **需要自定义时**: 手动设置 `SCRIPT_FILENAME` 后包含 `fastcgi_params`
- **避免混用**: 不要同时包含两个文件

### 16.6 FastCGI 代理配置示例

**注意**:本示例仅展示配置方式,实际运行需要安装 PHP-FPM。

```bash
# 进入负载均衡器容器
sudo docker compose exec -it nginx-lb bash

# 配置 FastCGI 代理
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    include mime.types;
    default_type application/octet-stream;

    server {
        listen 80;
        root /data/wwwroot/php;
        index index.php index.html;

        # 静态文件处理
        location / {
            try_files $uri $uri/ =404;
        }

        # PHP 文件处理
        location ~ \.php$ {
            include fastcgi.conf;
            fastcgi_pass 127.0.0.1:9000;  # PHP-FPM 监听地址
            fastcgi_index index.php;
        }
    }
}
EOF

# 创建测试 PHP 文件
mkdir -p /data/wwwroot/php
cat > /data/wwwroot/php/index.php <<'EOF'
<?php
phpinfo();
?>
EOF

cat > /data/wwwroot/php/test.php <<'EOF'
<?php
echo "test.php\n";
?>
EOF
```

### 16.7 测试 FastCGI 代理

**⚠️ 前提条件**: 需要先安装并启动 PHP-FPM

#### 16.7.1 安装 PHP-FPM（如果未安装）

```bash
# Ubuntu 系统
apt update
apt install -y php8.3-fpm php8.3-cli

# Rocky/CentOS 系统
yum install -y php-fpm php-cli

# 启动 PHP-FPM（Ubuntu）
service php8.3-fpm start

# 启动 PHP-FPM（Rocky）
systemctl start php-fpm

# 检查 PHP-FPM 是否运行
ps aux | grep php-fpm
# 或
ss -tnlp | grep 9000
```

#### 16.7.2 测试静态文件访问

```bash
# 进入 DNS 客户端容器测试静态文件
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

curl http://balance.com/

# 预期输出:
404 Not Found 或静态页面内容
```

#### 16.7.3 测试 PHP 脚本执行

```bash
# 测试 test.php
curl http://balance.com/test.php

# 预期输出:
test.php

# 测试 index.php（phpinfo）
curl http://balance.com/index.php

# 预期输出（部分 HTML）:
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml"><head>
<style type="text/css">
body {background-color: #fff; color: #222; font-family: sans-serif;}
...
<tr><td class="e">PHP Version </td><td class="v">8.3.10 </td></tr>
...
```

#### 16.7.4 验证 PHP-FPM 日志

```bash
# 查看 PHP-FPM 访问日志（Ubuntu）
tail -f /var/log/php8.3-fpm.log

# 预期输出:
[12-Oct-2025 10:00:00] NOTICE: fpm is running, pid 1234
[12-Oct-2025 10:00:05] NOTICE: ready to handle connections
```

#### 16.7.5 测试 PHP-FPM 状态页面（如果已配置）

```bash
# 如果配置了 pm.status_path = /status
curl http://balance.com/status

# 预期输出:
pool:                 www
process manager:      dynamic
start time:           12/Oct/2025:10:00:00 +0000
start since:          3600
accepted conn:        150
listen queue:         0
max listen queue:     0
listen queue len:     128
idle processes:       5
active processes:     1
total processes:      6
max active processes: 3
max children reached: 0
slow requests:        0
```

**测试结果说明**:
- ✅ 静态文件直接由 Nginx 处理
- ✅ `.php` 文件由 Nginx 转发给 PHP-FPM 处理
- ✅ PHP-FPM 正确执行 PHP 脚本并返回结果
- ✅ FastCGI 代理配置成功

---

## 📋 第十七部分:测试检查清单

### 17.1 负载均衡基础

- [ ] 理解负载均衡的工作原理和特点
- [ ] 理解 Nginx upstream 指令的作用
- [ ] 掌握 server 指令的各项参数（weight、max_conns、backup、down）
- [ ] 理解健康检测机制（被动检查）

### 17.2 调度算法

- [ ] 掌握轮询（默认）调度算法
- [ ] 掌握权重（weight）调度算法
- [ ] 掌握 ip_hash 调度算法
- [ ] 掌握 hash key 调度算法
- [ ] 理解一致性哈希（consistent hash）原理

### 17.3 高级特性

- [ ] 掌握最大连接数限制（max_conns）
- [ ] 掌握备用服务器配置（backup）
- [ ] 掌握平滑下线配置（down）
- [ ] 理解 nginx_upstream_check_module 主动健康检测

### 17.4 四层代理

- [ ] 掌握 stream 模块的配置
- [ ] 掌握 TCP 协议的四层代理
- [ ] 理解 stream 与 http 配置的区别
- [ ] 掌握动态加载 stream 模块的方法

### 17.5 FastCGI 代理

- [ ] 理解 FastCGI 协议的作用
- [ ] 掌握 fastcgi_pass 指令的使用
- [ ] 理解 fastcgi.conf 和 fastcgi_params 的区别
- [ ] 掌握 Nginx 与 PHP-FPM 的集成配置

---

## ❓ 第十八部分:常见问题

### Q1: upstream 健康检测是主动还是被动?

**答**:Nginx 默认的 upstream 健康检测是**被动检测**。

- 当有客户端请求被调度到该服务器上时,会在 TCP 协议层的三次握手时检查该服务器是否可用
- 如果不可用就调度到别的服务器
- 当不可用的次数达到指定次数时（默认是1次,由 max_fails 决定）,在规定时间内（默认是10S,由 fail_timeout 决定）,不会再向该服务器调度请求

如需**主动检测**,需要使用第三方模块 nginx_upstream_check_module。

---

### Q2: 普通 hash 和一致性 hash 的区别?

**答**:

| 特性 | 普通 Hash | 一致性 Hash |
|------|----------|------------|
| **算法** | hash(key) % N（N为服务器数量） | hash(key) % 2^32,顺时针找最近节点 |
| **节点变化影响** | 所有数据重新分配 | 只影响相邻节点,其他节点不变 |
| **缓存失效** | 新增/删除节点导致大量缓存失效 | 新增/删除节点只影响少量缓存 |
| **使用场景** | 服务器数量固定 | 服务器数量动态变化 |

**配置示例**:
```nginx
# 普通 hash
upstream backend {
    hash $remote_addr;
    server 10.0.7.71;
    server 10.0.7.72;
}

# 一致性 hash
upstream backend {
    hash $remote_addr consistent;  # 添加 consistent 参数
    server 10.0.7.71;
    server 10.0.7.72;
}
```

---

### Q3: backup 服务器在什么情况下会被使用?

**答**:backup 服务器只在以下情况下被使用:

1. **所有主服务器都不可用**
2. **所有主服务器都达到最大连接数**

**测试方法**:
```bash
# 停止所有主服务器
cd /home/www/docker-man/07.nginx/07.manual-balance/
sudo docker compose exec -it nginx-web-1 /data/server/nginx/sbin/nginx -s stop
sudo docker compose exec -it nginx-web-2 /data/server/nginx/sbin/nginx -s stop

# 进入 DNS 客户端容器测试
cd /home/www/docker-man/01.dns/03.manual-master-slave-dns/
sudo docker compose exec -it dns-client bash

# 此时请求会被转发到 backup 服务器
curl http://balance.com
# 预期输出:RealServer-3-Backup
```

---

### Q4: down 参数和 backup 参数的区别?

**答**:

| 参数 | 作用 | 使用场景 |
|------|------|---------|
| **down** | 标记服务器临时不可用,新请求不再调度到此服务器 | 平滑下线服务器进行维护 |
| **backup** | 标记服务器为备用,只有所有主服务器不可用时才使用 | 设置备用服务器,提高可用性 |

**配置示例**:
```nginx
upstream backend {
    server 10.0.7.71;
    server 10.0.7.72 down;     # 临时下线,不接受新请求
    server 10.0.7.73 backup;   # 备用,仅主服务器不可用时启用
}
```

---

### Q5: 如何实现会话保持（Session Sticky）?

**答**:有以下几种方法:

**方法1:使用 ip_hash**
```nginx
upstream backend {
    ip_hash;  # 基于客户端IP的hash
    server 10.0.7.71;
    server 10.0.7.72;
}
```

**方法2:使用 hash $remote_addr**
```nginx
upstream backend {
    hash $remote_addr;  # 基于客户端IP的hash
    server 10.0.7.71;
    server 10.0.7.72;
}
```

**方法3:使用 hash $cookie_SESSIONID**（基于 cookie）
```nginx
upstream backend {
    hash $cookie_SESSIONID;  # 基于 session cookie
    server 10.0.7.71;
    server 10.0.7.72;
}
```

---

### Q6: stream 模块配置失败怎么办?

**答**:按以下步骤排查:

**步骤1:检查编译参数**
```bash
/data/server/nginx/sbin/nginx -V 2>&1 | grep stream
```

**步骤2:如果没有 stream 支持,重新编译**
```bash
./configure --with-stream
make
```

**步骤3:如果是动态模块,加载模块**
```nginx
# 在 nginx.conf 最顶部添加
load_module /usr/lib/nginx/modules/ngx_stream_module.so;
```

**步骤4:检查配置文件结构**
```nginx
# stream 必须与 http 平级
worker_processes auto;
events {
    worker_connections 1024;
}

http {
    # http 配置
}

stream {
    # stream 配置（与 http 平级,不能嵌套）
}
```

---

### Q7: max_conns 如何计算实际最大连接数?

**答**:

**计算公式**:
```
实际最大连接数 = worker 进程数 × max_conns
```

**示例**:
```nginx
worker_processes 4;  # 4 个 worker 进程

upstream backend {
    server 10.0.7.71 max_conns=2;  # 每个 worker 最多 2 个连接
    server 10.0.7.72;
}

# 10.0.7.71 实际最大连接数 = 4 × 2 = 8
```

**验证方法**:
```bash
# 在后端服务器查看连接数
ss -tnep | grep 80 | wc -l
```

---

## 🧹 清理环境

```bash
# 1. 停止所有容器
sudo docker compose down

# 2. 删除网络（可选）
docker network rm 07manual-balance_nginx-net

# 3. 完全清理（包括镜像）
sudo docker compose down --rmi all
```

---

## 📖 参考资料

- **Nginx 负载均衡官方文档**: http://nginx.org/en/docs/http/load_balancing.html
- **ngx_http_upstream_module**: http://nginx.org/en/docs/http/ngx_http_upstream_module.html
- **ngx_stream_proxy_module**: http://nginx.org/en/docs/stream/ngx_stream_proxy_module.html
- **ngx_stream_upstream_module**: https://nginx.org/en/docs/stream/ngx_stream_upstream_module.html
- **ngx_http_fastcgi_module**: http://nginx.org/en/docs/http/ngx_http_fastcgi_module.html

---

## 🔗 相关项目

- **07.nginx/01.manual-install**: Nginx 安装实践
- **07.nginx/06.manual-proxy**: Nginx 反向代理实践
- **07.nginx/05.manual-advanced**: Nginx 高级功能实践

---

**完成时间**: 2025-10-12
**文档版本**: v1.0
**维护者**: docker-man 项目组
