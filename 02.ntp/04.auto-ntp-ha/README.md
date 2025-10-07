# NTP 高可用服务 - 自动化配置

## 概述

此示例展示了如何使用 Docker Compose 自动部署 NTP 高可用集群，实现时间同步的高可用性和故障自动切换。

## 架构

```
高可用 NTP 集群架构：

┌─────────────────────────────────────────────┐
│         公共 NTP 服务器 (上游)               │
│  ntp.aliyun.com / time.tencent.com 等        │
└─────────────────────────────────────────────┘
          ↓           ↓           ↓
┌─────────────────────────────────────────────┐
│            NTP 服务器集群                    │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐     │
│  │Server 1 │←→│Server 2 │←→│Server 3 │     │
│  │10.0.0.121│ │10.0.0.122│ │10.0.0.123│    │
│  └─────────┘  └─────────┘  └─────────┘     │
│       ↑             ↑             ↑         │
│       └─────────────┴─────────────┘         │
│              对等同步 (peer)                 │
└─────────────────────────────────────────────┘
                    ↓
          ┌─────────────────┐
          │  NTP 客户端      │
          │   10.0.0.124    │
          │ (多源同步+自动切换)│
          └─────────────────┘

特性：
✓ 3 台 NTP 服务器对等配置
✓ 服务器间相互同步，保持时间一致性
✓ 客户端配置多个时间源，自动选择最佳源
✓ 自动故障检测和切换
✓ 负载均衡
```

## 配置文件说明

### 服务器配置
- `configs/chrony-server-1.conf`: Server 1 配置
- `configs/chrony-server-2.conf`: Server 2 配置
- `configs/chrony-server-3.conf`: Server 3 配置

每个服务器配置包含：
- **上游时间源**: 公共 NTP 服务器（阿里云、腾讯云等）
- **对等配置**: peer 配置指向其他两台服务器
- **服务端配置**: 允许客户端访问
- **备用源**: 本地时钟作为 Stratum 10 备用

### 客户端配置
- `configs/chrony-client.conf`: 高可用客户端配置

包含三个 NTP 服务器，chrony 自动选择最佳源。

## 快速启动

```bash
# 1. 启动所有服务
docker compose up -d

# 2. 查看服务状态
docker compose ps

# 3. 查看客户端测试输出
docker compose logs -f client
```

## 验证高可用功能

### 查看集群状态
```bash
# 查看所有服务器的同步状态
for i in 1 2 3; do
  echo "=== Server $i ==="
  docker compose exec ntp-server-$i chronyc tracking | grep -E 'Reference|Stratum|System'
  echo ""
done

# 查看服务器间的对等关系
docker compose exec ntp-server-1 chronyc peers
```

### 查看客户端时间源
```bash
# 查看客户端的所有时间源
docker compose exec client chronyc sources -v

# 输出说明：
# M: 模式 (^ = server, = = peer)
# S: 状态
#    * = 当前同步源（最佳源）
#    + = 可用备用源
#    - = 不可用源
#    x = 错误源
# 应该看到三个服务器，其中一个标记为 *

# 查看同步详情
docker compose exec client chronyc tracking
```

## 高可用测试

### 测试 1: 故障切换
```bash
# 1. 查看当前同步源
docker compose exec client chronyc sources
# 记下当前使用的服务器（标记为 *）

# 2. 停止当前同步源（假设是 server-1）
docker compose stop ntp-server-1

# 3. 等待 10-20 秒，观察自动切换
sleep 15
docker compose exec client chronyc sources
# 应该看到客户端已切换到另一台服务器

# 4. 验证时间仍在同步
docker compose exec client chronyc tracking

# 5. 恢复服务器
docker compose start ntp-server-1
```

### 测试 2: 多服务器故障
```bash
# 停止两台服务器
docker compose stop ntp-server-1 ntp-server-2

# 客户端应该仍能从 server-3 同步
docker compose exec client chronyc sources

# 恢复服务器
docker compose start ntp-server-1 ntp-server-2
```

### 测试 3: 时间一致性
```bash
# 比较所有节点的时间
echo "=== Server 1 ===" && docker compose exec ntp-server-1 date
echo "=== Server 2 ===" && docker compose exec ntp-server-2 date
echo "=== Server 3 ===" && docker compose exec ntp-server-3 date
echo "=== Client ===" && docker compose exec client date

# 查看时间偏差
for i in 1 2 3; do
  echo "=== Server $i System time ==="
  docker compose exec ntp-server-$i chronyc tracking | grep "System time"
done
```

### 测试 4: 负载分布
```bash
# 查看每台服务器的客户端连接
for i in 1 2 3; do
  echo "=== Server $i Clients ==="
  docker compose exec ntp-server-$i chronyc clients
  echo ""
done
```

## 监控脚本

### 实时监控
```bash
# 在宿主机执行
watch -n 2 'docker compose exec client chronyc sources'
```

### 健康检查脚本
```bash
cat > check-ha.sh << 'EOF'
#!/bin/bash
echo "检查 NTP 高可用集群..."
echo ""

# 检查服务器
healthy=0
for i in 1 2 3; do
  if docker compose exec ntp-server-$i chronyc tracking >/dev/null 2>&1; then
    echo "✓ Server $i 健康"
    ((healthy++))
  else
    echo "✗ Server $i 故障"
  fi
done

echo ""
echo "健康服务器: $healthy/3"

# 检查客户端
sources=$(docker compose exec client chronyc sources 2>/dev/null | grep "^\^[\*\+]" | wc -l)
echo "客户端可用源: $sources"

if [ "$sources" -ge 1 ]; then
  echo "✓ 高可用集群正常"
else
  echo "✗ 高可用集群异常"
fi
EOF

chmod +x check-ha.sh
./check-ha.sh
```

## 配置详解

### Peer 对等配置
```
server 配置：单向时间同步（客户端从服务器获取时间）
peer 配置：双向对等同步（服务器之间相互同步）

为什么使用 peer：
1. 保持服务器集群时间高度一致
2. 即使部分服务器失联上游，仍可从对等节点获取时间
3. 提高整体集群的稳定性和可靠性
```

### 时间源选择策略
```
chrony 选择最佳源的标准：
1. Stratum 层级（越小越好）
2. 网络延迟 RTT（越小越好）
3. 抖动 jitter（越小越好）
4. 稳定性（长期观察）

客户端会综合评估所有源，选择得分最高的作为当前同步源。
```

### 故障切换时间
```
典型切换时间：10-30 秒
影响因素：
- poll interval (轮询间隔)
- iburst 参数 (加快初始同步)
- minpoll/maxpoll 设置
```

## 性能优化

### 调整轮询间隔
```bash
# 在配置文件中添加
server 10.0.0.121 iburst minpoll 4 maxpoll 6

# minpoll 4 = 2^4 = 16 秒
# maxpoll 6 = 2^6 = 64 秒
# 更频繁的轮询 = 更快的故障检测
```

### 调整客户端访问限制
```bash
# 限制客户端请求速率，防止 DDoS
ratelimit interval 1 burst 16
```

## 生产环境建议

### 1. 服务器数量
- **最少**: 3 台（推荐）
- **理想**: 5 台或更多
- **原则**: 奇数台，避免脑裂

### 2. 地理分布
- 分散在不同机房/可用区
- 避免单点故障
- 考虑网络延迟

### 3. 上游源选择
- 使用多个独立的上游 NTP 源
- 混合使用不同供应商（阿里云、腾讯云、Google 等）
- 选择地理位置近的服务器

### 4. 监控告警
监控指标：
- 服务器健康状态
- Stratum 层级
- 时间偏差
- 客户端连接数
- 网络延迟和抖动

告警条件：
- 超过 2 台服务器故障
- 时间偏差超过 1 秒
- Stratum 超过 10
- 长时间无法同步

### 5. 安全加固
```bash
# 限制访问来源
allow 10.0.0.0/8
deny all

# 启用认证（可选）
keyfile /etc/chrony.keys
```

### 6. 日志管理
```bash
# 定期清理日志
logdir /var/log/chrony
log measurements statistics tracking

# 配置日志轮转
cat > /etc/logrotate.d/chrony << 'EOF'
/var/log/chrony/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
EOF
```

## 故障排查

### 问题 1: 服务器间无法对等
```bash
# 检查网络
docker compose exec ntp-server-1 ping 10.0.0.122

# 检查防火墙
docker compose exec ntp-server-1 nc -vuz 10.0.0.122 123

# 查看日志
docker compose exec ntp-server-1 cat /var/log/chrony/tracking.log
```

### 问题 2: 客户端不切换
```bash
# 查看源状态
docker compose exec client chronyc sources -v

# 强制重新评估
docker compose exec client chronyc reselect
```

### 问题 3: 时间不一致
```bash
# 强制同步
for i in 1 2 3; do
  docker compose exec ntp-server-$i chronyc makestep
done
```

## 扩展配置

### 添加更多服务器
在 `compose.yml` 中添加新服务器，并更新其他服务器的 peer 配置。

### 添加更多客户端
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
    ntp-server-1:
      condition: service_healthy
    ntp-server-2:
      condition: service_healthy
    ntp-server-3:
      condition: service_healthy
  restart: unless-stopped
```

## 清理环境

```bash
# 停止所有服务
docker compose down

# 删除所有资源
docker compose down --volumes
```

## 参考资料

- [Chrony 官方文档 - Peer 配置](https://chrony.tuxfamily.org/doc/4.0/chrony.conf.html#peer)
- [Red Hat - NTP 高可用](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/9/html/configuring_basic_system_settings/using-chrony-to-configure-ntp)
- [NTP 最佳实践](https://www.ntp.org/documentation/)
