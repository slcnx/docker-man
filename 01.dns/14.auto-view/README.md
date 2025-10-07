# DNS 视图 (DNS Views) - 自动化部署

这是一个预配置的 DNS 视图（分离视图/Split-Horizon DNS）环境，根据客户端来源网络返回不同的 DNS 解析结果。

## 架构说明

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        内网 (Internal Network)                               │
│                            10.0.0.0/24                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌──────────────┐    ┌──────────────┐         ┌──────────────┐             │
│  │    client    │    │   dns-server │  AXFR   │  dns-slave   │             │
│  │   -internal  │───►│  (主服务器)   │────────►│  (从服务器)   │             │
│  │  10.0.0.12   │    │  10.0.0.13   │ NOTIFY  │  10.0.0.15   │             │
│  └──────────────┘    │ internal-view│         │ internal-view│             │
│                      └──────┬───────┘         └──────┬───────┘             │
│                             │  返回 10.0.0.14        │                      │
│                             ▼                        ▼                      │
│                      ┌──────────────┐                                       │
│                      │     web      │                                       │
│                      │  -internal   │                                       │
│                      │  10.0.0.14   │                                       │
│                      │www.magedu.com│                                       │
│                      └──────────────┘                                       │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        外网 (External Network)                               │
│                           192.168.1.0/24                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  ┌──────────────┐    ┌──────────────┐         ┌──────────────┐             │
│  │    client    │    │   dns-server │  AXFR   │  dns-slave   │             │
│  │   -external  │───►│  (主服务器)   │────────►│  (从服务器)   │             │
│  │ 192.168.1.12 │    │ 192.168.1.13 │ NOTIFY  │ 192.168.1.15 │             │
│  └──────────────┘    │external-view │         │external-view │             │
│                      └──────┬───────┘         └──────┬───────┘             │
│                             │  返回 192.168.1.14     │                      │
│                             ▼                        ▼                      │
│                      ┌──────────────┐                                       │
│                      │     web      │                                       │
│                      │  -external   │                                       │
│                      │ 192.168.1.14 │                                       │
│                      │www.magedu.com│                                       │
│                      └──────────────┘                                       │
└─────────────────────────────────────────────────────────────────────────────┘

工作原理：
1. 内网客户端 (10.0.0.12) 查询 www.magedu.com → DNS 匹配 internal-view → 返回 10.0.0.14
2. 外网客户端 (192.168.1.12) 查询 www.magedu.com → DNS 匹配 external-view → 返回 192.168.1.14
3. 内网可访问 ftp/db/mail 等内部资源，外网无法访问（隐藏内部资源）
4. 主从复制：主服务器 (10.0.0.13 / 192.168.1.13) 通过 AXFR + NOTIFY 同步到从服务器 (10.0.0.15 / 192.168.1.15)
5. 每个视图（内网、外网）独立维护主从复制
```

## 快速开始

### 1. 启动所有容器

```bash
cd /root/docker-man/dns/14.auto-view
docker compose up -d
```

### 2. 查看测试结果

**内网客户端测试**:
```bash
docker logs auto-client-internal
```

预期输出：
```
===== DNS 视图测试 - 内网客户端 =====

客户端 IP: 10.0.0.12 (内网)

========== 1. 测试 www.magedu.com 解析 ==========
10.0.0.14
预期结果: 10.0.0.14 (内网 IP)

========== 2. 测试内网专属资源 ==========
2.1 查询 ftp.magedu.com (仅内网可见):
10.0.0.20
2.2 查询 db.magedu.com (仅内网可见):
10.0.0.30
2.3 查询 mail.magedu.com (仅内网可见):
10.0.0.40

========== 3. 测试 Web 访问 ==========
内网服务器

===== 内网客户端测试完成 =====
```

**外网客户端测试**:
```bash
docker logs auto-client-external
```

预期输出：
```
===== DNS 视图测试 - 外网客户端 =====

客户端 IP: 192.168.1.12 (外网)

========== 1. 测试 www.magedu.com 解析 ==========
192.168.1.14
预期结果: 192.168.1.14 (外网 IP)

========== 2. 测试内网专属资源（应该不可见）==========
2.1 查询 ftp.magedu.com (应该失败):
NXDOMAIN (不存在)
2.2 查询 db.magedu.com (应该失败):
NXDOMAIN (不存在)
2.3 查询 mail.magedu.com (应该失败):
NXDOMAIN (不存在)

========== 3. 测试 Web 访问 ==========
外网服务器

===== 外网客户端测试完成 =====
```

### 3. 手动验证

```bash
# 内网客户端测试
docker exec -it auto-client-internal bash
dig @10.0.0.13 www.magedu.com +short      # 应返回 10.0.0.14
dig @10.0.0.13 ftp.magedu.com +short      # 应返回 10.0.0.20
curl http://www.magedu.com                # 应显示 "内网服务器"

# 外网客户端测试
docker exec -it auto-client-external bash
dig @192.168.1.13 www.magedu.com +short   # 应返回 192.168.1.14
dig @192.168.1.13 ftp.magedu.com +short   # 应返回空或 NXDOMAIN
curl http://www.magedu.com                # 应显示 "外网服务器"
```

## 配置详解

### ACL 配置 (dns-configs/named.conf)

定义访问控制列表：

```conf
acl "internal-networks" {
    10.0.0.0/24;        // 内网网段
    localhost;
    localnets;
};

acl "external-networks" {
    192.168.1.0/24;     // 外网网段
    any;                // 其他所有
};
```

### 内网视图配置

```conf
view "internal-view" {
    match-clients { internal-networks; };    // 匹配内网客户端
    recursion yes;

    zone "magedu.com" IN {
        type master;
        file "zones/internal/magedu.com.zone";  // 内网区域文件
        allow-update { none; };
    };
};
```

### 外网视图配置

```conf
view "external-view" {
    match-clients { external-networks; };    // 匹配外网客户端
    recursion yes;

    zone "magedu.com" IN {
        type master;
        file "zones/external/magedu.com.zone";  // 外网区域文件
        allow-update { none; };
    };
};
```

### 内网区域文件 (zones/internal/magedu.com.zone)

包含所有资源记录（包括内部资源）：

```dns
$TTL 86400
@   IN  SOA dns-server.magedu.com. admin.magedu.com. (
        2024010601  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400 )     ; Minimum TTL

@       IN  NS  dns-server.magedu.com.

; A 记录 - 内网视图
dns-server  IN  A   10.0.0.13       ; DNS 服务器内网 IP
www         IN  A   10.0.0.14       ; Web 服务器内网 IP
ftp         IN  A   10.0.0.20       ; FTP 服务器（仅内网可见）
db          IN  A   10.0.0.30       ; 数据库服务器（仅内网可见）
mail        IN  A   10.0.0.40       ; 邮件服务器（仅内网可见）
```

### 外网区域文件 (zones/external/magedu.com.zone)

仅包含公开资源记录（隐藏内部资源）：

```dns
$TTL 86400
@   IN  SOA dns-server.magedu.com. admin.magedu.com. (
        2024010601  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400 )     ; Minimum TTL

@       IN  NS  dns-server.magedu.com.

; A 记录 - 外网视图
dns-server  IN  A   192.168.1.13    ; DNS 服务器外网 IP
www         IN  A   192.168.1.14    ; Web 服务器外网 IP
; 注意：ftp, db, mail 记录在外网视图中不存在（隐藏内部资源）
```

## 测试场景

### 1. 同名不同值测试

验证相同域名在不同网络返回不同 IP：

```bash
# 内网查询
docker exec auto-client-internal dig @10.0.0.13 www.magedu.com +short
# 预期: 10.0.0.14

# 外网查询
docker exec auto-client-external dig @192.168.1.13 www.magedu.com +short
# 预期: 192.168.1.14
```

### 2. 内部资源隐藏测试

验证内部资源仅在内网可见：

```bash
# 内网可以解析 ftp.magedu.com
docker exec auto-client-internal dig @10.0.0.13 ftp.magedu.com +short
# 预期: 10.0.0.20

# 外网无法解析 ftp.magedu.com
docker exec auto-client-external dig @192.168.1.13 ftp.magedu.com +short
# 预期: 空输出或 NXDOMAIN
```

### 3. Web 内容验证测试

验证访问相同域名时获得不同的 Web 内容：

```bash
# 内网访问
docker exec auto-client-internal curl -s http://www.magedu.com | grep -o "内网服务器"
# 预期: 内网服务器

# 外网访问
docker exec auto-client-external curl -s http://www.magedu.com | grep -o "外网服务器"
# 预期: 外网服务器
```

### 4. DNS 视图匹配测试

验证 DNS 服务器正确识别客户端来源：

```bash
# 查看 DNS 服务器日志，观察视图匹配
docker logs auto-dns-server | grep -i "view"

# 查看查询日志
docker exec auto-dns-server tail -f /var/log/named/query.log
```

### 5. 主从同步测试

验证主从服务器的区域数据同步：

```bash
# 5.1 对比主从服务器的 SOA 记录（内网视图）
docker exec auto-dns-server dig @10.0.0.13 magedu.com SOA +short
docker exec auto-dns-slave dig @10.0.0.15 magedu.com SOA +short
# 预期: 两个序列号相同

# 5.2 对比主从服务器的 SOA 记录（外网视图）
docker exec auto-dns-server dig @192.168.1.13 magedu.com SOA +short
docker exec auto-dns-slave dig @192.168.1.15 magedu.com SOA +short
# 预期: 两个序列号相同

# 5.3 验证从服务器内网视图同步
docker exec auto-dns-slave dig @10.0.0.15 www.magedu.com +short
# 预期: 10.0.0.14

docker exec auto-dns-slave dig @10.0.0.15 ftp.magedu.com +short
# 预期: 10.0.0.20 (内网专属记录已同步)

# 5.4 验证从服务器外网视图同步
docker exec auto-dns-slave dig @192.168.1.15 www.magedu.com +short
# 预期: 192.168.1.14

docker exec auto-dns-slave dig @192.168.1.15 ftp.magedu.com +short
# 预期: 空或 NXDOMAIN (外网视图无此记录)

# 5.5 查看从服务器的区域文件
docker exec auto-dns-slave ls -l /var/named/slaves/
# 预期: 看到 internal-magedu.com.zone 和 external-magedu.com.zone

# 5.6 查看区域传输日志
docker exec auto-dns-slave tail -20 /var/named/data/named.run | grep -i "transfer"
```

### 6. 区域传输测试

测试主服务器的区域传输功能：

```bash
# 从内网视图请求完整区域传输
docker exec auto-client-internal dig @10.0.0.13 magedu.com AXFR
# 预期: 显示完整的内网视图区域数据（包括 ftp, db, mail）

# 从外网视图请求完整区域传输
docker exec auto-client-external dig @192.168.1.13 magedu.com AXFR
# 预期: 显示完整的外网视图区域数据（仅 dns-server, www）
```

## 应用场景

### 1. 企业内外网分离

- **内网用户**: 访问内部 IP，速度快，可访问内部资源
- **外网用户**: 访问公网 IP，通过防火墙/NAT，无法访问内部资源

### 2. CDN 分发优化

- **不同地区**: 返回就近的 CDN 节点 IP
- **不同运营商**: 返回对应运营商的服务器 IP

### 3. 安全隐私保护

- **隐藏内部结构**: 外网无法发现内部服务器
- **访问控制**: 不同网络获得不同的服务访问权限

### 4. 多环境管理

- **开发环境**: 返回开发服务器 IP
- **测试环境**: 返回测试服务器 IP
- **生产环境**: 返回生产服务器 IP

## 故障排除

### 问题 1: 视图匹配错误

**症状**: 内网客户端获得外网 IP 或反之

**排查步骤**:
```bash
# 1. 检查 ACL 配置
docker exec auto-dns-server grep -A 5 "acl" /etc/named.conf

# 2. 检查客户端 IP
docker exec auto-client-internal ip addr show eth0
docker exec auto-client-external ip addr show eth0

# 3. 查看 DNS 服务器匹配的视图
docker logs auto-dns-server | grep -i "client.*view"

# 4. 验证配置语法
docker exec auto-dns-server named-checkconf
```

**解决方法**:
- 确认 ACL 定义包含正确的网段
- 检查 `match-clients` 配置
- 确保视图的顺序正确（更具体的视图在前）

### 问题 2: 内部资源对外可见

**症状**: 外网客户端可以解析 ftp/db/mail 等内部域名

**排查步骤**:
```bash
# 1. 检查外网区域文件
docker exec auto-dns-server cat /var/named/zones/external/magedu.com.zone

# 2. 验证外网客户端使用的视图
docker exec auto-client-external dig @192.168.1.13 ftp.magedu.com +short

# 3. 查看 DNS 查询日志
docker logs auto-dns-server | tail -20
```

**解决方法**:
- 确认外网区域文件不包含内部资源记录
- 检查视图配置是否正确加载了对应的区域文件

### 问题 3: DNS 服务器配置错误

**症状**: DNS 服务器启动失败或查询超时

**排查步骤**:
```bash
# 1. 检查配置文件语法
docker exec auto-dns-server named-checkconf

# 2. 检查区域文件语法
docker exec auto-dns-server named-checkzone magedu.com /var/named/zones/internal/magedu.com.zone
docker exec auto-dns-server named-checkzone magedu.com /var/named/zones/external/magedu.com.zone

# 3. 查看 DNS 服务器日志
docker logs auto-dns-server

# 4. 检查 DNS 服务状态
docker exec auto-dns-server ps aux | grep named
```

**解决方法**:
- 修复配置文件语法错误
- 确保区域文件路径正确
- 检查文件权限（named 用户可读）

### 问题 4: 网络隔离问题

**症状**: 客户端无法连接到 DNS 服务器

**排查步骤**:
```bash
# 1. 检查网络连通性
docker exec auto-client-internal ping -c 2 10.0.0.13
docker exec auto-client-external ping -c 2 192.168.1.13

# 2. 检查 DNS 服务监听端口
docker exec auto-dns-server netstat -ulnp | grep :53

# 3. 检查 Docker 网络配置
docker network inspect 14auto-view_internal-net
docker network inspect 14auto-view_external-net

# 4. 查看容器网络接口
docker exec auto-dns-server ip addr
```

**解决方法**:
- 确认 DNS 服务器同时在两个网络中
- 检查防火墙规则（iptables）
- 验证 Docker 网络配置正确

### 问题 5: Web 访问错误

**症状**: curl 返回错误或无法访问

**排查步骤**:
```bash
# 1. 测试 DNS 解析
docker exec auto-client-internal dig @10.0.0.13 www.magedu.com +short

# 2. 测试直接 IP 访问
docker exec auto-client-internal curl -I http://10.0.0.14
docker exec auto-client-external curl -I http://192.168.1.14

# 3. 检查 Web 服务器状态
docker ps | grep web

# 4. 查看 Web 服务器日志
docker logs auto-web-internal
docker logs auto-web-external
```

**解决方法**:
- 确认 DNS 解析返回正确 IP
- 检查 Web 服务器容器正常运行
- 验证 HTML 文件存在且可读

### 问题 6: 主从同步失败

**症状**: 从服务器 SOA 序列号与主服务器不一致，或无法解析域名

**排查步骤**:
```bash
# 1. 检查从服务器是否收到区域文件
docker exec auto-dns-slave ls -l /var/named/slaves/
# 应该看到 internal-magedu.com.zone 和 external-magedu.com.zone

# 2. 对比主从 SOA 记录
docker exec auto-dns-server dig @10.0.0.13 magedu.com SOA +short
docker exec auto-dns-slave dig @10.0.0.15 magedu.com SOA +short

# 3. 查看从服务器日志
docker logs auto-dns-slave | grep -i "transfer\|notify"

# 4. 检查主服务器的 allow-transfer 配置
docker exec auto-dns-server grep -A 3 "allow-transfer" /etc/named.conf

# 5. 检查网络连通性
docker exec auto-dns-slave ping -c 2 10.0.0.13
docker exec auto-dns-slave ping -c 2 192.168.1.13

# 6. 手动触发区域传输
docker exec auto-dns-slave rndc refresh magedu.com

# 7. 验证传输结果
docker exec auto-dns-slave dig @10.0.0.15 magedu.com SOA +short
```

**解决方法**:
- 确认主服务器的 `allow-transfer` 包含从服务器 IP
- 确认主服务器的 `also-notify` 配置正确
- 检查从服务器的 `masters` 配置指向正确的主服务器 IP
- 确保 `/var/named/slaves` 目录存在且权限正确 (770, named:named)
- 重启从服务器容器: `docker compose restart dns-slave`
- 查看详细日志: `docker exec auto-dns-slave tail -50 /var/named/data/named.run`

## 清理环境

```bash
# 停止并删除所有容器
docker compose down

# 删除网络
docker network prune

# 重新启动
docker compose up -d
```

## 技术要点

### 1. DNS 视图 (Views)

- **视图匹配**: 基于客户端源 IP 地址匹配不同的视图
- **视图顺序**: 从上到下匹配，第一个匹配的视图生效
- **视图隔离**: 每个视图维护独立的区域配置和缓存

### 2. ACL (访问控制列表)

- **预定义 ACL**: localhost, localnets, any, none
- **自定义 ACL**: 定义特定的 IP 地址范围
- **ACL 嵌套**: ACL 可以包含其他 ACL

### 3. 安全最佳实践

- **最小权限原则**: 外网视图仅暴露必要的资源
- **内部资源隐藏**: 敏感服务器记录不出现在外网视图
- **递归控制**: 根据客户端来源控制递归查询权限

### 4. 主从复制 (Master-Slave Replication)

- **AXFR**: 完整区域传输（首次同步或序列号不连续时）
- **IXFR**: 增量区域传输（后续更新，序列号连续时）
- **NOTIFY**: 主服务器主动通知从服务器区域变更
- **SOA Serial**: 序列号控制版本，序列号增加触发同步
- **视图隔离**: 每个视图独立维护主从复制关系

主从配置要点：
- **主服务器**: `allow-transfer` 指定允许传输的从服务器 IP
- **主服务器**: `also-notify` 指定需要通知的从服务器 IP
- **从服务器**: `type slave` 声明为从服务器
- **从服务器**: `masters` 指定主服务器 IP
- **从服务器**: 区域文件自动保存在 `slaves/` 目录

### 5. 性能优化

- **视图缓存**: 每个视图独立缓存，提高查询效率
- **区域文件分离**: 内外网区域文件分开管理，便于维护
- **主从冗余**: 提供高可用性和负载均衡
- **健康检查**: 确保服务就绪后再接受请求

## 与手动配置的区别

与 `13.manual-view` 相比，本示例：

| 特性 | 手动配置 (13) | 自动化配置 (14) |
|------|--------------|----------------|
| 配置文件 | 容器启动后手动创建 | 预先准备好 |
| 区域文件 | 手动编写 | 预先创建（内外网分离） |
| 主从复制 | 手动配置主从关系 | 预先配置（主从自动同步） |
| HTML 页面 | 手动创建 | 预先准备好 |
| 测试 | 手动执行命令 | 自动测试脚本 |
| ACL 定义 | 手动配置 | 预先定义 |
| 健康检查 | 无 | 自动健康检查和依赖管理 |
| 适用场景 | 学习理解 | 生产部署 |

## 扩展练习

### 1. 添加更多内部资源

编辑 `dns-configs/zones/internal/magedu.com.zone`：

```dns
jenkins     IN  A   10.0.0.50       ; Jenkins 服务器
gitlab      IN  A   10.0.0.60       ; GitLab 服务器
monitor     IN  A   10.0.0.70       ; 监控服务器
```

重启 DNS 服务器：
```bash
docker compose restart dns-server
```

### 2. 添加第三个视图（VPN 网络）

在 `named.conf` 中添加：

```conf
acl "vpn-networks" {
    172.16.0.0/24;
};

view "vpn-view" {
    match-clients { vpn-networks; };
    recursion yes;

    zone "magedu.com" IN {
        type master;
        file "zones/vpn/magedu.com.zone";
    };
};
```

### 3. 添加反向解析视图

为内网添加反向解析：

```conf
view "internal-view" {
    // ... 现有配置 ...

    zone "0.0.10.in-addr.arpa" IN {
        type master;
        file "zones/internal/10.0.0.rev";
    };
};
```

反向区域文件示例：
```dns
$TTL 86400
@   IN  SOA dns-server.magedu.com. admin.magedu.com. (
        2024010601 3600 1800 604800 86400 )

@       IN  NS  dns-server.magedu.com.

13      IN  PTR dns-server.magedu.com.
14      IN  PTR www.magedu.com.
20      IN  PTR ftp.magedu.com.
```

## 参考资料

- BIND 9 Administrator Reference Manual - Views
- RFC 1918: 私有网络地址分配
- Split-Horizon DNS 最佳实践
- DNS 安全配置指南
