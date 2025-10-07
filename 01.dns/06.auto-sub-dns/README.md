# DNS 子域委派架构 - 自动化部署

## 项目简介

本项目实现基于Docker Compose的DNS子域委派架构自动化部署。演示主域如何通过NS记录和胶水记录将子域管理权委派给独立的DNS服务器。

## 架构说明

```
10.0.0.0/24 网络拓扑（子域委派架构）
├── 10.0.0.1   - 网关
├── 10.0.0.12  - 客户端/博客 (blog)
├── 10.0.0.13  - 主DNS (dns1) - 管理 magedu.com
├── 10.0.0.14  - bj子域DNS (bj-dns) - 管理 bj.magedu.com
├── 10.0.0.16  - sh子域DNS (sh-dns) - 管理 sh.magedu.com
├── 10.0.0.24  - bj Web服务器
└── 10.0.0.26  - sh Web服务器

域名结构:
magedu.com (主域)
├── dns1.magedu.com → 10.0.0.13
├── blog.magedu.com → 10.0.0.12
├── bj-dns.magedu.com → 10.0.0.14 (子域DNS)
├── sh-dns.magedu.com → 10.0.0.16 (子域DNS)
├── bj.magedu.com (委派给bj-dns)
│   ├── bj.magedu.com → 10.0.0.24
│   └── www.bj.magedu.com → 10.0.0.24
└── sh.magedu.com (委派给sh-dns)
    ├── sh.magedu.com → 10.0.0.26
    └── www.sh.magedu.com → 10.0.0.26
```

## 快速启动

```bash
# 启动所有服务
docker compose up -d

# 查看服务状态
docker compose ps

# 查看测试日志
docker compose logs client
```

## 目录结构

```
06.auto-sub-dns/
├── dns-main-configs/           # 主DNS配置
│   ├── named.conf
│   ├── named.rfc1912.zones
│   ├── named.magedu.com
│   └── named.0.0.10
├── dns-bj-configs/             # bj子域DNS配置
│   ├── named.conf
│   ├── named.rfc1912.zones
│   └── named.bj.magedu.com
├── dns-sh-configs/             # sh子域DNS配置
│   ├── named.conf
│   ├── named.rfc1912.zones
│   └── named.sh.magedu.com
├── html/
│   ├── bj/index.html
│   └── sh/index.html
├── compose.yml
└── README.md
```

## 功能特性

### ✅ 子域委派机制
- 主域通过NS记录委派子域管理权
- 胶水记录(Glue Records)打破循环依赖
- 子域DNS服务器独立管理自己的区域

### ✅ 分布式DNS架构
- 主DNS管理主域和委派信息
- 子域DNS独立管理子域记录
- 支持地理分布式部署

### ✅ 自动化部署
- 所有配置预先准备好
- 一键启动完整架构
- 自动健康检查和测试

## DNS查询流程

### 查询 www.bj.magedu.com:
1. 客户端向主DNS (10.0.0.13) 查询
2. 主DNS发现bj.magedu.com被委派给bj-dns
3. 主DNS返回NS记录和胶水记录
4. 客户端向bj-dns (10.0.0.14) 查询
5. bj-dns返回 10.0.0.24

### 胶水记录的作用:
```
; 在主域文件中
bj-dns IN A 10.0.0.14   ; 胶水记录
sh-dns IN A 10.0.0.16   ; 胶水记录
```
避免循环依赖：查询bj.magedu.com需要bj-dns的IP，但bj-dns.magedu.com在主域中定义。

## 验证测试

```bash
docker compose exec client bash

# 测试主域
nslookup www.magedu.com
nslookup blog.magedu.com

# 测试子域委派
dig @10.0.0.13 bj.magedu.com NS
dig @10.0.0.13 sh.magedu.com NS

# 测试子域解析
nslookup bj.magedu.com
nslookup www.bj.magedu.com
nslookup sh.magedu.com
nslookup www.sh.magedu.com

# 直接查询子域DNS
dig @10.0.0.14 www.bj.magedu.com
dig @10.0.0.16 www.sh.magedu.com

# 测试Web访问
curl http://10.0.0.24
curl http://10.0.0.26
```

## 配置说明

### 主DNS配置 (named.magedu.com)
```
; 子域委派
bj  NS bj-dns
sh  NS sh-dns

; 胶水记录
bj-dns IN A 10.0.0.14
sh-dns IN A 10.0.0.16
```

### bj子域DNS配置 (named.bj.magedu.com)
```
@ IN SOA bj-dns.magedu.com. admin.magedu.com. (...)
     NS ns1
ns1 IN A 10.0.0.14
www IN A 10.0.0.24
```

## 架构优势

1. **负载分担** - 不同子域由不同服务器管理
2. **管理分权** - 可将子域管理权委派给不同团队
3. **故障隔离** - 子域DNS故障不影响主域
4. **地理分布** - 支持跨地域部署
5. **扩展性好** - 易于添加新的子域

## 技术栈

- DNS服务: BIND 9
- Web服务: Nginx Alpine
- 容器编排: Docker Compose 3.8
- 基础镜像: Rocky Linux 9.3
