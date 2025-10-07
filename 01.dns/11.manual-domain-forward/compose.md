# DNS 指定域转发 + 主从复制 - 手工配置

## **网络架构概览**
```
10.0.0.0/24 网络拓扑（指定域转发 + 主从复制架构）
├── 10.0.0.1   - 网关
├── 10.0.0.12  - DNS 客户端 (client)
├── 10.0.0.13  - DNS Server 1 主 (dns-server-1) [指定域转发服务器-Master]
├── 10.0.0.16  - DNS Server 1 从 (dns-server-1-slave) [指定域转发服务器-Slave]
├── 10.0.0.14  - Web 服务器 (www.magedu.com)
├── 10.0.0.15  - DNS Server 2 主 (dns-server-2) [权威服务器-Master]
└── 10.0.0.17  - DNS Server 2 从 (dns-server-2-slave) [权威服务器-Slave]

DNS 转发流程：
- magedu.com 域：client → dns-server-1 (指定域转发) → dns-server-2 (权威解析)
- 其他域名：client → dns-server-1 (直接递归解析) → Internet

主从复制流程：
dns-server-1 (Master) ⇄ dns-server-1-slave (Slave) [转发配置相同]
dns-server-2 (Master) ⇄ dns-server-2-slave (Slave) [区域同步]
```

## **服务启动**
```bash
# 1. 启动所有服务
docker compose up -d

# 2. 检查服务状态
docker compose ps

# 3. 查看网络配置
docker network inspect 11manual-domain-forward_dns-net
```

## **DNS 服务器配置**

### **配置 dns-server-2（权威服务器-主服务器）**
```bash
# 进入 dns-server-2 容器
docker compose exec -it dns-server-2 bash

# 1. 编辑主配置文件
vim /etc/named.conf
    //listen-on port 53 { 127.0.0.1; };           # 注释掉仅监听localhost
    //listen-on-v6 port 53 { ::1; };              # 注释掉IPv6监听
    directory     "/var/named";                    # 区域文件目录
    dump-file     "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file    "/var/named/data/named.secroots";
    recursing-file    "/var/named/data/named.recursing";
    //allow-query     { localhost; };             # 注释掉仅允许本地查询

    recursion yes;                                 # 启用递归查询（重要）
    dnssec-validation no;                          # 禁用DNSSEC验证

# 2. 添加 magedu.com 域名区域配置（主服务器配置）
vim /etc/named.rfc1912.zones                       # 添加zone配置
zone "magedu.com" IN {
    type master;                                   # 主服务器类型
    file "magedu.com.zone";
    allow-update { none; };                        # 禁止动态更新
    allow-transfer { 10.0.0.17; };                 # 允许 slave 进行区域传输
    also-notify { 10.0.0.17; };                    # 主动通知 slave 更新
};

# 3. 创建区域文件
cat > /var/named/magedu.com.zone << 'EOF'
$TTL 86400                                         ; 默认 TTL 86400秒(1天)
@   IN  SOA dns-server-2.magedu.com. admin.magedu.com. (
        2024010601                                 ; 序列号（每次修改需递增）
        3600                                       ; 刷新时间 1小时
        1800                                       ; 重试时间 30分钟
        604800                                     ; 过期时间 1周
        86400 )                                    ; 最小 TTL 1天

@               IN  NS  dns-server-2.magedu.com.  ; 主 NS 记录
@               IN  NS  dns-server-2-slave.magedu.com.  ; 从 NS 记录
dns-server-2    IN  A   10.0.0.15                  ; 主 NS 服务器 IP
dns-server-2-slave  IN  A   10.0.0.17              ; 从 NS 服务器 IP
www             IN  A   10.0.0.14                  ; www 主机记录
EOF

# 4. 修改文件所有权和权限
chown named.named /var/named/magedu.com.zone
chmod 640 /var/named/magedu.com.zone
ls -l /var/named/magedu.com.zone                   # 确认权限

# 5. 检查区域文件语法
named-checkzone magedu.com /var/named/magedu.com.zone

# 6. 检查总配置
named-checkconf -z /etc/named.conf

# 7. 重新加载配置
rndc status                                        # 查看服务状态
rndc reload                                        # 重新加载

# 8. 退出容器
exit
```

### **配置 dns-server-2-slave（从服务器）**
```bash
# 进入 dns-server-2-slave 容器
docker compose exec -it dns-server-2-slave bash

# 1. 编辑主配置文件
vim /etc/named.conf
    //listen-on port 53 { 127.0.0.1; };           # 注释掉仅监听localhost
    //listen-on-v6 port 53 { ::1; };              # 注释掉IPv6监听
    directory     "/var/named";
    //allow-query     { localhost; };             # 注释掉仅允许本地查询

    recursion yes;                                 # 启用递归查询
    dnssec-validation no;                          # 禁用DNSSEC验证

# 2. 添加 magedu.com 域名区域配置（从服务器配置）
vim /etc/named.rfc1912.zones                       # 添加zone配置
zone "magedu.com" IN {
    type slave;                                    # 从服务器类型
    file "slaves/magedu.com.zone";                 # 从主服务器同步的区域文件
    masters { 10.0.0.15; };                        # 主服务器 IP
};

# 3. 创建 slaves 目录
mkdir -p /var/named/slaves
chown named.named /var/named/slaves
chmod 770 /var/named/slaves

# 4. 检查总配置
named-checkconf -z /etc/named.conf

# 5. 重新加载配置
rndc reload                                        # 重新加载

# 6. 验证区域传输
rndc retransfer magedu.com                         # 手动触发区域传输
ls -l /var/named/slaves/                           # 查看是否成功同步区域文件

# 7. 查看区域状态
rndc status
rndc zonestatus magedu.com                         # 查看区域详细状态

# 8. 退出容器
exit
```

### **配置 dns-server-1（指定域转发服务器-主服务器）**
```bash
# 进入 dns-server-1 容器
docker compose exec -it dns-server-1 bash

# 1. 编辑主配置文件
vim /etc/named.conf
    //listen-on port 53 { 127.0.0.1; };           # 注释掉仅监听localhost
    //listen-on-v6 port 53 { ::1; };              # 注释掉IPv6监听
    directory     "/var/named";
    //allow-query     { localhost; };             # 注释掉仅允许本地查询

    recursion yes;                                 # 启用递归查询
    dnssec-validation no;                          # 禁用DNSSEC验证

# 2. 添加指定域转发配置（在配置文件末尾或 zone 段）
vim /etc/named.rfc1912.zones                       # 添加指定域转发配置

# 添加 magedu.com 的指定域转发配置
zone "magedu.com" IN {
    type forward;                                  # 转发类型
    forwarders { 10.0.0.15; };                     # 转发目标：dns-server-2
    forward only;                                  # 仅转发，不自行解析
};

# 3. 检查配置语法
named-checkconf -z /etc/named.conf

# 4. 重新加载配置
rndc reload                                        # 重新加载
rndc status                                        # 查看状态

# 5. 验证转发配置
grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones  # 确认转发配置

# 6. 退出容器
exit
```

### **配置 dns-server-1-slave（指定域转发服务器-从服务器）**
```bash
# 进入 dns-server-1-slave 容器
docker compose exec -it dns-server-1-slave bash

# 1. 编辑主配置文件（与主服务器配置相同）
vim /etc/named.conf
    //listen-on port 53 { 127.0.0.1; };           # 注释掉仅监听localhost
    //listen-on-v6 port 53 { ::1; };              # 注释掉IPv6监听
    directory     "/var/named";
    //allow-query     { localhost; };             # 注释掉仅允许本地查询

    recursion yes;                                 # 启用递归查询
    dnssec-validation no;                          # 禁用DNSSEC验证

# 2. 添加指定域转发配置（与主服务器相同）
vim /etc/named.rfc1912.zones

zone "magedu.com" IN {
    type forward;                                  # 转发类型
    forwarders { 10.0.0.15; };                     # 转发目标：dns-server-2
    forward only;                                  # 仅转发
};

# 3. 检查配置语法
named-checkconf -z /etc/named.conf

# 4. 重新加载配置
rndc reload                                        # 重新加载
rndc status                                        # 查看状态

# 5. 验证转发配置
grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones

# 6. 退出容器
exit
```

## **客户端测试**
```bash
# 进入客户端容器
docker compose exec -it client bash

# 1. 安装 DNS 工具
yum install -y bind-utils curl iputils

# 2. 测试指定域转发（magedu.com）
nslookup www.magedu.com                            # 应该解析到 10.0.0.14
dig -t A www.magedu.com @10.0.0.13                 # 从 server-1 查询
dig www.magedu.com                                 # 使用默认 DNS（10.0.0.13）

# 3. 测试指定域转发 - 从服务器
dig @10.0.0.16 www.magedu.com                      # 从 server-1-slave 查询
dig @10.0.0.17 www.magedu.com                      # 从 server-2-slave 查询
dig @10.0.0.15 www.magedu.com                      # 从 server-2 查询
# 三次查询应该返回相同的结果：10.0.0.14

# 4. 验证主从 NS 记录
dig @10.0.0.15 NS magedu.com                       # 查询 NS 记录
dig @10.0.0.17 NS magedu.com                       # 从 slave 查询 NS 记录
# 应该返回两个 NS：dns-server-2 和 dns-server-2-slave

# 5. 测试其他域名（不通过转发，直接递归解析）
dig @10.0.0.13 www.baidu.com                       # 直接递归解析（不转发）
dig @10.0.0.16 www.google.com                      # 直接递归解析（不转发）
dig @10.0.0.13 www.qq.com                          # 直接递归解析（不转发）

# 6. 对比：指定域转发 vs 直接递归
dig @10.0.0.13 www.magedu.com +trace               # 查看解析路径（经过转发）
dig @10.0.0.13 www.baidu.com +trace                # 查看解析路径（不经过转发）

# 7. 验证缓存功能
dig @10.0.0.13 www.taobao.com                      # 第一次查询（慢）
dig @10.0.0.13 www.taobao.com                      # 第二次查询（快，来自缓存）

# 8. 测试不同记录类型
dig @10.0.0.13 A www.magedu.com                    # A 记录
dig @10.0.0.13 NS magedu.com                       # NS 记录
dig @10.0.0.13 SOA magedu.com                      # SOA 记录

# 9. 测试 Web 访问
curl http://www.magedu.com                         # 访问网站
curl http://10.0.0.14                              # 直接访问IP
ping -c 3 www.magedu.com                           # 测试连通性

# 10. 测试高可用性（主服务器故障转移）
# 在另一个终端停止 server-2：docker compose stop dns-server-2
dig @10.0.0.17 www.magedu.com                      # 从服务器应该仍能响应
```

## **验证转发流程**
```bash
# 在主机上开启多个终端，同时观察转发流程

# 终端1：观察 dns-server-1 查询日志
docker compose exec dns-server-1 tail -f /var/log/named/query.log

# 终端2：观察 dns-server-2 查询日志
docker compose exec dns-server-2 tail -f /var/log/named/query.log

# 终端3：发起 DNS 查询
docker compose exec client dig @10.0.0.13 www.magedu.com
docker compose exec client dig @10.0.0.13 www.baidu.com

# 观察结果：
# magedu.com 查询：
# 1. server-1 日志显示接收到来自 client 的查询
# 2. server-2 日志显示接收到来自 server-1 的转发查询
# 3. server-2 返回权威记录
# 4. server-1 将结果返回给 client

# www.baidu.com 查询：
# 1. server-1 日志显示接收到来自 client 的查询
# 2. server-2 日志无记录（因为 server-1 直接递归解析）
# 3. server-1 自行递归解析并返回结果
```

## **验证主从同步**
```bash
# 1. 检查从服务器区域文件是否已同步
docker compose exec dns-server-2-slave ls -l /var/named/slaves/
# 应该看到 magedu.com.zone 文件

# 2. 对比主从区域文件内容
docker compose exec dns-server-2 cat /var/named/magedu.com.zone
docker compose exec dns-server-2-slave cat /var/named/slaves/magedu.com.zone
# 内容应该完全相同

# 3. 查看主从同步状态
docker compose exec dns-server-2 rndc zonestatus magedu.com
docker compose exec dns-server-2-slave rndc zonestatus magedu.com
# 注意观察 serial number 应该相同

# 4. 测试主从服务器响应一致性
docker compose exec client dig @10.0.0.15 www.magedu.com +short
docker compose exec client dig @10.0.0.17 www.magedu.com +short
# 两次查询应返回相同的 IP：10.0.0.14

# 5. 手动触发区域传输
docker compose exec dns-server-2-slave rndc retransfer magedu.com

# 6. 测试主服务器故障转移
docker compose stop dns-server-2                    # 停止主服务器
docker compose exec client dig @10.0.0.17 www.magedu.com  # 从服务器应仍能响应
docker compose start dns-server-2                   # 恢复主服务器
```

## **配置说明**

### **指定域转发配置项**
```conf
# 在 /etc/named.rfc1912.zones 中添加
zone "magedu.com" IN {
    type forward;                  # 转发类型
    forwarders { 10.0.0.15; };    # 转发目标服务器IP列表
    forward only;                  # 转发策略
};
```

### **forward 策略说明**
- `forward only`: 仅转发，转发失败时直接返回失败，不自行解析（推荐用于指定域转发）
- `forward first`: 优先转发，转发失败时自行递归解析

### **指定域转发 vs 全局转发**

| 特性 | 全局转发 | 指定域转发 |
|------|---------|-----------|
| 配置位置 | `options { }` | `zone { }` |
| 作用范围 | 所有域名 | 指定域名 |
| 配置语法 | `forwarders { IP; };` | `zone "domain" { type forward; }` |
| 递归行为 | 可全局控制 | 按域控制 |
| 适用场景 | 统一出口 | 混合架构、多数据中心 |

### **主从同步机制**
```
1. 主服务器修改区域文件并递增序列号（Serial）
2. 主服务器执行 rndc reload 重新加载配置
3. 主服务器通过 NOTIFY 消息通知从服务器（also-notify）
4. 从服务器收到 NOTIFY 后，查询主服务器的 SOA 记录
5. 从服务器比较序列号，如果主服务器序列号更大，则发起 AXFR 区域传输
6. 从服务器接收完整区域数据并保存到 slaves/ 目录
7. 从服务器重新加载区域文件，开始使用新数据
```

### **转发机制详解**

#### **查询 magedu.com 域（指定域转发）**
```
1. client (10.0.0.12) → dns-server-1 (10.0.0.13): 查询 www.magedu.com
2. dns-server-1 匹配到指定域转发配置
3. dns-server-1 → dns-server-2 (10.0.0.15): 转发查询
4. dns-server-2 作为 magedu.com 的权威服务器，直接返回 A 记录: 10.0.0.14
5. dns-server-1 → client: 返回结果并缓存

使用从服务器查询：
1. client → dns-server-2-slave (10.0.0.17): 直接查询从服务器
2. dns-server-2-slave 作为 magedu.com 的权威从服务器，返回同步的 A 记录: 10.0.0.14
```

#### **查询其他域名（不转发，直接递归）**
```
1. client → dns-server-1: 查询 www.baidu.com
2. dns-server-1 检查指定域转发配置（未匹配）
3. dns-server-1 → 根DNS → TLD DNS → 权威DNS: 直接递归解析
4. dns-server-1 → client: 返回解析结果并缓存

与全局转发的区别：
- 全局转发：所有域名都转发到 dns-server-2
- 指定域转发：只有 magedu.com 转发，其他域名自行递归解析
```

## **故障排除**
```bash
# 1. 检查服务状态
docker compose ps -a

# 2. 查看服务日志
docker compose logs dns-server-1
docker compose logs dns-server-1-slave
docker compose logs dns-server-2
docker compose logs dns-server-2-slave
docker compose logs client

# 3. 检查 DNS 配置
docker compose exec dns-server-1 named-checkconf          # 检查 server-1 配置
docker compose exec dns-server-1-slave named-checkconf    # 检查 server-1-slave 配置
docker compose exec dns-server-2 named-checkconf          # 检查 server-2 配置
docker compose exec dns-server-2-slave named-checkconf    # 检查 server-2-slave 配置

# 4. 查看指定域转发配置
docker compose exec dns-server-1 grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones
docker compose exec dns-server-1-slave grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones

# 5. 检查主从区域配置
docker compose exec dns-server-2 grep -A 5 'zone "magedu.com"' /etc/named.rfc1912.zones
docker compose exec dns-server-2-slave grep -A 5 'zone "magedu.com"' /etc/named.rfc1912.zones

# 6. 测试网络连通性
docker compose exec client ping -c 2 10.0.0.13            # 测试到 server-1
docker compose exec client ping -c 2 10.0.0.16            # 测试到 server-1-slave
docker compose exec client ping -c 2 10.0.0.15            # 测试到 server-2
docker compose exec client ping -c 2 10.0.0.17            # 测试到 server-2-slave
docker compose exec dns-server-1 ping -c 2 10.0.0.15     # server-1 到 server-2
docker compose exec dns-server-2-slave ping -c 2 10.0.0.15  # slave 到 master

# 7. 查看 DNS 服务状态
docker compose exec dns-server-1 rndc status
docker compose exec dns-server-1-slave rndc status
docker compose exec dns-server-2 rndc status
docker compose exec dns-server-2-slave rndc status

# 8. 查看区域同步状态
docker compose exec dns-server-2 rndc zonestatus magedu.com
docker compose exec dns-server-2-slave rndc zonestatus magedu.com

# 9. 检查从服务器区域文件
docker compose exec dns-server-2-slave ls -l /var/named/slaves/
docker compose exec dns-server-2-slave cat /var/named/slaves/magedu.com.zone

# 10. 查看查询日志
docker compose exec dns-server-1 tail -50 /var/log/named/query.log
docker compose exec dns-server-2 tail -50 /var/log/named/query.log

# 11. 排查指定域转发问题
# 测试指定域是否正确转发
docker compose exec client dig @10.0.0.13 www.magedu.com +trace
# 测试其他域是否直接递归解析
docker compose exec client dig @10.0.0.13 www.baidu.com +trace

# 12. 重新加载配置
docker compose exec dns-server-1 rndc reload
docker compose exec dns-server-1-slave rndc reload
docker compose exec dns-server-2 rndc reload
docker compose exec dns-server-2-slave rndc reload

# 13. 重启问题服务器
docker compose restart dns-server-1
docker compose restart dns-server-2-slave
```

## **服务管理**
```bash
# 启动服务
docker compose up -d

# 启动单个服务
docker compose up -d dns-server-1
docker compose up -d dns-server-2-slave

# 重启单个服务
docker compose restart dns-server-1
docker compose restart dns-server-1-slave
docker compose restart dns-server-2
docker compose restart dns-server-2-slave

# 重启所有 DNS 服务器
docker compose restart dns-server-1 dns-server-1-slave dns-server-2 dns-server-2-slave

# 重启所有服务
docker compose restart

# 停止单个服务
docker compose stop dns-server-1
docker compose stop dns-server-2-slave

# 停止服务
docker compose down

# 完全清理（包括网络和卷）
docker compose down --volumes

# 查看实时日志
docker compose logs -f
docker compose logs -f dns-server-1                 # 只看 server-1 日志
docker compose logs -f dns-server-2-slave           # 只看 server-2-slave 日志

# 同时查看主从服务器日志
docker compose logs -f dns-server-2 dns-server-2-slave
```

## **验证完整流程**
```bash
# 步骤1：启动服务
docker compose up -d

# 步骤2：配置 dns-server-2（权威服务器-主）
docker compose exec -it dns-server-2 bash
# 执行上述 "配置 dns-server-2" 部分的所有命令
exit

# 步骤3：配置 dns-server-2-slave（权威服务器-从）
docker compose exec -it dns-server-2-slave bash
# 执行上述 "配置 dns-server-2-slave" 部分的所有命令
exit

# 步骤4：验证主从同步（server-2）
docker compose exec dns-server-2-slave ls -l /var/named/slaves/
# 应该看到 magedu.com.zone 文件
docker compose exec dns-server-2-slave cat /var/named/slaves/magedu.com.zone
# 内容应该与主服务器一致

# 步骤5：配置 dns-server-1（指定域转发服务器-主）
docker compose exec -it dns-server-1 bash
# 执行上述 "配置 dns-server-1" 部分的所有命令
exit

# 步骤6：配置 dns-server-1-slave（指定域转发服务器-从）
docker compose exec -it dns-server-1-slave bash
# 执行上述 "配置 dns-server-1-slave" 部分的所有命令
exit

# 步骤7：验证配置
docker compose exec dns-server-1 grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones
docker compose exec dns-server-1-slave grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones
docker compose exec dns-server-2 grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones
docker compose exec dns-server-2-slave grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones

# 步骤8：客户端测试
docker compose exec client nslookup www.magedu.com           # 应解析到 10.0.0.14（指定域转发）
docker compose exec client dig @10.0.0.13 www.baidu.com      # 应返回百度IP（直接递归）
docker compose exec client dig @10.0.0.17 www.magedu.com     # 测试从服务器
docker compose exec client curl http://www.magedu.com        # 应返回网页内容

# 步骤9：验证主从同步状态
docker compose exec dns-server-2 rndc zonestatus magedu.com      # 主服务器状态
docker compose exec dns-server-2-slave rndc zonestatus magedu.com  # 从服务器状态

# 步骤10：验证成功标志
# ✓ magedu.com 通过指定域转发解析正确
# ✓ 其他域名通过直接递归解析正确
# ✓ 主从服务器区域文件已同步
# ✓ 从服务器可以正确响应查询
# ✓ Web 请求返回页面内容
# ✓ 所有容器状态为 Up
```

## **注意事项**

1. **配置持久性问题**
   - 本示例为**手工配置**方式，配置文件不挂载到容器
   - 容器重启后配置会**丢失**，需要重新配置
   - 生产环境建议使用配置文件挂载方式（参考自动配置示例）

2. **主从配置顺序**
   - 必须先配置主服务器（dns-server-2 和 dns-server-1）
   - 确保主服务器配置正确且服务正常运行
   - 再配置从服务器（dns-server-2-slave 和 dns-server-1-slave）
   - 从服务器会自动从主服务器同步区域文件

3. **指定域转发配置注意**
   - `type forward` 只能用于 `zone` 配置段，不能用于 `options`
   - `forward only` 表示只转发不递归，转发失败会返回错误
   - 可配置多个域的转发，每个域一个 zone 配置

4. **区域传输安全**
   - 主服务器的 `allow-transfer` 选项限制了哪些服务器可以进行区域传输
   - 生产环境建议使用 TSIG 密钥认证来保护区域传输
   - 避免将 `allow-transfer` 设置为 `any;`

5. **序列号管理**
   - SOA 记录中的序列号（Serial）必须在每次修改区域文件时递增
   - 从服务器通过比较序列号来判断是否需要同步
   - 推荐使用格式：YYYYMMDDNN（如 2024010601）

6. **网络连通性**
   - 确保 dns-server-1 可以访问 dns-server-2 (10.0.0.15)
   - 确保从服务器可以访问对应的主服务器（端口 53 和 953）
   - 检查防火墙规则是否允许 UDP/TCP 53 端口和 TCP 953（rndc）

7. **转发策略选择**
   - 指定域转发推荐使用 `forward only`，确保转发行为可预测
   - 如需容错，可使用 `forward first`

8. **高可用性说明**
   - dns-server-1-slave 作为 dns-server-1 的备份，提供相同的转发功能
   - dns-server-2-slave 作为 dns-server-2 的备份，提供区域数据的冗余
   - 客户端可以配置多个 DNS 服务器实现故障转移

## **指定域转发的优势**

1. **灵活的路由策略**
   - 不同域名可以路由到不同的 DNS 服务器
   - 适合多数据中心、混合云架构

2. **性能优化**
   - 只转发特定域名，减少转发开销
   - 其他域名直接递归解析，减少网络跳数

3. **架构灵活**
   - 企业内部域名转发到内部 DNS
   - 公网域名直接递归解析
   - 合作伙伴域名转发到指定服务器

4. **故障隔离**
   - 转发目标故障不影响其他域名解析
   - 更好的容错能力
