# Docker Compose DNS 架构部署指导

## **网络架构概览**
```
10.0.0.0/24 网络拓扑
├── 10.0.0.1   - 网关
├── 10.0.0.12  - DNS 客户端 (client)
├── 10.0.0.13  - DNS 服务器 (dns-server)
└── 10.0.0.14  - Web 服务器 (www.magedu.com)
```

## **服务启动**
```bash
# 1. 启动所有服务
docker compose up -d

# 2. 检查服务状态
docker compose ps

# 3. 查看网络配置
docker network inspect docker-man_dns-net
```

## **DNS 服务器配置**
```bash
# 进入 DNS 服务器容器
docker compose exec -it dns-server bash

# 1. 创建区域文件
vim /var/named/named.magedu.com
$TTL 86400                                         ; 默认 TTL 86400秒(1天)
@ IN SOA @ admin.magedu.com (                     ; SOA 记录定义
    123                                            ; 序列号
    3H                                             ; 刷新时间 3小时
    15M                                            ; 重试时间 15分钟
    1D                                             ; 过期时间 1天
    1W                                             ; 最小 TTL 1周
)

       NS ns1                                      ; 权威 NS 记录
ns1 IN A 10.0.0.13                                ; NS 服务器 IP
www IN A 10.0.0.14                                ; www 主机记录
*   IN A 10.0.0.199                               ; 通配符记录，匹配所有未定义主机

# 2. 修改文件所有权和权限
chown named.named /var/named/named.magedu.com
ls -l /var/named                                   # 确认权限

# 3. 检查区域文件语法
named-checkzone magedu.com /var/named/named.magedu.com

# 4. 编辑主配置文件
vim /etc/named.conf                                # 修改主配置
    //listen-on port 53 { 127.0.0.1; };           # 注释掉仅监听localhost
    //listen-on-v6 port 53 { ::1; };              # 注释掉IPv6监听
    directory     "/var/named";                    # 区域文件目录
    dump-file     "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file    "/var/named/data/named.secroots";
    recursing-file    "/var/named/data/named.recursing";
    //allow-query     { localhost; };             # 注释掉仅允许本地查询

    recursion yes;                                 # 启用递归查询
    dnssec-validation no;                          # 禁用DNSSEC验证

# 5. 编辑区域配置文件
vim /etc/named.rfc1912.zones                       # 添加zone配置
zone "magedu.com" IN {
    type master;
    file "/var/named/named.magedu.com";
    allow-update { none; };
};

# 6. 创建反向解析区域文件（PTR记录）
vim /var/named/named.0.0.10
$TTL 86400
@ IN SOA @ admin.magedu.com (
    123
    3H
    15M
    1D
    1W
)

       NS ns1.magedu.com.
13  IN PTR ns1.magedu.com.
14  IN PTR www.magedu.com.

# 7. 修改反向区域文件权限
chown named.named /var/named/named.0.0.10

# 8. 检查反向区域文件
named-checkzone 0.0.10.in-addr.arpa /var/named/named.0.0.10

# 9. 添加反向解析区域配置
vim /etc/named.rfc1912.zones                       # 继续添加
zone "0.0.10.in-addr.arpa" IN {
    type master;
    file "/var/named/named.0.0.10";
    allow-update { none; };
};

# 10. 检查总配置
/usr/sbin/named-checkconf -z /etc/named.conf

# 11. 重新加载配置
rndc status                                        # 查看服务状态
rndc reload                                        # 重新加载
```

## **客户端测试**
```bash
# 进入客户端容器
docker compose exec -it client bash

# 1. 安装 DNS 工具
yum install -y bind-utils curl

# 2. 测试正向 DNS 解析
nslookup www.magedu.com
dig -t A www.magedu.com @10.0.0.13

# 3. 测试反向 DNS 解析（PTR记录）
nslookup 10.0.0.13
nslookup 10.0.0.14
dig -x 10.0.0.13 @10.0.0.13
dig -x 10.0.0.14 @10.0.0.13

# 4. 测试 Web 访问
curl http://www.magedu.com
curl http://10.0.0.14
```

## **Web 服务器配置**
```bash
# 1. 准备网页内容
mkdir -p html
echo "<h1>Welcome to magedu.com</h1>" > html/index.html

# 2. 检查 Web 服务
docker compose exec web-server nginx -t           # 检查配置
docker compose logs web-server                    # 查看日志
```

## **故障排除**
```bash
# 1. 检查服务状态
docker compose ps -a

# 2. 查看服务日志
docker compose logs dns-server
docker compose logs web-server
docker compose logs client

# 3. 网络连通性测试
docker compose exec client ping 10.0.0.13         # 测试到 DNS 服务器
docker compose exec client ping 10.0.0.14         # 测试到 Web 服务器

# 4. DNS 服务调试
docker compose exec dns-server rndc status
docker compose exec dns-server named-checkconf

# 5. 重启服务
docker compose restart dns-server
docker compose restart web-server
```

## **服务管理**
```bash
# 重启所有服务
docker compose restart

# 停止服务
docker compose down

# 完全清理
docker compose down --volumes --rmi all

# 查看实时日志
docker compose logs -f
```

## **验证完整流程**
```bash
# 1. 启动服务
docker compose up -d

# 2. 配置 DNS 区域（在 dns-server 容器中执行上述 DNS 配置步骤）

# 3. 在客户端测试
docker compose exec client bash
nslookup www.magedu.com                            # 应该解析到 10.0.0.14
curl http://www.magedu.com                         # 应该返回网页内容

# 4. 验证成功标志
# - DNS 解析返回正确 IP
# - Web 请求返回页面内容
# - 所有容器状态为 Up
```