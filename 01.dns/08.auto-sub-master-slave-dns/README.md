# DNS 完整主从架构 - 自动化部署

## 项目简介

本项目实现基于Docker Compose的**完整主从DNS架构**自动化部署，主域和所有子域均采用主从架构，是最完整的企业级DNS架构示例。

## 架构说明

```
10.0.0.0/24 网络拓扑（完整主从架构）
├── 10.0.0.1   - 网关
├── 10.0.0.12  - 客户端/博客 (blog)
├── 10.0.0.13  - 主域DNS Master (dns1)
├── 10.0.0.14  - bj子域DNS Master (bj-dns1)
├── 10.0.0.15  - 主域DNS Slave (dns2)
├── 10.0.0.16  - sh子域DNS Master (sh-dns1)
├── 10.0.0.17  - bj子域DNS Slave (bj-dns2)
├── 10.0.0.18  - sh子域DNS Slave (sh-dns2)
├── 10.0.0.24  - bj Web服务器
└── 10.0.0.26  - sh Web服务器

架构特点:
1. 主域magedu.com采用主从架构（dns1主 + dns2从）
2. bj子域bj.magedu.com采用主从架构（bj-dns1主 + bj-dns2从）
3. sh子域sh.magedu.com采用主从架构（sh-dns1主 + sh-dns2从）
4. 主域通过NS记录委派子域给子域DNS服务器
5. 所有DNS都有主从冗余，实现完整的高可用
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
08.auto-sub-master-slave-dns/
├── master-configs/                # 主域DNS Master配置
│   ├── named.conf
│   ├── named.rfc1912.zones
│   ├── named.magedu.com           # 主域区域文件
│   └── named.0.0.10               # 反向解析
├── slave-configs/                 # 主域DNS Slave配置
│   ├── named.conf
│   └── named.rfc1912.zones
├── dns-bj-master-configs/         # bj子域DNS Master配置
│   ├── named.conf
│   ├── named.rfc1912.zones
│   └── named.bj.magedu.com
├── dns-bj-slave-configs/          # bj子域DNS Slave配置
│   ├── named.conf
│   └── named.rfc1912.zones
├── dns-sh-master-configs/         # sh子域DNS Master配置
│   ├── named.conf
│   ├── named.rfc1912.zones
│   └── named.sh.magedu.com
├── dns-sh-slave-configs/          # sh子域DNS Slave配置
│   ├── named.conf
│   └── named.rfc1912.zones
├── html/
│   ├── bj/index.html
│   └── sh/index.html
├── compose.yml
└── README.md
```

## 功能特性

### ✅ 主域主从架构
- dns1 (Master) 管理主域 magedu.com
- dns2 (Slave) 从dns1同步主域
- 提供主域的高可用和负载均衡

### ✅ bj子域主从架构
- bj-dns1 (Master) 管理 bj.magedu.com
- bj-dns2 (Slave) 从bj-dns1同步
- 提供bj子域的高可用和负载均衡

### ✅ sh子域主从架构
- sh-dns1 (Master) 管理 sh.magedu.com
- sh-dns2 (Slave) 从sh-dns1同步
- 提供sh子域的高可用和负载均衡

### ✅ 子域委派机制
- 主域通过NS记录委派子域给子域DNS
- 各子域DNS独立管理各自的记录
- 支持分布式管理和地理分布

### ✅ 同步范围

**主域同步（dns2从dns1）：**
- ✅ 主域 magedu.com（包含子域委派NS记录和胶水记录）
- ✅ 反向解析区域 0.0.10.in-addr.arpa

**bj子域同步（bj-dns2从bj-dns1）：**
- ✅ bj子域 bj.magedu.com

**sh子域同步（sh-dns2从sh-dns1）：**
- ✅ sh子域 sh.magedu.com

### ✅ 完整的DNS记录
- 主域NS: dns1, dns2
- bj子域NS: bj-dns1, bj-dns2
- sh子域NS: sh-dns1, sh-dns2
- 胶水记录避免循环依赖
- PTR反向解析记录（集中管理）

## DNS查询流程

### 查询 www.bj.magedu.com:
1. 客户端向主域DNS (dns1或dns2) 查询 www.bj.magedu.com
2. 主域DNS返回bj.magedu.com的委派信息和胶水记录
   - NS记录: bj.magedu.com → bj-dns1, bj-dns2
   - 胶水记录: bj-dns1 → 10.0.0.14, bj-dns2 → 10.0.0.17
3. 客户端选择其中一个bj子域DNS查询（如10.0.0.14）
4. bj-dns1返回www记录 → 10.0.0.24
5. 如果bj-dns1不可用，客户端会自动查询bj-dns2

### 主从同步流程:

**主域同步：**
1. dns1管理主域区域文件（包含子域委派信息）
2. dns2从dns1自动同步主域区域
3. dns1修改后notify dns2立即同步

**bj子域同步：**
1. bj-dns1管理bj子域区域文件
2. bj-dns2从bj-dns1自动同步
3. bj-dns1修改后notify bj-dns2立即同步

**sh子域同步：**
1. sh-dns1管理sh子域区域文件
2. sh-dns2从sh-dns1自动同步
3. sh-dns1修改后notify sh-dns2立即同步

## 验证测试

```bash
docker compose exec client bash

# 测试主从DNS
nslookup www.magedu.com 10.0.0.13  # 主DNS
nslookup www.magedu.com 10.0.0.15  # 从DNS

# 测试子域委派（主从都应返回委派）
dig @10.0.0.13 bj.magedu.com NS
dig @10.0.0.15 bj.magedu.com NS

# 测试bj子域主从DNS
nslookup www.bj.magedu.com 10.0.0.14  # bj主DNS
nslookup www.bj.magedu.com 10.0.0.17  # bj从DNS

# 测试sh子域主从DNS
nslookup www.sh.magedu.com 10.0.0.16  # sh主DNS
nslookup www.sh.magedu.com 10.0.0.18  # sh从DNS

# 测试完整查询流程（通过主域DNS查询子域）
nslookup www.bj.magedu.com 10.0.0.13
nslookup www.sh.magedu.com 10.0.0.15

# 测试反向解析
nslookup 10.0.0.13 10.0.0.13        # 主DNS查询
nslookup 10.0.0.13 10.0.0.15        # 从DNS查询（已同步）

# 测试Web访问
curl http://10.0.0.24
curl http://10.0.0.26
```

## 验证主从同步

```bash
# 查看从DNS同步的文件
docker compose exec dns-slave ls -l /var/named/slaves/

# 查看同步的主域（包含委派记录）
docker compose exec dns-slave cat /var/named/slaves/named.magedu.com

# 查看同步的反向解析
docker compose exec dns-slave cat /var/named/slaves/named.0.0.10

# 注意：不会有 named.bj.magedu.com 和 named.sh.magedu.com
# 这两个子域由独立DNS服务器管理
```

## 配置说明

### 主DNS配置要点
```
# named.rfc1912.zones
# 只配置主域和反向解析，不配置子域
zone "magedu.com" IN {
    type master;
    file "/var/named/named.magedu.com";
    allow-transfer { 10.0.0.15; };
    notify yes;
};

zone "0.0.10.in-addr.arpa" IN {
    type master;
    file "/var/named/named.0.0.10";
    allow-transfer { 10.0.0.15; };
    notify yes;
};
```

### 从DNS配置要点
```
# named.rfc1912.zones
# 只同步主域和反向解析，不同步子域
zone "magedu.com" IN {
    type slave;
    file "slaves/named.magedu.com";
    masters { 10.0.0.13; };
};

zone "0.0.10.in-addr.arpa" IN {
    type slave;
    file "slaves/named.0.0.10";
    masters { 10.0.0.13; };
};
```

### 子域NS记录格式
```
# named.bj.magedu.com
@ IN SOA ns1.bj.magedu.com. admin.bj.magedu.com. (...)
     NS ns1.bj.magedu.com.
ns1  IN A 10.0.0.14    # 子域DNS服务器
@    IN A 10.0.0.14    # 子域本身
www  IN A 10.0.0.24    # www记录
```

## 架构优势

1. **完整高可用** - 所有DNS（主域+子域）都有主从冗余
2. **多级负载均衡** - 主域和子域都可负载均衡
3. **完整故障容错** - 任何DNS故障都有备份接管
4. **分布式管理** - 子域独立管理，互不影响
5. **地理分布** - 支持跨地域部署
6. **自动同步** - 所有从DNS自动同步更新
7. **灵活扩展** - 可独立扩展主域或子域的DNS

## 适用场景

- **大型企业DNS架构** - 需要完整高可用保障
- **跨地域分支机构** - 每个分支有独立的主从DNS
- **关键生产环境** - 需要99.9%以上可用性
- **分权管理组织** - 各子域团队独立管理自己的DNS

## 技术栈

- DNS服务: BIND 9
- Web服务: Nginx Alpine
- 容器编排: Docker Compose 3.8
- 基础镜像: Rocky Linux 9.3
