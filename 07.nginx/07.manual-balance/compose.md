# Docker Compose Nginx 负载均衡完整实践指南

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
├── 10.0.7.76  - MySQL 模拟服务器（mysql-mock）
└── 10.0.7.77  - Redis 模拟服务器（redis-mock）
```

### 2.2 服务说明

| 服务名 | IP地址 | 端口映射 | 系统 | 角色 |
|--------|--------|----------|------|------|
| nginx-lb | 10.0.7.70 | 8070:80, 3306:3306, 6379:6379 | Ubuntu | 负载均衡器 |
| nginx-web-1 | 10.0.7.71 | 8071:80 | Rocky | 后端 Web 服务器 |
| nginx-web-2 | 10.0.7.72 | 8072:80 | Ubuntu | 后端 Web 服务器 |
| nginx-web-3 | 10.0.7.73 | 8073:80 | Rocky | 备用 Web 服务器 |
| mysql-mock | 10.0.7.76 | 3307:3306 | Ubuntu | MySQL 模拟服务器 |
| redis-mock | 10.0.7.77 | 6380:6379 | Rocky | Redis 模拟服务器 |

---

## 🚀 第三部分:环境启动

### 3.1 启动所有服务

```bash
# 1. 进入项目目录
cd /home/www/docker-man/07.nginx/07.manual-balance

# 2. 启动所有容器
docker compose up -d

# 3. 检查容器状态
docker compose ps

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

#### 5.1.1 进入负载均衡器容器

```bash
docker compose exec -it nginx-lb bash
```

#### 5.1.2 配置后端服务器 1（nginx-web-1）

```bash
# 进入容器
docker compose exec -it nginx-web-1 bash

# 创建测试页面
mkdir -p /data/server/nginx/html
echo "RealServer-1" > /data/server/nginx/html/index.html

# 配置 Nginx
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/server/nginx/html;
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
docker compose exec -it nginx-web-2 bash

# 创建测试页面
mkdir -p /data/server/nginx/html
echo "RealServer-2" > /data/server/nginx/html/index.html

# 配置 Nginx
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/server/nginx/html;
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
docker compose exec -it nginx-web-3 bash

# 创建测试页面
mkdir -p /data/server/nginx/html
echo "RealServer-3-Backup" > /data/server/nginx/html/index.html

# 配置 Nginx
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/server/nginx/html;
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
docker compose exec -it nginx-lb bash

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
        listen 80 default_server;
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
# 在宿主机测试
curl http://localhost:8070
# 预期输出:RealServer-1

curl http://localhost:8070
# 预期输出:RealServer-2

curl http://localhost:8070
# 预期输出:RealServer-1

curl http://localhost:8070
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
docker compose exec -it nginx-lb bash

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
        listen 80 default_server;
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
# 在宿主机测试
curl http://localhost:8070
# 预期输出:RealServer-1

curl http://localhost:8070
# 预期输出:RealServer-1

curl http://localhost:8070
# 预期输出:RealServer-1

curl http://localhost:8070
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
docker compose exec -it nginx-lb bash

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
        listen 80 default_server;
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
docker compose exec -it nginx-web-1 bash

# 创建 10MB 测试文件
mkdir -p /data/server/nginx/html
dd if=/dev/zero of=/data/server/nginx/html/10.img bs=10M count=1

# 配置限速 10KB/s
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/server/nginx/html;
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
docker compose exec -it nginx-web-2 bash

# 创建 10MB 测试文件
mkdir -p /data/server/nginx/html
dd if=/dev/zero of=/data/server/nginx/html/10.img bs=10M count=1

# 配置限速 10KB/s
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen 80 default_server;
        root /data/server/nginx/html;
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
# 在宿主机执行多次 wget（20次）
for i in {1..20}; do wget http://localhost:8070/10.img & done

# 查看下载进程
ps aux | grep wget

# 进入 nginx-web-1 容器,查看连接数量
docker compose exec -it nginx-web-1 bash
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

### 6.5 配置多个 Upstream

```bash
# 进入负载均衡器容器
docker compose exec -it nginx-lb bash

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
        server_name group1.example.com;
        location / {
            proxy_pass http://group1;
        }
    }

    # 使用 server_name 匹配 group2
    server {
        listen 80;
        server_name group2.example.com;
        location / {
            proxy_pass http://group2;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 6.6 测试多 Upstream 效果

```bash
# 在宿主机测试 group1（通过 Host 头指定）
curl -H "Host: group1.example.com" http://localhost:8070
# 预期输出:
# RealServer-1

curl -H "Host: group1.example.com" http://localhost:8070
# 预期输出:
# RealServer-1

# 测试 group2（通过 Host 头指定）
curl -H "Host: group2.example.com" http://localhost:8070
# 预期输出:
# RealServer-2

curl -H "Host: group2.example.com" http://localhost:8070
# 预期输出:
# RealServer-2
```

**结果说明**:
- 使用不同的 server_name 可以将请求调度到不同的 upstream 组
- group1.example.com 的请求调度到 10.0.7.71
- group2.example.com 的请求调度到 10.0.7.72
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
docker compose exec -it nginx-lb bash

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
        listen 80 default_server;
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
# 在宿主机测试
curl http://localhost:8070
# 预期输出:RealServer-1

curl http://localhost:8070
# 预期输出:RealServer-2

curl http://localhost:8070
# 预期输出:RealServer-1
```

**结果说明**:正常访问时,都是主服务器响应

### 8.4 测试备用服务器（故障情况）

```bash
# 停止 nginx-web-1 服务
docker compose exec -it nginx-web-1 bash
/data/server/nginx/sbin/nginx -s stop
exit

# 停止 nginx-web-2 服务
docker compose exec -it nginx-web-2 bash
/data/server/nginx/sbin/nginx -s stop
exit

# 在宿主机测试
curl http://localhost:8070
# 预期输出:RealServer-3-Backup

curl http://localhost:8070
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

### 9.2 配置平滑下线

```bash
# 进入负载均衡器容器
docker compose exec -it nginx-lb bash

# 配置平滑下线（10.0.7.72 准备下线）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    # 10.0.7.72 准备下线
    upstream backend {
        server 10.0.7.71;
        server 10.0.7.72 down;
    }

    server {
        listen 80 default_server;
        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 9.3 测试平滑下线效果

```bash
# 重启所有后端服务器
docker compose exec -it nginx-web-1 /data/server/nginx/sbin/nginx
docker compose exec -it nginx-web-2 /data/server/nginx/sbin/nginx

# 在宿主机测试
curl http://localhost:8070
# 预期输出:RealServer-1

curl http://localhost:8070
# 预期输出:RealServer-1

curl http://localhost:8070
# 预期输出:RealServer-1
```

**结果说明**:
- 因为我们标记 10.0.7.72 主机 down
- 所以,客户端的请求都是 10.0.7.71 在响应
- 10.0.7.72 主机,可以从容下线

---

## 🔐 第十部分:源IP地址hash实践

### 10.1 ip_hash 算法说明

**ip_hash 工作原理**:
- 源地址hash调度方法
- 基于客户端的 remote_addr 做hash计算
- **以实现会话保持（Session Sticky）**

### 10.2 配置 ip_hash

```bash
# 进入负载均衡器容器
docker compose exec -it nginx-lb bash

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
        listen 80 default_server;
        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 10.3 测试 ip_hash 效果

```bash
# 客户端1测试（宿主机）
curl http://localhost:8070
# 预期输出:RealServer-1（固定）

curl http://localhost:8070
# 预期输出:RealServer-1（固定）

curl http://localhost:8070
# 预期输出:RealServer-1（固定）

# 客户端2测试（进入 nginx-web-1 容器测试）
docker compose exec -it nginx-web-1 bash
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

### 11.2 配置自定义 Key Hash（基于 $remote_addr）

```bash
# 进入负载均衡器容器
docker compose exec -it nginx-lb bash

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
        listen 80 default_server;
        location / {
            proxy_pass http://backend;
        }
    }
}
EOF

# 重新加载配置
/data/server/nginx/sbin/nginx -s reload
```

### 11.3 测试自定义 Key Hash 效果

```bash
# 客户端1测试（宿主机）
curl http://localhost:8070
# 预期输出:RealServer-1（固定）

curl http://localhost:8070
# 预期输出:RealServer-1（固定）

# 客户端2测试（进入 nginx-web-1 容器测试）
docker compose exec -it nginx-web-1 bash
curl 10.0.7.70
# 预期输出:RealServer-2（固定）

curl 10.0.7.70
# 预期输出:RealServer-2（固定）
```

**结果说明**:
- 使用 `$remote_addr` 作为 hash key
- 效果与 `ip_hash` 相同
- 但可以灵活更换为其他变量（如 $request_uri）

---

## 🔄 第十二部分:Hash 算法详解

### 12.1 普通 Hash 原理分析

#### 12.1.1 权重相同的 Hash 配置

```nginx
# 完整配置示例
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    upstream backend {
        hash $remote_addr;
        server 10.0.0.111;
        server 10.0.0.112;
        server 10.0.0.113;
    }

    server {
        listen 80;
        location / {
            # 传递原始 Host 头到后端
            proxy_set_header Host $http_host;
            proxy_pass http://backend;
        }
    }
}
```

**调度算法**:hash($remote_addr) % 3

#### 12.1.2 调度示例（3台服务器）

| hash($remote_addr) | hash($remote_addr) % 3 | server |
|-------------------|------------------------|--------|
| 3, 6, 9 | 0, 0, 0 | 10.0.0.111 |
| 1, 4, 7 | 1, 1, 1 | 10.0.0.112 |
| 2, 5, 8 | 2, 2, 2 | 10.0.0.113 |

#### 12.1.3 新增服务器后的问题

**新增一台服务器后,总权重变为 4**:

| hash($remote_addr) | hash($remote_addr) % 4 | server |
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
- 用于实现对后端服务器的健康检查功能
- 通过定期发送探测请求并分析响应,自动识别不健康的服务器并将其从负载均衡池中临时移除
- 待恢复正常后再重新加入

**编译方式**:
```bash
./configure --add-module=/path/to/nginx_upstream_check_module
```

### 14.2 工作原理1 - 主动健康检查机制

1. **定期探测**:模块会按照配置的时间间隔（interval）向后端服务器发送特定类型的探测请求（如 HTTP、TCP 等）
2. **响应分析**:通过分析响应结果判断服务器是否健康
3. **标记不可用**:当连续失败次数达到阈值（fall）时,标记服务器为不可用

### 14.3 工作原理2 - 状态管理

**内部状态表**:
- 模块为每个后端服务器维护一个内部状态表
- 状态信息包括:健康状态、连续成功/失败次数、上次检查时间等
- 这些状态信息存储在共享内存中,确保 worker 进程间同步

### 14.4 工作原理3 - 集成负载均衡

1. 当服务器被标记为不可用时,Nginx 在负载均衡决策中会自动跳过该服务器
2. 不影响现有连接,但新请求不会再分配到不健康的服务器
3. 支持多种负载均衡算法（轮询、IP 哈希等）

### 14.5 健康检查配置示例

```nginx
upstream backend {
    # 后端服务器列表
    server backend1.example.com:80 weight=5;
    server backend2.example.com:80;

    # 健康检查基本设置
    check interval=5000 rise=2 fall=3 timeout=1000 type=http;
    # interval=5000    - 检查间隔（毫秒）
    # rise=2           - 连续成功多少次认为服务器恢复
    # fall=3           - 连续失败多少次认为服务器不可用
    # timeout=1000     - 超时时间（毫秒）
    # type=http        - 检查类型（http/tcp/ssl_hello/mysql/ajp）

    # HTTP 检查特有的设置
    check_http_send "GET /health_check HTTP/1.1\r\nHost: backend\r\nConnection: close\r\n\r\n";
    check_http_expect_alive http_2xx http_3xx;
}

# 自定义状态页面（可选）
server {
    listen 8080;
    location /upstream_status {
        check_status;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
```

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
docker compose exec -it nginx-lb bash

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

### 15.4 准备 MySQL 模拟服务器

**⚠️ 说明**: 本示例提供两种方式:
1. **简单模拟方式**（使用 Nginx stream 模拟,便于快速测试）
2. **真实安装方式**（安装真实 MySQL 服务器）

#### 15.4.1 方式一: 使用 Nginx 模拟 MySQL（快速测试）

```bash
# 进入 mysql-mock 容器
docker compose exec -it mysql-mock bash

# 配置 Nginx 监听 3306 端口（模拟 MySQL）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
load_module /usr/lib/nginx/modules/ngx_stream_module.so;

worker_processes auto;
events {
    worker_connections 1024;
}

stream {
    server {
        listen 3306;
        return "MySQL Mock Server on 10.0.7.76:3306\n";
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx
```

#### 15.4.2 方式二: 安装真实 MySQL 服务器（生产环境）

```bash
# 进入 mysql-mock 容器（Ubuntu 系统）
docker compose exec -it mysql-mock bash

# 1. 安装 MySQL 服务器
apt update
apt install -y mysql-server

# 2. 修改 MySQL 配置,允许远程访问
cat >> /etc/mysql/mysql.conf.d/mysqld.cnf <<'EOF'

# 允许远程连接
bind-address = 0.0.0.0
EOF

# 3. 启动 MySQL 服务
service mysql start

# 4. 查看 MySQL 监听端口
ss -tnlp | grep 3306
# 预期输出:
# LISTEN  0  80  0.0.0.0:3306  0.0.0.0:*  users:(("mysqld",pid=1234,fd=25))

# 5. 登录 MySQL
mysql -u root

# 6. 创建远程访问用户
mysql> CREATE USER 'testuser'@'%' IDENTIFIED BY 'testpass';
mysql> GRANT ALL PRIVILEGES ON *.* TO 'testuser'@'%';
mysql> FLUSH PRIVILEGES;
mysql> EXIT;

# 7. 测试本地连接
mysql -u testuser -ptestpass -e "SELECT VERSION();"
# 预期输出:
# +-----------+
# | VERSION() |
# +-----------+
# | 8.0.39    |
# +-----------+
```

### 15.5 准备 Redis 模拟服务器

**⚠️ 说明**: 本示例提供两种方式:
1. **简单模拟方式**（使用 Nginx stream 模拟,便于快速测试）
2. **真实安装方式**（安装真实 Redis 服务器）

#### 15.5.1 方式一: 使用 Nginx 模拟 Redis（快速测试）

```bash
# 进入 redis-mock 容器
docker compose exec -it redis-mock bash

# 配置 Nginx 监听 6379 端口（模拟 Redis）
cat > /data/server/nginx/conf/nginx.conf <<'EOF'
load_module /usr/lib/nginx/modules/ngx_stream_module.so;

worker_processes auto;
events {
    worker_connections 1024;
}

stream {
    server {
        listen 6379;
        return "Redis Mock Server on 10.0.7.77:6379\n";
    }
}
EOF

# 启动 Nginx
/data/server/nginx/sbin/nginx
```

#### 15.5.2 方式二: 安装真实 Redis 服务器（生产环境）

```bash
# 进入 redis-mock 容器（Rocky 系统）
docker compose exec -it redis-mock bash

# 1. 安装 Redis 服务器
yum install -y redis

# 2. 修改 Redis 配置,允许远程访问
sed -i 's/^bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf

# 或手动编辑
# vim /etc/redis/redis.conf
# 找到: bind 127.0.0.1
# 改为: bind 0.0.0.0

# 3. 启动 Redis 服务
redis-server /etc/redis/redis.conf --daemonize yes

# 4. 查看 Redis 监听端口
ss -tnlp | grep 6379
# 预期输出:
# LISTEN  0  128  0.0.0.0:6379  0.0.0.0:*  users:(("redis-server",pid=1234,fd=6))

# 5. 测试本地连接
redis-cli ping
# 预期输出:
# PONG

# 6. 测试 SET/GET 命令
redis-cli SET testkey "Hello Redis"
redis-cli GET testkey
# 预期输出:
# "Hello Redis"

# 7. 查看 Redis 服务器信息
redis-cli INFO SERVER | head -20
# 预期输出:
# # Server
# redis_version:7.0.15
# redis_git_sha1:00000000
# redis_git_dirty:0
# redis_build_id:1234567890abcdef
# redis_mode:standalone
# os:Linux 6.11.0-29-generic x86_64
# arch_bits:64
# multiplexing_api:epoll
# ...
```

### 15.6 配置四层代理

#### 15.6.1 配置负载均衡器的四层代理

```bash
# 进入负载均衡器容器
docker compose exec -it nginx-lb bash

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

#### 15.8.1 测试 MySQL 代理（模拟方式）

```bash
# 在宿主机测试（使用 telnet 或 nc）
telnet localhost 3306
# 预期输出:MySQL Mock Server on 10.0.7.76:3306

# 或使用 nc
nc localhost 3306
# 预期输出:MySQL Mock Server on 10.0.7.76:3306
```

#### 15.8.2 测试 MySQL 代理（真实安装）

```bash
# 在宿主机使用 mysql 客户端连接
mysql -h 127.0.0.1 -P 3306 -u testuser -ptestpass -e "SELECT VERSION();"

# 预期输出（完整版本信息表格）:
+-----------+
| VERSION() |
+-----------+
| 8.0.39    |
+-----------+

# 测试数据库操作
mysql -h 127.0.0.1 -P 3306 -u testuser -ptestpass <<EOF
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;
CREATE TABLE IF NOT EXISTS users (id INT PRIMARY KEY, name VARCHAR(50));
INSERT INTO users VALUES (1, 'Alice'), (2, 'Bob');
SELECT * FROM users;
EOF

# 预期输出:
+----+-------+
| id | name  |
+----+-------+
|  1 | Alice |
|  2 | Bob   |
+----+-------+
```

#### 15.8.3 测试 Redis 代理（模拟方式）

```bash
# 在宿主机测试（使用 telnet 或 nc）
telnet localhost 6379
# 预期输出:Redis Mock Server on 10.0.7.77:6379

# 或使用 nc
nc localhost 6379
# 预期输出:Redis Mock Server on 10.0.7.77:6379
```

#### 15.8.4 测试 Redis 代理（真实安装）

```bash
# 在宿主机使用 redis-cli 连接
redis-cli -h 127.0.0.1 -p 6379 ping
# 预期输出:
PONG

# 测试 Redis 基本操作
redis-cli -h 127.0.0.1 -p 6379 SET mykey "Hello Nginx Proxy"
redis-cli -h 127.0.0.1 -p 6379 GET mykey
# 预期输出:
"Hello Nginx Proxy"

# 查看 Redis 服务器信息（完整输出）
redis-cli -h 127.0.0.1 -p 6379 INFO SERVER
# 预期输出:
# Server
redis_version:7.0.15
redis_git_sha1:00000000
redis_git_dirty:0
redis_build_id:1234567890abcdef
redis_mode:standalone
os:Linux 6.11.0-29-generic x86_64
arch_bits:64
monotonic_clock:POSIX clock_gettime
multiplexing_api:epoll
atomicvar_api:c11-builtin
gcc_version:11.4.0
process_id:1234
process_supervised:no
run_id:1234567890abcdef1234567890abcdef12345678
tcp_port:6379
server_time_usec:1728740123456789
uptime_in_seconds:3600
uptime_in_days:0
hz:10
configured_hz:10
lru_clock:1234567
executable:/usr/bin/redis-server
config_file:/etc/redis/redis.conf
io_threads_active:0
```

**测试结果说明**:
- MySQL 代理成功将 3306 端口的请求转发到后端 MySQL 服务器
- Redis 代理成功将 6379 端口的请求转发到后端 Redis 服务器
- 四层代理完全透明,客户端无需知道后端服务器的真实 IP

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
docker compose exec -it nginx-lb bash

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
docker compose exec -it nginx-lb bash

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
        root /data/server/nginx/html;
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
mkdir -p /data/server/nginx/html
cat > /data/server/nginx/html/index.php <<'EOF'
<?php
phpinfo();
?>
EOF

cat > /data/server/nginx/html/test.php <<'EOF'
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
# 在宿主机测试静态文件
curl http://localhost:8070/

# 预期输出:
404 Not Found 或静态页面内容
```

#### 16.7.3 测试 PHP 脚本执行

```bash
# 测试 test.php
curl http://localhost:8070/test.php

# 预期输出:
test.php

# 测试 index.php（phpinfo）
curl http://localhost:8070/index.php

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
curl http://localhost:8070/status

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
docker compose exec -it nginx-web-1 /data/server/nginx/sbin/nginx -s stop
docker compose exec -it nginx-web-2 /data/server/nginx/sbin/nginx -s stop

# 此时请求会被转发到 backup 服务器
curl http://localhost:8070
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
docker compose down

# 2. 删除网络（可选）
docker network rm 07manual-balance_nginx-net

# 3. 完全清理（包括镜像）
docker compose down --rmi all
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
