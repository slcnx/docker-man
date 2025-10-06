# DNS 全局转发 + 主从复制 - 自动化部署

## 概述
这是一个完全自动化的 DNS 全局转发 + 主从复制部署方案，演示了企业级 DNS 架构，包括：
- **全局转发**：DNS Server 1 将查询转发到 DNS Server 2
- **主从复制**：每个 DNS 服务器都有对应的从服务器，提供高可用性
- **区域管理**：DNS Server 2 作为 magedu.com 域的权威服务器
- **递归解析**：DNS Server 2 为转发服务器提供递归 DNS 解析

用户只需执行 `docker compose up -d` 即可完成整个环境的部署和自动测试。

## 目录结构
```
10.auto-global-forward/
├── compose.yml                      # Docker Compose 配置文件
├── README.md                        # 说明文档
├── dns-server-1-configs/            # DNS Server 1 (主转发服务器) 配置
│   └── named.conf
├── dns-server-1-slave-configs/      # DNS Server 1 Slave (从转发服务器) 配置
│   └── named.conf
├── dns-server-2-configs/            # DNS Server 2 (主权威+递归服务器) 配置
│   ├── named.conf
│   ├── named.rfc1912.zones
│   └── magedu.com.zone              # magedu.com 区域文件
├── dns-server-2-slave-configs/      # DNS Server 2 Slave (从权威+递归服务器) 配置
│   ├── named.conf
│   └── named.rfc1912.zones
└── html/                            # Web 服务器内容
    └── index.html
```

## 网络架构
```
10.0.0.0/24 网络拓扑（全局转发 + 主从复制架构）
├── 10.0.0.1   - 网关
├── 10.0.0.12  - 客户端 (auto-dns-client)
├── 10.0.0.13  - DNS Server 1 主 (auto-dns-server-1) [转发服务器-Master]
├── 10.0.0.16  - DNS Server 1 从 (auto-dns-server-1-slave) [转发服务器-Slave]
├── 10.0.0.14  - Web 服务器 (auto-web-server / www.magedu.com)
├── 10.0.0.15  - DNS Server 2 主 (auto-dns-server-2) [权威+递归服务器-Master]
└── 10.0.0.17  - DNS Server 2 从 (auto-dns-server-2-slave) [权威+递归服务器-Slave]

DNS 转发流程：
client → dns-server-1 (全局转发) → dns-server-2 (权威解析/递归解析) → Internet

主从复制流程：
dns-server-1 (Master) ⇄ dns-server-1-slave (Slave) [转发配置相同]
dns-server-2 (Master) ⇄ dns-server-2-slave (Slave) [区域同步]
```

## 快速启动

### 一键启动
```bash
# 进入目录
cd /root/docker-man/dns/10.auto-global-forward

# 启动所有服务（自动部署 + 自动测试）
docker compose up -d

# 查看服务状态
docker compose ps

# 查看自动测试结果
docker logs auto-dns-client
```

### 查看测试输出
启动后，客户端会自动执行以下测试并输出结果：
```bash
docker logs -f auto-dns-client
```

预期输出：
```
===== DNS 全局转发 + 主从复制自动化测试开始 =====

========== 1. 测试本地域名解析 (magedu.com) ==========
1.1 通过主转发服务器 (server-1) 查询:
10.0.0.14
1.2 通过从转发服务器 (server-1-slave) 查询:
10.0.0.14
1.3 通过主权威服务器 (server-2) 查询:
10.0.0.14
1.4 通过从权威服务器 (server-2-slave) 查询:
10.0.0.14

========== 2. 验证主从 NS 记录 ==========
dns-server-2.magedu.com.
dns-server-2-slave.magedu.com.

========== 3. 测试外部域名解析（通过转发） ==========
3.1 通过主转发服务器查询:
xxx.xxx.xxx.xxx
3.2 通过从转发服务器查询:
xxx.xxx.xxx.xxx

========== 4. 测试 Web 访问 ==========
<h1>Welcome to magedu.com</h1>

========== 5. 验证主从同步状态 ==========
5.1 检查从服务器区域文件:
-rw-r--r-- 1 named named 423 ... /var/named/slaves/magedu.com.zone

===== 测试完成，容器保持运行 =====
```

## 自动化特性

### 1. 配置文件自动挂载
- 所有 DNS 配置文件预先准备好
- 自动挂载到对应容器
- 无需手动进入容器配置

### 2. 主从自动同步
- DNS Server 2 Slave 自动从主服务器同步 magedu.com 区域
- 使用 Docker volume 持久化从服务器数据
- 自动 NOTIFY 和 AXFR 区域传输

### 3. 健康检查
- DNS Server 1/1-Slave：`dig @127.0.0.1 www.baidu.com`（验证转发功能）
- DNS Server 2/2-Slave：`dig @127.0.0.1 www.magedu.com`（验证权威解析）
- Web Server：`wget --spider http://localhost`

### 4. 依赖管理
- 客户端等待所有 DNS 服务器和 Web 服务器健康后才启动
- 从服务器等待主服务器健康后启动
- 确保服务按正确顺序启动

### 5. 自动测试
客户端启动后自动执行全面测试：
- 本地域名解析测试（4 个 DNS 服务器）
- 主从 NS 记录验证
- 外部域名解析测试（通过转发）
- Web 访问测试
- 主从同步状态验证

## 验证测试

### 手动测试 DNS 解析
```bash
# 进入客户端容器
docker exec -it auto-dns-client bash

# 测试本地域名（magedu.com）
dig @10.0.0.13 www.magedu.com          # 主转发服务器
dig @10.0.0.16 www.magedu.com          # 从转发服务器
dig @10.0.0.15 www.magedu.com          # 主权威服务器
dig @10.0.0.17 www.magedu.com          # 从权威服务器

# 验证 NS 记录（应该看到两个 NS）
dig @10.0.0.15 NS magedu.com
dig @10.0.0.17 NS magedu.com

# 测试外部域名（通过转发）
dig @10.0.0.13 www.baidu.com           # 通过主转发
dig @10.0.0.16 www.baidu.com           # 通过从转发

# 使用 nslookup 测试
nslookup www.magedu.com                # 默认使用 10.0.0.13
nslookup www.magedu.com 10.0.0.17      # 指定从服务器
```

### 验证主从同步
```bash
# 查看主服务器区域文件
docker exec auto-dns-server-2 cat /var/named/magedu.com.zone

# 查看从服务器同步的区域文件
docker exec auto-dns-server-2-slave cat /var/named/slaves/magedu.com.zone

# 验证区域状态
docker exec auto-dns-server-2 rndc zonestatus magedu.com
docker exec auto-dns-server-2-slave rndc zonestatus magedu.com

# 检查序列号是否一致
docker exec auto-dns-server-2 dig @127.0.0.1 SOA magedu.com
docker exec auto-dns-server-2-slave dig @127.0.0.1 SOA magedu.com
```

### 测试故障转移
```bash
# 停止主转发服务器
docker compose stop dns-server-1

# 测试从转发服务器是否仍能提供服务
docker exec auto-dns-client dig @10.0.0.16 www.magedu.com

# 停止主权威服务器
docker compose stop dns-server-2

# 测试从权威服务器是否仍能提供服务
docker exec auto-dns-client dig @10.0.0.17 www.magedu.com

# 恢复服务
docker compose start dns-server-1 dns-server-2
```

### 测试 Web 访问
```bash
# 从客户端访问
docker exec auto-dns-client curl http://www.magedu.com
docker exec auto-dns-client curl http://10.0.0.14

# 测试连通性
docker exec auto-dns-client ping -c 3 www.magedu.com
```

## 从宿主机测试
```bash
# 查看自动测试结果
docker logs auto-dns-client

# DNS 解析测试
docker exec auto-dns-client dig @10.0.0.13 www.magedu.com
docker exec auto-dns-client nslookup www.magedu.com

# 验证转发
docker exec auto-dns-client dig @10.0.0.13 www.baidu.com

# Web 访问测试
docker exec auto-dns-client curl http://www.magedu.com

# 验证主从同步
docker exec auto-dns-server-2-slave ls -l /var/named/slaves/
```

## 服务管理

### 查看日志
```bash
# 查看所有服务日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f dns-server-1
docker compose logs -f dns-server-2-slave
docker compose logs -f client

# 同时查看主从服务器日志
docker compose logs -f dns-server-2 dns-server-2-slave
```

### 重启服务
```bash
# 重启所有服务
docker compose restart

# 重启特定服务
docker compose restart dns-server-1
docker compose restart dns-server-2-slave

# 重启所有 DNS 服务器
docker compose restart dns-server-1 dns-server-1-slave dns-server-2 dns-server-2-slave
```

### 停止服务
```bash
# 停止所有服务
docker compose down

# 停止特定服务
docker compose stop dns-server-1
```

### 完全清理
```bash
# 清理所有容器、网络和卷
docker compose down --volumes

# 清理并删除镜像
docker compose down --volumes --rmi all
```

## 故障排除

### 常见问题

#### 1. 服务启动失败
```bash
# 检查服务状态
docker compose ps -a

# 查看错误日志
docker compose logs dns-server-1
docker compose logs dns-server-2-slave

# 检查配置语法
docker exec auto-dns-server-1 named-checkconf
docker exec auto-dns-server-2 named-checkconf
docker exec auto-dns-server-2-slave named-checkconf
```

#### 2. DNS 解析失败
```bash
# 检查 DNS 服务状态
docker exec auto-dns-server-1 rndc status
docker exec auto-dns-server-2 rndc status

# 检查转发配置
docker exec auto-dns-server-1 grep forwarders /etc/named.conf

# 测试 DNS 连通性
docker exec auto-dns-client ping -c 2 10.0.0.13
docker exec auto-dns-client ping -c 2 10.0.0.15
```

#### 3. 主从同步问题
```bash
# 检查从服务器区域文件
docker exec auto-dns-server-2-slave ls -l /var/named/slaves/

# 查看区域状态
docker exec auto-dns-server-2 rndc zonestatus magedu.com
docker exec auto-dns-server-2-slave rndc zonestatus magedu.com

# 手动触发区域传输
docker exec auto-dns-server-2-slave rndc retransfer magedu.com

# 检查主服务器配置
docker exec auto-dns-server-2 grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones

# 检查网络连通性
docker exec auto-dns-server-2-slave ping -c 2 10.0.0.15
```

#### 4. 网络连通性问题
```bash
# 检查网络
docker network ls
docker network inspect 10auto-global-forward_dns-net

# 测试连通性
docker exec auto-dns-client ping -c 2 10.0.0.13
docker exec auto-dns-client ping -c 2 10.0.0.15
docker exec auto-dns-client ping -c 2 10.0.0.16
docker exec auto-dns-client ping -c 2 10.0.0.17
```

#### 5. Web 访问问题
```bash
# 检查 Web 服务器
docker compose logs web-server

# 测试 Web 服务器
docker exec auto-dns-client curl http://10.0.0.14
docker exec auto-web-server wget --spider http://localhost
```

## 配置说明

### 转发配置
- **DNS Server 1 (主)**：转发所有查询到 10.0.0.15 (DNS Server 2)
- **DNS Server 1 Slave (从)**：配置与主服务器相同的转发规则
- 转发策略：`forward first`（优先转发，失败则自行递归）

### 主从配置
- **主服务器**：`type master`，配置 `allow-transfer` 和 `also-notify`
- **从服务器**：`type slave`，配置 `masters` 指向主服务器
- 自动同步机制：NOTIFY + AXFR

### 区域管理
- **magedu.com** 由 DNS Server 2 主服务器管理
- 从服务器自动同步到 `/var/named/slaves/magedu.com.zone`
- 包含双 NS 记录（主和从）

## 与手动版本的区别

| 特性 | 09.manual-global-forward | 10.auto-global-forward |
|------|-------------------------|------------------------|
| 配置方式 | 手动进入容器配置 | 预配置文件自动挂载 |
| 主从同步 | 手动配置 | 自动同步 |
| 启动流程 | 多步骤手动操作 | 一键启动 |
| 测试验证 | 手动执行测试命令 | 自动测试并输出结果 |
| 健康检查 | 无 | 内置健康检查 |
| 依赖管理 | 无 | 自动依赖管理 |
| 数据持久化 | 容器重启数据丢失 | Volume 持久化从服务器数据 |
| 适用场景 | 学习 DNS 配置原理 | 快速部署演示、生产测试 |

## 架构优势

1. **高可用性**
   - 主从双活架构
   - 任一服务器故障不影响服务
   - 自动故障转移

2. **负载均衡**
   - 客户端可配置多个 DNS 服务器
   - 分散查询压力

3. **数据一致性**
   - 自动主从同步
   - 序列号管理
   - NOTIFY 机制确保及时更新

4. **性能优化**
   - 全局转发减少递归查询
   - DNS 缓存提升响应速度
   - 就近访问从服务器

## 注意事项

1. **配置持久性**
   - 主服务器配置文件以只读方式挂载
   - 从服务器区域文件使用 Docker volume 持久化
   - 修改配置需要重启容器

2. **序列号管理**
   - 修改区域文件时必须递增序列号
   - 建议使用 YYYYMMDDNN 格式（如 2024010601）

3. **安全性**
   - 生产环境应使用 TSIG 密钥保护区域传输
   - 限制 `allow-transfer` 和 `allow-query` 范围
   - 启用 DNSSEC 验证

4. **资源需求**
   - 4 个 DNS 服务器 + 1 个 Web 服务器 + 1 个客户端
   - 建议至少 2GB 内存
   - 从服务器需要额外磁盘空间存储区域文件

## 扩展建议

1. **添加更多域名**
   - 在主服务器添加新的区域配置
   - 在从服务器添加对应的 slave 配置

2. **启用日志查询**
   - 已配置查询日志到 `/var/log/named/query.log`
   - 可通过 volume 挂载持久化日志

3. **监控和告警**
   - 集成 Prometheus + Grafana 监控
   - 配置区域同步失败告警

4. **备份策略**
   - 定期备份主服务器区域文件
   - 备份 named.conf 配置文件
   - 测试从备份恢复的流程
