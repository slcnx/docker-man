# Docker Compose 子域DNS架构部署指导

## **网络架构概览**
```
10.0.0.0/24 网络拓扑（子域委派架构）
├── 10.0.0.1   - 网关
├── 10.0.0.12  - 客户端/博客 (blog)
├── 10.0.0.13  - 主 DNS 服务器 (dns1) - 管理 magedu.com
├── 10.0.0.14  - bj 子域 DNS 服务器 (bj-dns) - 管理 bj.magedu.com
├── 10.0.0.16  - sh 子域 DNS 服务器 (sh-dns) - 管理 sh.magedu.com
├── 10.0.0.24  - bj Web 服务器 (www-bj)
└── 10.0.0.26  - sh Web 服务器 (www-sh)

域名结构:
magedu.com (主域 - 由 dns1 管理)
├── dns1.magedu.com → 10.0.0.13
├── blog.magedu.com → 10.0.0.12
├── www.magedu.com → 10.0.0.14
├── bj-dns.magedu.com → 10.0.0.14 (子域DNS服务器)
├── sh-dns.magedu.com → 10.0.0.16 (子域DNS服务器)
├── bj.magedu.com (子域 - 委派给 bj-dns 管理)
│   ├── bj.magedu.com → 10.0.0.24
│   └── www.bj.magedu.com → 10.0.0.24
└── sh.magedu.com (子域 - 委派给 sh-dns 管理)
    ├── sh.magedu.com → 10.0.0.26
    └── www.sh.magedu.com → 10.0.0.26
```

## **服务启动**
```bash
docker compose up -d
docker compose ps
```

## **主 DNS 服务器配置 (dns1 - 10.0.0.13)**
```bash
docker compose exec -it dns-main bash

# 1. 创建主域区域文件
vim /var/named/named.magedu.com
$TTL 86400
@ IN SOA magedu-dns.magedu.com. admin.magedu.com. (
    128           ; 序列号
    3H            ; 刷新
    15M           ; 重试
    1D            ; 过期
    1W            ; 最小TTL
)

       NS dns1

; 子域委派 - 将子域委派给专门的DNS服务器
bj     NS bj-dns
sh     NS sh-dns

; 主域记录
dns1   IN A 10.0.0.13
www    IN A 10.0.0.14
blog   IN A 10.0.0.12

; 子域DNS服务器的胶水记录(Glue Records)
bj-dns IN A 10.0.0.14
sh-dns IN A 10.0.0.16

# 2. 设置权限并检查
chown named.named /var/named/named.magedu.com
chmod 640 /var/named/named.magedu.com
named-checkzone magedu.com /var/named/named.magedu.com

# 3. 创建反向解析区域文件
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
12  IN PTR blog.magedu.com.
13  IN PTR dns1.magedu.com.
14  IN PTR bj-dns.magedu.com.
16  IN PTR sh-dns.magedu.com.
24  IN PTR www-bj.bj.magedu.com.
26  IN PTR www-sh.sh.magedu.com.

chown named.named /var/named/named.0.0.10
chmod 640 /var/named/named.0.0.10
named-checkzone 0.0.10.in-addr.arpa /var/named/named.0.0.10

# 4. 编辑主配置文件
vim /etc/named.conf
    //listen-on port 53 { 127.0.0.1; };
    //listen-on-v6 port 53 { ::1; };
    //allow-query     { localhost; };
    recursion yes;
    dnssec-validation no;
    filter-aaaa-on-v4 yes;
    server ::/0 { bogus yes; };

# 5. 编辑区域配置文件
vim /etc/named.rfc1912.zones
# 添加:

zone "magedu.com" IN {
    type master;
    file "/var/named/named.magedu.com";
    allow-update { none; };
};

zone "0.0.10.in-addr.arpa" IN {
    type master;
    file "/var/named/named.0.0.10";
    allow-update { none; };
};

# 6. 检查并重载
named-checkconf -z /etc/named.conf
rndc reload
rndc status
```

## **bj 子域 DNS 服务器配置 (bj-dns - 10.0.0.14)**
```bash
docker compose exec -it dns-bj bash

# 1. 创建 bj 子域区域文件
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

## **sh 子域 DNS 服务器配置 (sh-dns - 10.0.0.16)**
```bash
docker compose exec -it dns-sh bash

# 1. 创建 sh 子域区域文件
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

# 1. 测试主域解析
nslookup www.magedu.com
nslookup blog.magedu.com
nslookup dns1.magedu.com

# 2. 测试子域NS委派
dig @10.0.0.13 bj.magedu.com NS
dig @10.0.0.13 sh.magedu.com NS

# 3. 测试 bj 子域解析（查询会被委派到 10.0.0.14）
nslookup bj.magedu.com
nslookup www.bj.magedu.com
dig @10.0.0.14 bj.magedu.com
dig @10.0.0.14 www.bj.magedu.com

# 4. 测试 sh 子域解析（查询会被委派到 10.0.0.16）
nslookup sh.magedu.com
nslookup www.sh.magedu.com
dig @10.0.0.16 sh.magedu.com
dig @10.0.0.16 www.sh.magedu.com

# 5. 测试反向解析
nslookup 10.0.0.12
nslookup 10.0.0.13
nslookup 10.0.0.14
nslookup 10.0.0.16
nslookup 10.0.0.24
nslookup 10.0.0.26

# 6. 测试 Web 访问
curl http://10.0.0.24
curl http://10.0.0.26
```

## **DNS查询流程说明**

### 查询 www.bj.magedu.com 的过程:
1. 客户端向主DNS (10.0.0.13) 查询 www.bj.magedu.com
2. 主DNS发现 bj.magedu.com 被委派给 bj-dns (10.0.0.14)
3. 主DNS返回委派信息，告知客户端去问 10.0.0.14
4. 客户端向 10.0.0.14 查询 www.bj.magedu.com
5. bj-dns返回 10.0.0.24

### 胶水记录(Glue Records)的作用:
在主域文件中配置:
```
bj-dns IN A 10.0.0.14
sh-dns IN A 10.0.0.16
```
这些记录称为"胶水记录"，用于打破循环依赖。如果没有这些记录，查询bj.magedu.com时会出现循环：
- 需要查询bj-dns.magedu.com的IP
- 但bj-dns.magedu.com在bj.magedu.com域中
- 而要查询bj.magedu.com需要先知道bj-dns的IP

## **重要概念**

### 子域委派 (Delegation)
通过NS记录将子域的管理权委派给其他DNS服务器：
```
bj  NS bj-dns
```

### 子域独立管理
每个子域有自己的DNS服务器和区域文件，可以独立管理自己的记录。

### 分布式DNS架构优势
1. 负载分担：不同子域由不同服务器管理
2. 管理分权：可以将子域管理权限委派给不同团队
3. 故障隔离：子域DNS故障不影响主域
4. 地理分布：可以将子域DNS服务器部署在不同地域
