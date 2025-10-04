# DNS 自动化部署

## 概述
这是一个完全自动化的 DNS 服务部署方案，用户只需要执行 `docker compose up -d` 即可完成整个 DNS 环境的部署和测试。

## 目录结构
```
01.auto-dns/
├── compose.yml              # Docker Compose 配置文件
├── start.sh                 # 自动化启动脚本（可选）
├── README.md               # 说明文档
├── configs/                # DNS 配置文件目录
│   ├── named.conf          # BIND 主配置文件
│   ├── named.magedu.com    # magedu.com 区域文件
│   └── named.rfc1912.zones # 区域配置文件
└── html/                   # Web 服务器内容
    └── index.html          # 测试网页
```

## 网络架构
```
10.0.0.0/24 内网
├── 10.0.0.12  - 客户端 (auto-dns-client)
├── 10.0.0.13  - DNS 服务器 (auto-dns-server)
└── 10.0.0.14  - Web 服务器 (auto-web-server)
```

## 快速启动

### 方法一：使用 Docker Compose
```bash
# 进入目录
cd 01.auto-dns

# 启动所有服务
docker compose up -d

# 查看服务状态
docker compose ps
```

 

## 自动化特性

### 1. 配置文件自动挂载
- DNS 配置文件预先准备好，自动挂载到容器
- 无需手动进入容器配置

### 2. 健康检查
- DNS 服务器健康检查：`dig @127.0.0.1 www.magedu.com`
- Web 服务器健康检查：`wget --spider http://localhost`

### 3. 依赖管理
- 客户端等待 DNS 和 Web 服务器健康后才启动
- 确保服务按正确顺序启动

### 4. 自动测试
客户端启动后自动执行测试：
```bash
# 自动安装工具
yum install -y bind-utils curl

# 自动测试 DNS 解析
nslookup www.magedu.com

# 自动测试 Web 访问
curl http://www.magedu.com
```

## 验证测试

### 查看自动测试结果
```bash
docker logs auto-dns-client
```

### 手动测试
```bash
# 进入客户端
docker exec -it auto-dns-client bash

# DNS 解析测试
nslookup www.magedu.com
dig www.magedu.com

# Web 访问测试
curl http://www.magedu.com
curl http://10.0.0.14
```

### 从宿主机测试
```bash
# 通过客户端访问网站
docker exec auto-dns-client curl http://www.magedu.com

# 通过客户端测试 DNS
docker exec auto-dns-client nslookup www.magedu.com
```

## 服务管理

### 查看日志
```bash
# 查看所有服务日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f dns-server
docker compose logs -f web-server
docker compose logs -f client
```

### 重启服务
```bash
# 重启所有服务
docker compose restart

# 重启特定服务
docker compose restart dns-server
```

### 停止服务
```bash
docker compose down
```

### 完全清理
```bash
docker compose down --volumes --rmi all
```

## 故障排除

### 常见问题

1. **服务启动失败**
   ```bash
   # 检查服务状态
   docker compose ps

   # 查看错误日志
   docker compose logs
   ```

2. **DNS 解析失败**
   ```bash
   # 检查 DNS 服务器状态
   docker compose logs dns-server

   # 手动测试 DNS
   docker exec auto-dns-client nslookup www.magedu.com
   ```

3. **网络连通性问题**
   ```bash
   # 检查网络
   docker network ls
   docker network inspect 01-auto-dns_dns-net

   # 测试连通性
   docker exec auto-dns-client ping 10.0.0.13
   docker exec auto-dns-client ping 10.0.0.14
   ```

## 与手动版本的区别

| 特性 | 01.manual-dns | 01.auto-dns |
|------|--------------|-------------|
| 配置方式 | 手动进入容器配置 | 预配置文件自动挂载 |
| 启动流程 | 多步骤手动操作 | 一键启动 |
| 测试验证 | 手动执行测试命令 | 自动测试并输出结果 |
| 健康检查 | 无 | 内置健康检查 |
| 依赖管理 | 无 | 自动依赖管理 |
| 适用场景 | 学习和理解 DNS 配置 | 快速部署和演示 |