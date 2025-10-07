# Docker Compose 子域委派+主从DNS架构部署指导

## **网络架构概览**
```
10.0.0.0/24 网络拓扑（子域委派+主从DNS架构）
├── 10.0.0.1   - 网关
├── 10.0.0.12  - 客户端/博客 (blog)
├── 10.0.0.13  - 主DNS Master (dns1) - 管理 magedu.com
├── 10.0.0.14  - bj子域DNS (bj-dns) - 管理 bj.magedu.com
├── 10.0.0.15  - 主DNS Slave (dns2) - 从dns1同步
├── 10.0.0.16  - sh子域DNS (sh-dns) - 管理 sh.magedu.com
├── 10.0.0.24  - bj Web服务器
└── 10.0.0.26  - sh Web服务器

架构特点:
1. 主域 magedu.com 采用主从架构 (dns1主, dns2从)
2. 子域委派给独立DNS服务器管理
3. 结合了主从复制和子域委派两种机制
```

## **服务启动**
```bash
docker compose up -d
docker compose ps
```

## **主DNS Master配置 (dns1 - 10.0.0.13)**
```bash
docker compose exec -it dns-master bash

# 1. 主域区域文件
vim /var/named/named.magedu.com
$TTL 86400
@ IN SOA magedu-dns.magedu.com. admin.magedu.com. (
    128           ; 序列号
    3H
    15M
    1D
    1W
)

       NS dns1
       NS dns2

; 子域委派
bj     NS bj-dns
sh     NS sh-dns

dns1   IN A 10.0.0.13
dns2   IN A 10.0.0.15
www    IN A 10.0.0.14
blog   IN A 10.0.0.12
bj-dns IN A 10.0.0.14
sh-dns IN A 10.0.0.16

chown named.named /var/named/named.magedu.com
chmod 640 /var/named/named.magedu.com
named-checkzone magedu.com /var/named/named.magedu.com

# 2. 反向解析区域
vim /var/named/named.0.0.10
$TTL 86400
@ IN SOA magedu-dns.magedu.com. admin.magedu.com. (
    128
    3H
    15M
    1D
    1W
)

       NS dns1.magedu.com.
       NS dns2.magedu.com.
12  IN PTR blog.magedu.com.
13  IN PTR dns1.magedu.com.
14  IN PTR bj-dns.magedu.com.
15  IN PTR dns2.magedu.com.
16  IN PTR sh-dns.magedu.com.
24  IN PTR www-bj.bj.magedu.com.
26  IN PTR www-sh.sh.magedu.com.

chown named.named /var/named/named.0.0.10
chmod 640 /var/named/named.0.0.10
named-checkzone 0.0.10.in-addr.arpa /var/named/named.0.0.10

# 3. 编辑主配置
vim /etc/named.conf
    //listen-on port 53 { 127.0.0.1; };
    //listen-on-v6 port 53 { ::1; };
    //allow-query     { localhost; };
    recursion yes;
    dnssec-validation no;
    filter-aaaa-on-v4 yes;
    server ::/0 { bogus yes; };

# 4. 编辑区域配置（注意：主DNS只管理主域，不管理子域）
vim /etc/named.rfc1912.zones
# 添加:

zone "magedu.com" IN {
    type master;
    file "/var/named/named.magedu.com";
    allow-update { none; };
    allow-transfer { 10.0.0.15; };
    notify yes;
};

zone "0.0.10.in-addr.arpa" IN {
    type master;
    file "/var/named/named.0.0.10";
    allow-update { none; };
    allow-transfer { 10.0.0.15; };
    notify yes;
};

# 5. 检查并重载
named-checkconf -z /etc/named.conf
rndc reload
rndc status
```

## **主DNS Slave配置 (dns2 - 10.0.0.15)**
```bash
docker compose exec -it dns-slave bash

# 1. 编辑主配置
vim /etc/named.conf
    //listen-on port 53 { 127.0.0.1; };
    //listen-on-v6 port 53 { ::1; };
    //allow-query     { localhost; };
    recursion yes;
    dnssec-validation no;
    filter-aaaa-on-v4 yes;
    server ::/0 { bogus yes; };

# 2. 编辑区域配置（只同步主域和反向解析）
vim /etc/named.rfc1912.zones
# 添加:

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

# 3. 创建slaves目录
mkdir -p /var/named/slaves
chown named.named /var/named/slaves
chmod 750 /var/named/slaves

# 4. 检查并重载
named-checkconf -z /etc/named.conf
rndc reload
rndc status

# 5. 检查同步状态
sleep 5
ls -l /var/named/slaves/
cat /var/named/slaves/named.magedu.com
```

## **bj子域DNS配置 (bj-dns - 10.0.0.14)**
```bash
docker compose exec -it dns-bj bash

# 1. 创建bj子域区域文件
vim /var/named/named.bj.magedu.com
$TTL 86400
@ IN SOA ns1.bj.magedu.com. admin.bj.magedu.com. (
    128
    3H
    15M
    1D
    1W
)

       NS ns1.bj.magedu.com.
ns1 IN A 10.0.0.14
@   IN A 10.0.0.14
www IN A 10.0.0.24

chown named.named /var/named/named.bj.magedu.com
chmod 640 /var/named/named.bj.magedu.com
named-checkzone bj.magedu.com /var/named/named.bj.magedu.com

# 2. 编辑主配置
vim /etc/named.conf
    //listen-on port 53 { 127.0.0.1; };
    //listen-on-v6 port 53 { ::1; };
    //allow-query     { localhost; };
    recursion yes;
    dnssec-validation no;
    filter-aaaa-on-v4 yes;
    server ::/0 { bogus yes; };

# 3. 编辑区域配置
vim /etc/named.rfc1912.zones
# 添加:

zone "bj.magedu.com" IN {
    type master;
    file "/var/named/named.bj.magedu.com";
    allow-update { none; };
};

# 4. 检查并重载
named-checkconf -z /etc/named.conf
rndc reload
rndc status
```

## **sh子域DNS配置 (sh-dns - 10.0.0.16)**
```bash
docker compose exec -it dns-sh bash

# 1. 创建sh子域区域文件
vim /var/named/named.sh.magedu.com
$TTL 86400
@ IN SOA ns1.sh.magedu.com. admin.sh.magedu.com. (
    128
    3H
    15M
    1D
    1W
)

       NS ns1.sh.magedu.com.
ns1 IN A 10.0.0.16
@   IN A 10.0.0.16
www IN A 10.0.0.26

chown named.named /var/named/named.sh.magedu.com
chmod 640 /var/named/named.sh.magedu.com
named-checkzone sh.magedu.com /var/named/named.sh.magedu.com

# 2. 编辑主配置
vim /etc/named.conf
    //listen-on port 53 { 127.0.0.1; };
    //listen-on-v6 port 53 { ::1; };
    //allow-query     { localhost; };
    recursion yes;
    dnssec-validation no;
    filter-aaaa-on-v4 yes;
    server ::/0 { bogus yes; };

# 3. 编辑区域配置
vim /etc/named.rfc1912.zones
# 添加:

zone "sh.magedu.com" IN {
    type master;
    file "/var/named/named.sh.magedu.com";
    allow-update { none; };
};

# 4. 检查并重载
named-checkconf -z /etc/named.conf
rndc reload
rndc status
```

## **客户端测试**
```bash
docker compose exec -it client bash
yum install -y bind-utils curl

# 1. 测试主从DNS
nslookup www.magedu.com 10.0.0.13  # 主DNS
nslookup www.magedu.com 10.0.0.15  # 从DNS

# 2. 测试子域NS委派（主从DNS都应返回委派记录）
dig @10.0.0.13 bj.magedu.com NS +short
dig @10.0.0.15 bj.magedu.com NS +short
dig @10.0.0.13 sh.magedu.com NS +short

# 3. 测试子域解析（查询会被委派到子域DNS服务器）
nslookup bj.magedu.com
nslookup www.bj.magedu.com
nslookup sh.magedu.com
nslookup www.sh.magedu.com

# 4. 直接查询子域DNS服务器
dig @10.0.0.14 bj.magedu.com
dig @10.0.0.14 www.bj.magedu.com
dig @10.0.0.16 sh.magedu.com
dig @10.0.0.16 www.sh.magedu.com

# 5. 测试反向解析
nslookup 10.0.0.13
nslookup 10.0.0.15
nslookup 10.0.0.14
nslookup 10.0.0.24

# 6. 测试Web访问
curl http://10.0.0.24
curl http://10.0.0.26
```

## **架构说明**

### 主从DNS + 子域委派的组合架构

这是一个结合了**主从复制**和**子域委派**两种机制的完整DNS架构：

#### 1. 主从DNS部分（主域高可用）
- **dns1 (10.0.0.13)**: 主DNS Master，管理主域 magedu.com
- **dns2 (10.0.0.15)**: 主DNS Slave，从dns1同步主域数据
- **作用**: 提供主域的高可用性和负载均衡

#### 2. 子域委派部分（分布式管理）
- **bj-dns (10.0.0.14)**: 独立管理 bj.magedu.com 子域
- **sh-dns (10.0.0.16)**: 独立管理 sh.magedu.com 子域
- **作用**: 实现子域的独立管理和地理分布

### DNS查询流程示例

**查询 www.bj.magedu.com 的过程:**
1. 客户端向主DNS或从DNS (10.0.0.13或10.0.0.15) 查询
2. 主/从DNS返回NS委派记录: "bj.magedu.com由bj-dns管理"
3. 客户端收到胶水记录: bj-dns地址为10.0.0.14
4. 客户端向bj-dns (10.0.0.14) 查询 www.bj.magedu.com
5. bj-dns返回 10.0.0.24

### 同步范围说明

**dns2 (从DNS) 同步的内容:**
- ✅ 主域 magedu.com（包含NS委派记录和胶水记录）
- ✅ 反向解析区域 0.0.10.in-addr.arpa
- ❌ **不同步**子域区域文件（子域由独立DNS管理）

**子域DNS服务器各自管理:**
- bj-dns 独立管理 bj.magedu.com 区域文件
- sh-dns 独立管理 sh.magedu.com 区域文件

### 架构优势

1. **高可用性**: 主域采用主从架构，主DNS故障时从DNS接管
2. **分布式管理**: 子域由独立DNS管理，支持权限分权
3. **故障隔离**: 子域DNS故障不影响主域和其他子域
4. **负载分担**: 查询负载分散到多个DNS服务器
5. **地理分布**: 子域DNS可部署在不同地域

### 重要概念

#### 胶水记录(Glue Records)
在主域区域文件中配置子域DNS服务器的A记录：
```
bj-dns IN A 10.0.0.14
sh-dns IN A 10.0.0.16
```
打破循环依赖：查询bj.magedu.com需要bj-dns的IP，但bj-dns.magedu.com在主域中定义。

#### 委派与同步的区别
- **委派**: 主域通过NS记录将子域的**管理权**交给子域DNS
- **同步**: 从DNS通过zone transfer从主DNS**复制**区域数据
- 本架构中：主域被同步，子域被委派（不被同步）
