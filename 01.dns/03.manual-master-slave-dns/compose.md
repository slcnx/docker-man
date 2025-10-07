# Docker Compose 主从DNS架构部署指导

## **网络架构概览**
```
10.0.0.0/24 网络拓扑
├── 10.0.0.1   - 网关
├── 10.0.0.12  - DNS 客户端 (client)
├── 10.0.0.13  - 主 DNS 服务器 (dns-master)
├── 10.0.0.14  - Web 服务器 (www.magedu.com)
└── 10.0.0.15  - 从 DNS 服务器 (dns-slave)
```

## **服务启动**
```bash
# 1. 启动所有服务
docker compose up -d

# 2. 检查服务状态
docker compose ps

# 3. 查看网络配置
docker network inspect 03manual-master-slave-dns_dns-net
```

## **主 DNS 服务器配置**
```bash
# 进入主 DNS 服务器容器
docker compose exec -it dns-master bash

# 1. 创建区域文件
vim /var/named/named.magedu.com
$TTL 86400
@ IN SOA ns1.magedu.com. admin.magedu.com. (
    2024100401    ; 序列号 (格式: YYYYMMDDNN)
    3H            ; 刷新时间
    15M           ; 重试时间
    1W            ; 过期时间
    1D            ; 最小TTL
)

       NS ns1.magedu.com.
       NS ns2.magedu.com.
ns1 IN A 10.0.0.13
ns2 IN A 10.0.0.15
www IN A 10.0.0.14
*   IN A 10.0.0.199

# 2. 修改文件所有权和权限
chown named.named /var/named/named.magedu.com
chmod 640 /var/named/named.magedu.com
ls -l /var/named

# 3. 检查区域文件语法
named-checkzone magedu.com /var/named/named.magedu.com

# 4. 编辑主配置文件
vim /etc/named.conf
# 修改以下内容:
    //listen-on port 53 { 127.0.0.1; };           # 注释掉
    //listen-on-v6 port 53 { ::1; };              # 注释掉
    //allow-query     { localhost; };             # 注释掉

    recursion yes;
    dnssec-validation no;

    # 添加区域传输控制
    allow-transfer { 10.0.0.15; };                # 允许从服务器传输

# 5. 编辑区域配置文件
vim /etc/named.rfc1912.zones
# 在文件末尾添加:
zone "magedu.com" IN {
    type master;
    file "/var/named/named.magedu.com";
    allow-update { none; };
    allow-transfer { 10.0.0.15; };                # 允许从服务器传输
    notify yes;                                    # 启用通知
};

# 6. 创建反向解析区域文件（PTR记录）
vim /var/named/named.0.0.10
$TTL 86400
@ IN SOA ns1.magedu.com. admin.magedu.com. (
    2024100401
    3H
    15M
    1W
    1D
)

       NS ns1.magedu.com.
       NS ns2.magedu.com.
13  IN PTR ns1.magedu.com.
14  IN PTR www.magedu.com.
15  IN PTR ns2.magedu.com.

# 7. 修改反向区域文件权限
chown named.named /var/named/named.0.0.10
chmod 640 /var/named/named.0.0.10

# 8. 检查反向区域文件
named-checkzone 0.0.10.in-addr.arpa /var/named/named.0.0.10

# 9. 添加反向解析区域配置
vim /etc/named.rfc1912.zones
# 继续添加反向区域:
zone "0.0.10.in-addr.arpa" IN {
    type master;
    file "/var/named/named.0.0.10";
    allow-update { none; };
    allow-transfer { 10.0.0.15; };                # 允许从服务器传输
    notify yes;                                    # 启用通知
};

# 10. 检查总配置
named-checkconf -z /etc/named.conf

# 11. 启动 DNS 服务
rndc reload

# 12. 检查服务状态
rndc status
ss -tunlp | grep 53
```

## **从 DNS 服务器配置**
```bash
# 进入从 DNS 服务器容器
docker compose exec -it dns-slave bash

# 1. 编辑主配置文件
vim /etc/named.conf
# 修改以下内容:
    //listen-on port 53 { 127.0.0.1; };           # 注释掉
    //listen-on-v6 port 53 { ::1; };              # 注释掉
    //allow-query     { localhost; };             # 注释掉

    recursion yes;
    dnssec-validation no;

# 2. 编辑区域配置文件
vim /etc/named.rfc1912.zones
# 在文件末尾添加:
zone "magedu.com" IN {
    type slave;                                    # 从服务器类型
    file "slaves/named.magedu.com";                # 从主服务器同步的文件
    masters { 10.0.0.13; };                        # 主服务器IP
};

# 添加反向解析从区域
zone "0.0.10.in-addr.arpa" IN {
    type slave;                                    # 从服务器类型
    file "slaves/named.0.0.10";                    # 从主服务器同步的文件
    masters { 10.0.0.13; };                        # 主服务器IP
};

# 3. 创建 slaves 目录并设置权限
mkdir -p /var/named/slaves
chown named.named /var/named/slaves
chmod 750 /var/named/slaves

# 4. 检查配置
named-checkconf -z /etc/named.conf

# 5. 启动 DNS 服务
rndc reload

# 6. 检查服务状态和区域传输
rndc status
ls -l /var/named/slaves/                           # 应该看到同步的区域文件
cat /var/named/slaves/named.magedu.com             # 查看正向区域同步内容
cat /var/named/slaves/named.0.0.10                 # 查看反向区域同步内容
```

## **客户端测试**
```bash
# 进入客户端容器
docker compose exec -it client bash

# 1. 安装 DNS 工具
yum install -y bind-utils curl

# 2. 测试主 DNS 服务器正向解析
nslookup www.magedu.com 10.0.0.13
dig @10.0.0.13 www.magedu.com

# 3. 测试从 DNS 服务器正向解析
nslookup www.magedu.com 10.0.0.15
dig @10.0.0.15 www.magedu.com

# 4. 测试主 DNS 服务器反向解析（PTR记录）
nslookup 10.0.0.13 10.0.0.13
nslookup 10.0.0.14 10.0.0.13
nslookup 10.0.0.15 10.0.0.13
dig -x 10.0.0.13 @10.0.0.13
dig -x 10.0.0.14 @10.0.0.13

# 5. 测试从 DNS 服务器反向解析（PTR记录）
nslookup 10.0.0.13 10.0.0.15
nslookup 10.0.0.14 10.0.0.15
dig -x 10.0.0.13 @10.0.0.15
dig -x 10.0.0.14 @10.0.0.15

# 6. 测试 NS 记录
dig @10.0.0.13 magedu.com NS
dig @10.0.0.15 magedu.com NS

# 7. 测试 SOA 记录
dig @10.0.0.13 magedu.com SOA
dig @10.0.0.15 magedu.com SOA

# 8. 测试 Web 访问
curl http://www.magedu.com
```

## **Web 服务器配置**
```bash
# 1. 准备网页内容（在宿主机执行）
mkdir -p html
echo "<h1>Welcome to magedu.com - Master-Slave DNS</h1>" > html/index.html

# 2. 检查 Web 服务
docker compose exec web-server nginx -t
docker compose logs web-server
```

## **验证主从同步**
```bash
# 1. 在主服务器上修改区域文件
docker compose exec -it dns-master bash
vim /var/named/named.magedu.com
# 修改序列号 (2024100401 -> 2024100402)
# 添加新记录: test IN A 10.0.0.100

# 2. 重新加载主服务器配置
rndc reload

# 3. 在从服务器上检查同步
docker compose exec -it dns-slave bash
cat /var/named/slaves/named.magedu.com             # 应该看到新记录

# 4. 在客户端测试新记录
docker compose exec -it client bash
dig @10.0.0.13 test.magedu.com                     # 主服务器
dig @10.0.0.15 test.magedu.com                     # 从服务器
```

## **区域传输测试**
```bash
# 从客户端手动触发区域传输测试
docker compose exec -it client bash
yum install -y bind-utils

# 1. 测试主服务器的区域传输
dig @10.0.0.13 magedu.com AXFR

# 2. 测试从服务器的区域传输（应该被拒绝）
dig @10.0.0.15 magedu.com AXFR

# 3. 在主服务器查看传输日志
docker compose exec dns-master bash
tail -f /var/named/data/named.run
```

## **故障排除**
```bash
# 1. 检查服务状态
docker compose ps -a

# 2. 查看服务日志
docker compose logs dns-master
docker compose logs dns-slave
docker compose logs web-server

# 3. 网络连通性测试
docker compose exec client ping 10.0.0.13         # 主 DNS
docker compose exec client ping 10.0.0.15         # 从 DNS
docker compose exec client ping 10.0.0.14         # Web 服务器

# 4. DNS 服务调试
docker compose exec dns-master rndc status
docker compose exec dns-slave rndc status
docker compose exec dns-master named-checkconf
docker compose exec dns-slave named-checkconf

# 5. 检查区域文件权限
docker compose exec dns-master ls -l /var/named/
docker compose exec dns-slave ls -l /var/named/slaves/

# 6. 检查端口监听
docker compose exec dns-master ss -tunlp | grep 53
docker compose exec dns-slave ss -tunlp | grep 53

# 7. 强制区域传输
docker compose exec dns-slave bash
rndc retransfer magedu.com

# 8. 重启服务
docker compose restart dns-master
docker compose restart dns-slave
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
docker compose logs -f dns-master
docker compose logs -f dns-slave
```

## **验证完整流程**
```bash
# 1. 启动服务
docker compose up -d

# 2. 配置主 DNS（在 dns-master 容器中执行上述主DNS配置步骤）

# 3. 配置从 DNS（在 dns-slave 容器中执行上述从DNS配置步骤）

# 4. 在客户端测试
docker compose exec client bash
yum install -y bind-utils curl
nslookup www.magedu.com 10.0.0.13                  # 主DNS解析
nslookup www.magedu.com 10.0.0.15                  # 从DNS解析
curl http://www.magedu.com                         # Web访问

# 5. 验证成功标志
# - 主从DNS都能正确解析域名
# - 从服务器 /var/named/slaves/ 目录下有同步的区域文件
# - Web 请求返回页面内容
# - 修改主DNS后从DNS自动同步
```

## **主从同步机制说明**
```
主从DNS同步过程:
1. 主服务器配置 allow-transfer 允许从服务器传输
2. 从服务器配置 masters 指向主服务器
3. 从服务器定期检查主服务器的 SOA 记录序列号
4. 当序列号增加时，从服务器自动从主服务器传输区域文件
5. 主服务器修改后执行 rndc reload 会触发 NOTIFY 通知从服务器
6. 从服务器收到通知后立即同步更新

重要提示:
- 每次修改区域文件必须增加序列号
- 序列号格式建议: YYYYMMDDNN (年月日+当日序号)
- 从服务器的区域文件自动生成，不需要手动创建
- 从服务器的 slaves 目录必须有写权限
```
