# DNS 主从架构 - 自动化部署

## 项目简介

本项目实现了基于 Docker Compose 的 DNS 主从架构自动化部署，所有配置文件已预先准备好，一键启动即可完成部署。

## 架构说明

```
10.0.0.0/24 网络拓扑
├── 10.0.0.1   - 网关
├── 10.0.0.12  - DNS 客户端 (client)
├── 10.0.0.13  - 主 DNS 服务器 (dns-master)
├── 10.0.0.14  - Web 服务器 (www.magedu.com)
└── 10.0.0.15  - 从 DNS 服务器 (dns-slave)
```

## 快速启动

```bash
# 1. 启动所有服务
docker compose up -d

# 2. 查看服务状态
docker compose ps

# 3. 查看客户端测试日志
docker compose logs client
```

## 目录结构

```
04.auto-master-slave-dns/
├── master-configs/              # 主DNS配置文件
│   ├── named.conf              # 主配置文件
│   ├── named.rfc1912.zones     # 区域配置文件
│   └── named.magedu.com        # 区域数据文件
├── slave-configs/               # 从DNS配置文件
│   ├── named.conf              # 主配置文件
│   └── named.rfc1912.zones     # 区域配置文件
├── html/                        # Web服务器页面
│   └── index.html
├── compose.yml                  # Docker Compose配置
└── README.md                    # 本文件
```

## 功能特性

### ✅ 主从自动同步
- 主DNS服务器配置了 `allow-transfer` 和 `notify yes`
- 从DNS服务器自动从主服务器同步区域文件
- 修改主DNS后自动通知从DNS更新

### ✅ IPv6过滤配置
- 配置了 `filter-aaaa-on-v4 yes` 过滤IPv6 AAAA记录查询
- 配置了 `server ::/0 { bogus yes; }` 禁用IPv6服务器
- 避免 "network unreachable" 警告信息

### ✅ 高可用性
- 双DNS服务器提供冗余备份
- 客户端配置了两个DNS服务器（主、从）
- 任一DNS故障不影响解析服务

### ✅ 健康检查
- 所有服务都配置了健康检查
- 自动监控DNS和Web服务状态
- 依赖关系确保启动顺序正确

## 验证测试

### 查看主DNS服务状态
```bash
docker compose exec dns-master rndc status
docker compose exec dns-master ss -tunlp | grep 53
```

### 查看从DNS服务状态和同步文件
```bash
docker compose exec dns-slave rndc status
docker compose exec dns-slave ls -l /var/named/slaves/
docker compose exec dns-slave cat /var/named/slaves/named.magedu.com
```

### 测试DNS解析
```bash
# 进入客户端
docker compose exec client bash

# 测试主DNS
nslookup www.magedu.com 10.0.0.13
dig @10.0.0.13 www.magedu.com

# 测试从DNS
nslookup www.magedu.com 10.0.0.15
dig @10.0.0.15 www.magedu.com

# 测试NS记录
dig @10.0.0.13 magedu.com NS

# 测试SOA记录
dig @10.0.0.13 magedu.com SOA
```

### 测试Web访问
```bash
docker compose exec client curl http://www.magedu.com
```

## 主从同步测试

### 修改主DNS区域文件
```bash
# 1. 进入主DNS容器
docker compose exec dns-master bash

# 2. 修改区域文件（需要先复制出来修改权限）
cp /var/named/named.magedu.com /tmp/
vim /tmp/named.magedu.com
# 修改序列号: 2024100401 -> 2024100402
# 添加新记录: test IN A 10.0.0.100

# 3. 复制回去并设置权限
cp /tmp/named.magedu.com /var/named/
chown named.named /var/named/named.magedu.com

# 4. 重新加载配置
rndc reload
```

### 验证从DNS同步
```bash
# 1. 查看从DNS上的文件（应该自动更新）
docker compose exec dns-slave cat /var/named/slaves/named.magedu.com

# 2. 测试新记录
docker compose exec client dig @10.0.0.13 test.magedu.com
docker compose exec client dig @10.0.0.15 test.magedu.com
```

### 强制区域传输
```bash
docker compose exec dns-slave rndc retransfer magedu.com
```

## 区域传输测试

```bash
# 从客户端测试区域传输
docker compose exec client bash

# 测试主DNS的区域传输（应该成功，因为允许10.0.0.15传输）
dig @10.0.0.13 magedu.com AXFR

# 注意：客户端IP是10.0.0.12，不在允许列表中，会被拒绝
```

## 故障排查

### 查看服务日志
```bash
docker compose logs dns-master
docker compose logs dns-slave
docker compose logs web-server
docker compose logs client
```

### 检查网络连通性
```bash
docker compose exec client ping 10.0.0.13
docker compose exec client ping 10.0.0.15
docker compose exec client ping 10.0.0.14
```

### 检查DNS配置
```bash
docker compose exec dns-master named-checkconf
docker compose exec dns-slave named-checkconf
```

### 检查区域文件
```bash
docker compose exec dns-master named-checkzone magedu.com /var/named/named.magedu.com
```

### 重启服务
```bash
# 重启单个服务
docker compose restart dns-master
docker compose restart dns-slave

# 重启所有服务
docker compose restart
```

## 服务管理

```bash
# 启动服务
docker compose up -d

# 停止服务
docker compose down

# 查看实时日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f dns-master

# 完全清理
docker compose down --volumes --rmi all
```

## 配置说明

### 主DNS配置要点
- `allow-transfer { 10.0.0.15; }` - 仅允许从DNS传输
- `notify yes` - 启用区域变更通知
- `filter-aaaa-on-v4 yes` - 过滤IPv6查询
- `type master` - 主DNS类型

### 从DNS配置要点
- `type slave` - 从DNS类型
- `masters { 10.0.0.13; }` - 指定主DNS
- `file "slaves/named.magedu.com"` - 同步文件存放位置
- 自动创建 `/var/named/slaves/` 目录

### 重要提示
1. 每次修改区域文件必须增加序列号
2. 序列号格式建议: YYYYMMDDNN (年月日+序号)
3. 从DNS的区域文件自动生成，无需手动创建
4. 从DNS的 slaves 目录必须有写权限
5. 修改主DNS后执行 `rndc reload` 会自动通知从DNS

## 技术栈

- **DNS服务**: BIND 9
- **Web服务**: Nginx Alpine
- **容器编排**: Docker Compose 3.8
- **基础镜像**: Rocky Linux 9.3
- **网络**: Bridge (10.0.0.0/24)

## 学习资源

- BIND 官方文档: https://www.isc.org/bind/
- DNS RFC 1912: https://tools.ietf.org/html/rfc1912
- Docker Compose 文档: https://docs.docker.com/compose/
