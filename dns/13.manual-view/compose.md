# DNS 视图（View）- 手工配置

## **网络架构概览**
```
双网络架构（内网 + 外网）+ 主从 DNS

内网网络 (10.0.0.0/24):
├── 10.0.0.1   - 网关
├── 10.0.0.12  - 内网客户端 (client-internal)
├── 10.0.0.13  - DNS 主服务器（内网接口）
├── 10.0.0.14  - 内网 Web 服务器 (web-internal)
└── 10.0.0.15  - DNS 从服务器（内网接口）

外网网络 (192.168.1.0/24):
├── 192.168.1.1   - 网关
├── 192.168.1.12  - 外网客户端 (client-external)
├── 192.168.1.13  - DNS 主服务器（外网接口）
├── 192.168.1.14  - 外网 Web 服务器 (web-external)
└── 192.168.1.15  - DNS 从服务器（外网接口）

DNS 视图机制：
- 内网客户端查询 www.magedu.com → 返回 10.0.0.14 (内网服务器)
- 外网客户端查询 www.magedu.com → 返回 192.168.1.14 (外网服务器)
- 同一域名，不同来源，不同结果！

主从复制：
- 主服务器：10.0.0.13 / 192.168.1.13
- 从服务器：10.0.0.15 / 192.168.1.15
- 两个视图（internal-view, external-view）分别配置主从复制
- 使用 AXFR 进行完整区域传输
- 使用 NOTIFY 机制实时通知从服务器更新
```

## **服务启动**
```bash
# 1. 启动所有服务
docker compose up -d

# 2. 检查服务状态
docker compose ps

# 3. 查看网络配置
docker network inspect 13manual-view_internal-net
docker network inspect 13manual-view_external-net
```

## **DNS 服务器配置**

### **配置 DNS 服务器（启用视图功能）**
```bash
# 进入 DNS 服务器容器
docker compose exec -it dns-server bash

# 1. 编辑主配置文件，添加 ACL 和 View
vim /etc/named.conf

# 在文件开头添加 ACL 定义（在 options 之前）
// 定义访问控制列表（ACL）
acl "internal-networks" {
    10.0.0.0/24;        # 内网网段
    localhost;          # 本地
    localnets;          # 本地网段
};

acl "external-networks" {
    192.168.1.0/24;     # 外网网段
    any;                # 其他所有（可根据需要调整）
};

include "/etc/rndc.key";

options {
    //listen-on port 53 { 127.0.0.1; };
    //listen-on-v6 port 53 { ::1; };
    directory     "/var/named";
    dump-file     "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file    "/var/named/data/named.secroots";
    recursing-file    "/var/named/data/named.recursing";

    // 注意：启用 view 后，allow-query 等指令需要在 view 中配置
    recursion yes;
    dnssec-validation no;

    pid-file "/run/named/named.pid";
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
    channel query_log {
        file "/var/log/named/query.log" versions 3 size 10m;
        severity info;
        print-category yes;
        print-severity yes;
        print-time yes;
    };
    category queries {
        query_log;
    };
};

// ========== 内网视图 ==========
view "internal-view" {
    match-clients { internal-networks; };  # 匹配内网客户端
    recursion yes;                          # 允许递归查询

    zone "." IN {
        type hint;
        file "named.ca";
    };

    zone "magedu.com" IN {
        type master;
        file "internal/magedu.com.zone";    # 内网区域文件
        allow-update { none; };
        allow-transfer { 10.0.0.15; };      # 允许从服务器传输
        also-notify { 10.0.0.15; };         # 通知从服务器更新
    };

    zone "localhost.localdomain" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
    };

    zone "localhost" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
    };

    zone "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
    };

    zone "1.0.0.127.in-addr.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
    };

    zone "0.in-addr.arpa" IN {
        type master;
        file "named.empty";
        allow-update { none; };
    };

    include "/etc/named.root.key";
};

// ========== 外网视图 ==========
view "external-view" {
    match-clients { external-networks; };   # 匹配外网客户端
    recursion yes;                          # 允许递归查询

    zone "." IN {
        type hint;
        file "named.ca";
    };

    zone "magedu.com" IN {
        type master;
        file "external/magedu.com.zone";    # 外网区域文件
        allow-update { none; };
        allow-transfer { 192.168.1.15; };   # 允许从服务器传输
        also-notify { 192.168.1.15; };      # 通知从服务器更新
    };

    zone "localhost.localdomain" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
    };

    zone "localhost" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
    };

    zone "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
    };

    zone "1.0.0.127.in-addr.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
    };

    zone "0.in-addr.arpa" IN {
        type master;
        file "named.empty";
        allow-update { none; };
    };

    include "/etc/named.root.key";
};

controls {
    inet * port 953 allow { any; } keys { "rndc-key"; };
};

# 2. 创建区域文件目录
mkdir -p /var/named/internal
mkdir -p /var/named/external

# 3. 创建内网区域文件
cat > /var/named/internal/magedu.com.zone << 'EOF'
$TTL 86400
@   IN  SOA dns-server.magedu.com. admin.magedu.com. (
        2024010601  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400 )     ; Minimum TTL

; 名称服务器记录
@       IN  NS  dns-server.magedu.com.

; A 记录 - 内网视图
dns-server  IN  A   10.0.0.13       ; DNS 服务器内网 IP
www         IN  A   10.0.0.14       ; Web 服务器内网 IP
ftp         IN  A   10.0.0.20       ; FTP 服务器（仅内网可见）
db          IN  A   10.0.0.30       ; 数据库服务器（仅内网可见）
EOF

# 4. 创建外网区域文件
cat > /var/named/external/magedu.com.zone << 'EOF'
$TTL 86400
@   IN  SOA dns-server.magedu.com. admin.magedu.com. (
        2024010601  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400 )     ; Minimum TTL

; 名称服务器记录
@       IN  NS  dns-server.magedu.com.

; A 记录 - 外网视图
dns-server  IN  A   192.168.1.13    ; DNS 服务器外网 IP
www         IN  A   192.168.1.14    ; Web 服务器外网 IP
; 注意：ftp 和 db 记录在外网视图中不存在（隐藏内部资源）
EOF

# 5. 修改文件所有权和权限
chown -R named.named /var/named/internal
chown -R named.named /var/named/external
chmod 640 /var/named/internal/magedu.com.zone
chmod 640 /var/named/external/magedu.com.zone

# 6. 检查区域文件语法
named-checkzone magedu.com /var/named/internal/magedu.com.zone
named-checkzone magedu.com /var/named/external/magedu.com.zone

# 7. 检查总配置
named-checkconf /etc/named.conf

# 8. 重新加载配置
rndc reload
rndc status

# 9. 退出容器
exit
```

### **配置从服务器（启用视图 + 主从复制）**
```bash
# 进入从服务器容器
docker compose exec -it dns-slave bash

# 1. 编辑主配置文件，配置从服务器视图
vim /etc/named.conf

# 添加相同的 ACL 定义和基础配置，然后配置从视图：

// 定义访问控制列表（ACL）- 与主服务器相同
acl "internal-networks" {
    10.0.0.0/24;
    localhost;
    localnets;
};

acl "external-networks" {
    192.168.1.0/24;
    any;
};

include "/etc/rndc.key";

options {
    directory     "/var/named";
    dump-file     "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    secroots-file    "/var/named/data/named.secroots";
    recursing-file    "/var/named/data/named.recursing";

    recursion yes;
    dnssec-validation no;

    pid-file "/run/named/named.pid";
};

logging {
    channel default_debug {
        file "data/named.run";
        severity dynamic;
    };
};

// ========== 内网视图（从服务器）==========
view "internal-view" {
    match-clients { internal-networks; };
    recursion yes;

    zone "." IN {
        type hint;
        file "named.ca";
    };

    zone "magedu.com" IN {
        type slave;                         # 从服务器类型
        file "slaves/internal-magedu.com.zone";  # 从服务器区域文件存储位置
        masters { 10.0.0.13; };            # 主服务器内网 IP
    };

    zone "localhost.localdomain" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
    };

    zone "localhost" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
    };

    zone "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
    };

    zone "1.0.0.127.in-addr.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
    };

    zone "0.in-addr.arpa" IN {
        type master;
        file "named.empty";
        allow-update { none; };
    };

    include "/etc/named.root.key";
};

// ========== 外网视图（从服务器）==========
view "external-view" {
    match-clients { external-networks; };
    recursion yes;

    zone "." IN {
        type hint;
        file "named.ca";
    };

    zone "magedu.com" IN {
        type slave;                         # 从服务器类型
        file "slaves/external-magedu.com.zone";  # 从服务器区域文件存储位置
        masters { 192.168.1.13; };         # 主服务器外网 IP
    };

    zone "localhost.localdomain" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
    };

    zone "localhost" IN {
        type master;
        file "named.localhost";
        allow-update { none; };
    };

    zone "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
    };

    zone "1.0.0.127.in-addr.arpa" IN {
        type master;
        file "named.loopback";
        allow-update { none; };
    };

    zone "0.in-addr.arpa" IN {
        type master;
        file "named.empty";
        allow-update { none; };
    };

    include "/etc/named.root.key";
};

controls {
    inet * port 953 allow { any; } keys { "rndc-key"; };
};

# 2. 创建从服务器区域文件目录
mkdir -p /var/named/slaves
chown named.named /var/named/slaves
chmod 770 /var/named/slaves

# 3. 检查配置语法
named-checkconf /etc/named.conf

# 4. 重新加载配置（自动触发区域传输）
rndc reload
rndc status

# 5. 验证区域传输
# 等待几秒钟后，检查从服务器是否成功接收区域文件
ls -l /var/named/slaves/
# 应该看到 internal-magedu.com.zone 和 external-magedu.com.zone

# 6. 查看区域传输日志
tail -20 /var/named/data/named.run

# 7. 退出容器
exit
```

## **主从同步验证**
```bash
# 1. 在主服务器上查询 SOA 记录
docker compose exec dns-server dig @10.0.0.13 magedu.com SOA +short
# 预期输出：dns-server.magedu.com. admin.magedu.com. 2024010601 3600 1800 604800 86400

# 2. 在从服务器上查询 SOA 记录（内网）
docker compose exec dns-slave dig @10.0.0.15 magedu.com SOA +short
# 预期输出：相同的 SOA 记录

# 3. 在从服务器上查询 SOA 记录（外网）
docker compose exec dns-slave dig @192.168.1.15 magedu.com SOA +short
# 预期输出：相同的 SOA 记录

# 4. 验证内网视图同步
docker compose exec dns-slave dig @10.0.0.15 www.magedu.com +short
# 预期输出：10.0.0.14 (内网 IP)

docker compose exec dns-slave dig @10.0.0.15 ftp.magedu.com +short
# 预期输出：10.0.0.20 (内网专属记录)

# 5. 验证外网视图同步
docker compose exec dns-slave dig @192.168.1.15 www.magedu.com +short
# 预期输出：192.168.1.14 (外网 IP)

docker compose exec dns-slave dig @192.168.1.15 ftp.magedu.com +short
# 预期输出：空或 NXDOMAIN (外网不可见)

# 6. 查看从服务器的区域文件内容
docker compose exec dns-slave cat /var/named/slaves/internal-magedu.com.zone
docker compose exec dns-slave cat /var/named/slaves/external-magedu.com.zone
```

## **客户端测试**

### **内网客户端测试**
```bash
# 进入内网客户端容器
docker compose exec -it client-internal bash

# 1. 安装 DNS 工具
yum install -y bind-utils curl iputils

# 2. 查看客户端 IP（确认在内网）
hostname -I
# 应该显示：10.0.0.12

# 3. 测试 DNS 解析（内网视图）
nslookup www.magedu.com
# 应该返回：10.0.0.14 (内网 IP)

dig www.magedu.com +short
# 应该返回：10.0.0.14

# 4. 测试内网专属记录
nslookup ftp.magedu.com
# 应该返回：10.0.0.20 (仅内网可见)

nslookup db.magedu.com
# 应该返回：10.0.0.30 (仅内网可见)

# 5. 测试 Web 访问
curl http://www.magedu.com
# 应该显示：内网 Web 服务器页面

curl http://10.0.0.14
# 应该显示：内网 Web 服务器页面

# 6. 查看所有 A 记录
dig magedu.com AXFR
# 注意：生产环境应禁止 AXFR

# 7. 退出容器
exit
```

### **外网客户端测试**
```bash
# 进入外网客户端容器
docker compose exec -it client-external bash

# 1. 安装 DNS 工具
yum install -y bind-utils curl iputils

# 2. 查看客户端 IP（确认在外网）
hostname -I
# 应该显示：192.168.1.12

# 3. 测试 DNS 解析（外网视图）
nslookup www.magedu.com
# 应该返回：192.168.1.14 (外网 IP)

dig www.magedu.com +short
# 应该返回：192.168.1.14

# 4. 测试内网专属记录（应该不可见）
nslookup ftp.magedu.com
# 应该返回：NXDOMAIN (不存在)

nslookup db.magedu.com
# 应该返回：NXDOMAIN (不存在)

# 5. 测试 Web 访问
curl http://www.magedu.com
# 应该显示：外网 Web 服务器页面

curl http://192.168.1.14
# 应该显示：外网 Web 服务器页面

# 6. 退出容器
exit
```

### **对比测试（从主机执行）**
```bash
# 对比内外网解析结果
echo "=== 内网客户端解析 www.magedu.com ==="
docker compose exec client-internal dig www.magedu.com +short

echo "=== 外网客户端解析 www.magedu.com ==="
docker compose exec client-external dig www.magedu.com +short

# 测试内网专属资源
echo "=== 内网客户端解析 ftp.magedu.com ==="
docker compose exec client-internal dig ftp.magedu.com +short

echo "=== 外网客户端解析 ftp.magedu.com（应该失败）==="
docker compose exec client-external dig ftp.magedu.com +short
```

## **验证视图功能**
```bash
# 1. 查看 DNS 服务器日志（观察不同客户端的查询）
docker compose exec dns-server tail -f /var/log/named/query.log

# 2. 在另一个终端分别从内外网客户端发起查询
docker compose exec client-internal dig www.magedu.com
docker compose exec client-external dig www.magedu.com

# 3. 观察日志中的差异：
# - 内网客户端（10.0.0.12）命中 internal-view
# - 外网客户端（192.168.1.12）命中 external-view

# 4. 验证 ACL 匹配
docker compose exec dns-server rndc status
```

## **配置说明**

### **ACL（访问控制列表）**
```conf
# 定义客户端组
acl "internal-networks" {
    10.0.0.0/24;        # 内网网段
    localhost;
    localnets;
};

acl "external-networks" {
    192.168.1.0/24;     # 外网网段
    any;                # 其他所有
};
```

### **View（视图）配置**
```conf
view "internal-view" {
    match-clients { internal-networks; };  # 匹配规则
    recursion yes;                          # 递归查询

    zone "magedu.com" IN {
        type master;
        file "internal/magedu.com.zone";    # 视图专用区域文件
    };
    // ... 其他区域配置
};
```

### **View 匹配顺序**
1. BIND 按照配置文件中 view 的顺序进行匹配
2. 第一个匹配成功的 view 被使用
3. 如果所有 view 都不匹配，查询被拒绝
4. **重要**：确保 match-clients 规则互斥或有明确的优先级

### **视图隔离说明**
- **内网视图**：
  - 可见记录：www, ftp, db, dns-server
  - www.magedu.com → 10.0.0.14（内网 IP）
  - 可访问内部资源（ftp, db）

- **外网视图**：
  - 可见记录：www, dns-server
  - www.magedu.com → 192.168.1.14（外网 IP）
  - 内部资源不可见（安全隔离）

## **DNS 视图工作流程**

### **内网客户端查询流程**
```
1. client-internal (10.0.0.12) → dns-server (10.0.0.13): 查询 www.magedu.com
2. DNS 服务器检查客户端 IP：10.0.0.12
3. 匹配 ACL "internal-networks"（10.0.0.0/24）
4. 使用 "internal-view" 视图
5. 从 /var/named/internal/magedu.com.zone 读取记录
6. 返回 A 记录：10.0.0.14
```

### **外网客户端查询流程**
```
1. client-external (192.168.1.12) → dns-server (192.168.1.13): 查询 www.magedu.com
2. DNS 服务器检查客户端 IP：192.168.1.12
3. 匹配 ACL "external-networks"（192.168.1.0/24）
4. 使用 "external-view" 视图
5. 从 /var/named/external/magedu.com.zone 读取记录
6. 返回 A 记录：192.168.1.14
```

## **故障排除**
```bash
# 1. 检查服务状态
docker compose ps -a

# 2. 查看服务日志
docker compose logs dns-server
docker compose logs web-internal
docker compose logs web-external

# 3. 检查 DNS 配置
docker compose exec dns-server named-checkconf

# 4. 检查 ACL 和 View 配置
docker compose exec dns-server grep -A 5 "acl" /etc/named.conf
docker compose exec dns-server grep -A 10 "view" /etc/named.conf

# 5. 检查区域文件
docker compose exec dns-server cat /var/named/internal/magedu.com.zone
docker compose exec dns-server cat /var/named/external/magedu.com.zone

# 6. 测试网络连通性
docker compose exec client-internal ping -c 2 10.0.0.13
docker compose exec client-external ping -c 2 192.168.1.13

# 7. 测试 DNS 解析
docker compose exec client-internal nslookup www.magedu.com
docker compose exec client-external nslookup www.magedu.com

# 8. 查看 DNS 服务状态
docker compose exec dns-server rndc status

# 9. 查看查询日志
docker compose exec dns-server tail -100 /var/log/named/query.log

# 10. 重新加载配置
docker compose exec dns-server rndc reload

# 11. 调试 View 匹配
# 查看哪个 view 被匹配
docker compose exec dns-server tail -f /var/log/named/query.log
# 然后在另一个终端发起查询，观察日志
```

## **服务管理**
```bash
# 启动服务
docker compose up -d

# 重启服务
docker compose restart

# 重启特定服务
docker compose restart dns-server
docker compose restart web-internal

# 停止服务
docker compose down

# 查看实时日志
docker compose logs -f
docker compose logs -f dns-server
```

## **验证完整流程**
```bash
# 步骤1：启动服务
docker compose up -d

# 步骤2：配置 DNS 服务器
docker compose exec -it dns-server bash
# 执行上述 "配置 DNS 服务器" 部分的所有命令
exit

# 步骤3：验证配置
docker compose exec dns-server named-checkconf
docker compose exec dns-server rndc status

# 步骤4：内网客户端测试
docker compose exec client-internal nslookup www.magedu.com
# 应返回：10.0.0.14

docker compose exec client-internal curl -s http://www.magedu.com | grep "内网"
# 应显示：内网服务器

# 步骤5：外网客户端测试
docker compose exec client-external nslookup www.magedu.com
# 应返回：192.168.1.14

docker compose exec client-external curl -s http://www.magedu.com | grep "外网"
# 应显示：外网服务器

# 步骤6：验证内网专属资源
docker compose exec client-internal nslookup ftp.magedu.com
# 应返回：10.0.0.20

docker compose exec client-external nslookup ftp.magedu.com
# 应返回：NXDOMAIN（不存在）

# 步骤7：验证成功标志
# ✓ 内网客户端解析到内网 IP
# ✓ 外网客户端解析到外网 IP
# ✓ 内网专属资源仅内网可见
# ✓ 两个客户端看到不同的 Web 页面
# ✓ 所有容器状态为 Up
```

## **注意事项**

1. **配置持久性问题**
   - 本示例为**手工配置**方式，配置文件不挂载到容器
   - 容器重启后配置会**丢失**，需要重新配置
   - 生产环境建议使用配置文件挂载方式（参考自动配置示例）

2. **View 配置顺序**
   - View 按配置顺序匹配
   - 第一个匹配成功的 view 被使用
   - 建议从最具体到最通用的顺序配置

3. **ACL 规则设计**
   - 确保 ACL 规则互斥或有明确的优先级
   - 使用 `any` 要谨慎，可能导致意外匹配

4. **安全隐藏**
   - 外网视图只暴露必要的资源
   - 内部资源（ftp, db 等）不在外网视图中定义
   - 防止信息泄露

5. **序列号管理**
   - 不同视图的区域文件可以有不同的序列号
   - 修改任一视图的区域文件都要递增序列号

6. **网络连通性**
   - DNS 服务器需要连接到所有网络
   - 确保客户端可以访问对应网络的 DNS 接口

7. **日志查看**
   - 查询日志会显示客户端 IP 和匹配的 view
   - 有助于调试 view 匹配问题

## **DNS View 的应用场景**

1. **内外网分离**
   - 内网用户访问内网服务器
   - 外网用户访问外网服务器（DMZ）
   - 同一域名，不同目标

2. **安全隔离**
   - 隐藏内部网络拓扑
   - 内部资源仅内网可见
   - 防止信息泄露

3. **CDN 和地理位置路由**
   - 不同地区用户访问最近的服务器
   - 运营商线路优化

4. **测试和生产环境分离**
   - 测试环境和生产环境使用不同的 view
   - 同一域名指向不同环境

5. **负载均衡和故障转移**
   - 不同视图返回不同的服务器池
   - 实现简单的负载均衡
