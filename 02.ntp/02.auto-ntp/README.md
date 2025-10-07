# NTP 服务 - 自动化配置

## 概述

此示例展示了如何使用 Docker Compose 自动部署和配置 NTP 服务，无需手动配置。

## 架构

```
网络拓扑：
├── 10.0.0.1     - 网关
├── 10.0.0.123   - NTP 服务器 (auto-ntp-server)
└── 10.0.0.124   - NTP 客户端 (auto-ntp-client)

组件：
- NTP 服务器：预配置的 chrony 服务器，同步到公共 NTP 服务器
- NTP 客户端：自动从 NTP 服务器同步时间并执行测试
```

## 配置文件说明

### `configs/chrony-server.conf`
NTP 服务器配置，包含：
- 上游 NTP 服务器（阿里云、腾讯云）
- 允许本地网络 (10.0.0.0/24) 访问
- 本地时钟作为备用时间源（Stratum 10）
- 日志记录

### `configs/chrony-client.conf`
NTP 客户端配置，包含：
- 指定 NTP 服务器 (10.0.0.123)
- 自动时间同步设置
- 日志记录

## 快速启动

```bash
# 1. 启动所有服务
docker compose up -d

# 2. 查看服务状态
docker compose ps

# 3. 查看客户端测试输出
docker compose logs -f client
```

## 验证 NTP 服务

### 查看服务器状态
```bash
# 查看 NTP 服务器的时间源
docker compose exec ntp-server chronyc sources -v

# 查看服务器同步状态
docker compose exec ntp-server chronyc tracking

# 查看已连接的客户端
docker compose exec ntp-server chronyc clients
```

### 查看客户端状态
```bash
# 查看客户端的时间源（应显示 10.0.0.123）
docker compose exec client chronyc sources -v

# 查看客户端同步状态
docker compose exec client chronyc tracking

# 查看客户端当前时间
docker compose exec client date
```

## 测试时间同步

```bash
# 1. 比较服务器和客户端的时间
echo "=== NTP Server Time ===" && docker compose exec ntp-server date
echo "=== Client Time ===" && docker compose exec client date

# 2. 查看时间偏差统计
docker compose exec client chronyc sourcestats -v

# 3. 查看 NTP 数据包信息
docker compose exec client chronyc ntpdata
```

## 常用操作

### 强制同步时间
```bash
# 在客户端强制立即同步
docker compose exec client chronyc makestep
```

### 重启服务
```bash
# 重启 NTP 服务器
docker compose restart ntp-server

# 重启客户端
docker compose restart client
```

### 查看日志
```bash
# 查看服务器日志
docker compose logs ntp-server

# 查看客户端日志
docker compose logs client
```

## 清理环境

```bash
# 停止并删除所有容器
docker compose down

# 删除所有资源（包括网络）
docker compose down --volumes
```

## 配置说明

### 关键配置项

**服务器端 (`chrony-server.conf`)**：
- `server <hostname> iburst`: 指定上游 NTP 服务器
- `allow 10.0.0.0/24`: 允许本地网络访问
- `local stratum 10`: 使用本地时钟作为备用源

**客户端 (`chrony-client.conf`)**：
- `server 10.0.0.123 iburst`: 指定 NTP 服务器
- `makestep 1.0 3`: 允许大幅度时间调整（前 3 次更新）

### Docker 配置

**必需的 Linux 能力 (Capabilities)**：
- `SYS_TIME`: 允许修改系统时间
- `SYS_NICE`: 允许提高进程优先级

**健康检查**：
- 服务器每 30 秒检查一次同步状态
- 客户端依赖服务器健康才启动

## 故障排查

### 查看 chrony 守护进程状态
```bash
docker compose exec ntp-server ps aux | grep chronyd
docker compose exec client ps aux | grep chronyd
```

### 检查网络连通性
```bash
# 从客户端 ping 服务器
docker compose exec client ping -c 4 10.0.0.123

# 检查 UDP 123 端口
docker compose exec client nc -vuz 10.0.0.123 123
```

### 查看 chrony 日志
```bash
# 服务器日志
docker compose exec ntp-server cat /var/log/chrony/tracking.log
docker compose exec ntp-server cat /var/log/chrony/measurements.log

# 客户端日志
docker compose exec client cat /var/log/chrony/tracking.log
```

## 扩展配置

### 添加更多客户端

在 `compose.yml` 中添加：
```yaml
  client2:
    build:
      context: .
      dockerfile: ../ntp.dockerfile
    container_name: auto-ntp-client2
    hostname: client2
    networks:
      ntp-net:
        ipv4_address: 10.0.0.125
    volumes:
      - ./configs/chrony-client.conf:/etc/chrony.conf:ro
    cap_add:
      - SYS_TIME
    command: tail -f /dev/null
    depends_on:
      ntp-server:
        condition: service_healthy
    restart: unless-stopped
```

### 使用不同的上游 NTP 服务器

编辑 `configs/chrony-server.conf`，修改 server 行：
```
server pool.ntp.org iburst
server time.google.com iburst
server time.cloudflare.com iburst
```

## 技术细节

### Chrony vs NTPd

此示例使用 **Chrony**，相比传统的 NTPd 有以下优势：
- 更快的同步速度
- 更好的间歇性网络连接支持
- 更低的系统资源占用
- 更适合虚拟化环境

### Stratum 层级

- **Stratum 0**: 原子钟、GPS 时钟等参考时钟
- **Stratum 1**: 直接连接到 Stratum 0 的服务器
- **Stratum 2-15**: 从上一级同步的服务器
- **Stratum 16**: 未同步

本示例中：
- NTP 服务器从公共服务器同步（Stratum 2-3）
- 客户端从本地 NTP 服务器同步（Stratum 3-4）

### iburst 参数

`iburst` 选项表示：
- 启动时快速发送 8 个数据包（而不是等待正常间隔）
- 加快初始同步速度
- 提高可靠性

## 参考资料

- [Chrony 官方文档](https://chrony.tuxfamily.org/documentation.html)
- [Red Hat 时间同步指南](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_basic_system_settings/using-chrony-to-configure-ntp)
- [NTP 协议 RFC 5905](https://tools.ietf.org/html/rfc5905)
