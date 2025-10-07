# NTP 高可用服务 - 手工配置

## **架构概览**
```
高可用 NTP 架构：
├── 10.0.0.1     - 网关
├── 10.0.0.121   - NTP 主服务器 (ntp-server-1) - Stratum 2
├── 10.0.0.122   - NTP 备服务器 (ntp-server-2) - Stratum 2
├── 10.0.0.123   - NTP 备服务器 (ntp-server-3) - Stratum 2
└── 10.0.0.124   - NTP 客户端 (client)

NTP 高可用特性：
1. 三台 NTP 服务器对等配置（peer）
2. 服务器之间相互同步，保持时间一致性
3. 所有服务器从公共 NTP 服务器同步（上游时间源）
4. 客户端配置多个 NTP 服务器，自动选择最佳时间源
5. 单台服务器故障不影响客户端时间同步

服务器角色：
- 所有服务器：对等节点（peer），同时也是服务端
- 服务器间：通过 peer 相互同步
- 客户端：从多个服务器同步，chrony 自动选择最优源
```

## **服务启动**
```bash
# 1. 启动所有服务
docker compose up -d

# 2. 检查服务状态
docker compose ps

# 3. 查看网络配置
docker network inspect 03manual-ntp-ha_ntp-net
```

## **配置 NTP 服务器（高可用）**

### **配置 NTP 服务器 1 (主服务器)**
```bash
# 进入服务器 1 容器
docker compose exec -it ntp-server-1 bash

# 1. 备份配置文件
cp /etc/chrony.conf /etc/chrony.conf.bak

# 2. 编辑配置文件
vim /etc/chrony.conf

# 删除默认的 pool 配置，添加以下内容：

# ========== 上游 NTP 时间源 ==========
# 从公共 NTP 服务器同步时间（作为权威时间源）
server ntp.aliyun.com iburst
server ntp1.aliyun.com iburst
server time1.cloud.tencent.com iburst
server time2.cloud.tencent.com iburst

# ========== 对等服务器配置 ==========
# 与其他 NTP 服务器对等，保持时间一致性
# ntp-server-2
peer 10.0.0.122
# ntp-server-3
peer 10.0.0.123

# ========== 基础配置 ==========
# 记录系统时钟偏移量
driftfile /var/lib/chrony/drift

# 允许系统时钟大幅度调整（启动时）
makestep 1.0 3

# 启用内核同步
rtcsync

# ========== 服务器配置 ==========
# 允许本地网络的客户端同步时间
allow 10.0.0.0/24

# 即使未同步到上游服务器，也允许客户端同步
# 使用本地时钟作为备用源（Stratum 10）
local stratum 10

# ========== 日志配置 ==========
logdir /var/log/chrony
log measurements statistics tracking

# ========== 性能优化 ==========
# 限制客户端访问速率
ratelimit interval 1 burst 16

# 设置最大时钟更新次数
maxupdateskew 100.0

# 3. 重启服务
exit
docker compose restart ntp-server-1
sleep 5

# 4. 验证配置
docker compose exec ntp-server-1 bash

# 查看上游时间源
chronyc sources -v
# 应该看到 4 个公共 NTP 服务器

# 查看对等服务器
chronyc peers
# 应该看到 server-2 和 server-3

# 查看同步状态
chronyc tracking

exit
```

### **配置 NTP 服务器 2 (备服务器)**
```bash
# 进入服务器 2 容器
docker compose exec -it ntp-server-2 bash

# 1. 备份配置文件
cp /etc/chrony.conf /etc/chrony.conf.bak

# 2. 编辑配置文件
vim /etc/chrony.conf

# 配置内容（与服务器 1 类似，但 peer 地址不同）：

# ========== 上游 NTP 时间源 ==========
server ntp.aliyun.com iburst
server ntp1.aliyun.com iburst
server time1.cloud.tencent.com iburst
server time2.cloud.tencent.com iburst

# ========== 对等服务器配置 ==========
# ntp-server-1
peer 10.0.0.121
# ntp-server-3
peer 10.0.0.123

# ========== 基础配置 ==========
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync

# ========== 服务器配置 ==========
allow 10.0.0.0/24
local stratum 10

# ========== 日志配置 ==========
logdir /var/log/chrony
log measurements statistics tracking

# ========== 性能优化 ==========
ratelimit interval 1 burst 16
maxupdateskew 100.0

# 3. 重启服务
exit
docker compose restart ntp-server-2
sleep 5

# 4. 验证配置
docker compose exec ntp-server-2 chronyc sources -v
docker compose exec ntp-server-2 chronyc peers
```

### **配置 NTP 服务器 3 (备服务器)**
```bash
# 进入服务器 3 容器
docker compose exec -it ntp-server-3 bash

# 1. 备份配置文件
cp /etc/chrony.conf /etc/chrony.conf.bak

# 2. 编辑配置文件
vim /etc/chrony.conf

# 配置内容（与服务器 1、2 类似，但 peer 地址不同）：

# ========== 上游 NTP 时间源 ==========
server ntp.aliyun.com iburst
server ntp1.aliyun.com iburst
server time1.cloud.tencent.com iburst
server time2.cloud.tencent.com iburst

# ========== 对等服务器配置 ==========
# ntp-server-1
peer 10.0.0.121
# ntp-server-2
peer 10.0.0.122

# ========== 基础配置 ==========
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync

# ========== 服务器配置 ==========
allow 10.0.0.0/24
local stratum 10

# ========== 日志配置 ==========
logdir /var/log/chrony
log measurements statistics tracking

# ========== 性能优化 ==========
ratelimit interval 1 burst 16
maxupdateskew 100.0

# 3. 重启服务
exit
docker compose restart ntp-server-3
sleep 5

# 4. 验证配置
docker compose exec ntp-server-3 chronyc sources -v
docker compose exec ntp-server-3 chronyc peers
```

## **配置 NTP 客户端（高可用）**

```bash
# 进入客户端容器
docker compose exec -it client bash

# 1. 备份配置文件
cp /etc/chrony.conf /etc/chrony.conf.bak

# 2. 编辑配置文件
vim /etc/chrony.conf

# 删除默认配置，添加以下内容：

# ========== NTP 服务器配置 ==========
# 配置多个 NTP 服务器（高可用）
# chrony 会自动选择最佳时间源
server 10.0.0.121 iburst         # ntp-server-1
server 10.0.0.122 iburst         # ntp-server-2
server 10.0.0.123 iburst         # ntp-server-3

# ========== 基础配置 ==========
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync

# ========== 日志配置 ==========
logdir /var/log/chrony
log measurements statistics tracking

# 3. 重启 chronyd
pkill chronyd
chronyd

# 4. 等待几秒钟，验证同步状态
sleep 10

# 查看所有配置的 NTP 服务器
chronyc sources -v
# 应该看到三台服务器，带 * 的是当前选中的最佳源

# 查看详细同步信息
chronyc tracking

# 查看时间源统计
chronyc sourcestats -v

# 5. 查看当前时间
date
timedatectl

exit
```

## **高可用验证测试**

### **1. 验证服务器对等关系**
```bash
# 在每台服务器上查看对等状态
echo "=== Server 1 Peers ===" && docker compose exec ntp-server-1 chronyc peers
echo "=== Server 2 Peers ===" && docker compose exec ntp-server-2 chronyc peers
echo "=== Server 3 Peers ===" && docker compose exec ntp-server-3 chronyc peers

# 查看服务器间同步状态
docker compose exec ntp-server-1 chronyc sources | grep "^[\^=]"
```

### **2. 验证客户端多源同步**
```bash
# 查看客户端的所有时间源
docker compose exec client chronyc sources -v

# 输出说明：
# M (Mode): ^ = server, = = peer
# S (State): * = 当前同步源, + = 可用源, - = 不可用源, x = 错误源
# 客户端应该显示三个服务器，其中一个带 * 标记

# 查看详细统计
docker compose exec client chronyc sourcestats -v
```

### **3. 故障切换测试**
```bash
# 停止当前同步源（假设是 server-1）
docker compose stop ntp-server-1

# 等待几秒钟，查看客户端是否自动切换
sleep 10
docker compose exec client chronyc sources -v
# 应该看到客户端已切换到 server-2 或 server-3

# 查看切换后的同步状态
docker compose exec client chronyc tracking

# 恢复服务器 1
docker compose start ntp-server-1
```

### **4. 时间一致性测试**
```bash
# 比较所有服务器的时间
echo "=== Server 1 ===" && docker compose exec ntp-server-1 date
echo "=== Server 2 ===" && docker compose exec ntp-server-2 date
echo "=== Server 3 ===" && docker compose exec ntp-server-3 date
echo "=== Client ===" && docker compose exec client date

# 查看服务器间的时间偏差
docker compose exec ntp-server-1 chronyc tracking | grep "System time"
docker compose exec ntp-server-2 chronyc tracking | grep "System time"
docker compose exec ntp-server-3 chronyc tracking | grep "System time"
```

### **5. 查看客户端连接（服务器端）**
```bash
# 在每台服务器上查看连接的客户端
echo "=== Server 1 Clients ===" && docker compose exec ntp-server-1 chronyc clients
echo "=== Server 2 Clients ===" && docker compose exec ntp-server-2 chronyc clients
echo "=== Server 3 Clients ===" && docker compose exec ntp-server-3 chronyc clients
```

## **高可用架构说明**

### **对等配置 (Peer) 的作用**
```
1. 服务器间时间一致性：
   - 三台服务器相互同步，保持时间高度一致
   - 即使一台服务器与上游失联，其他服务器仍可作为时间源

2. 自动故障切换：
   - 客户端配置了三个时间源
   - chrony 自动选择最佳源（延迟最低、准确度最高）
   - 当前源失败时，自动切换到其他源

3. 负载均衡：
   - 多个客户端会分散选择不同的服务器
   - 避免单点压力过大

4. Stratum 层级：
   - 上游公共服务器: Stratum 1-2
   - 本地 NTP 服务器: Stratum 2-3（从上游同步）
   - 客户端: Stratum 3-4（从本地服务器同步）
```

### **源选择算法**
```
chrony 选择最佳时间源的标准：
1. 优先选择 Stratum 层级低的源（更接近权威时间）
2. 选择网络延迟小的源（RTT 低）
3. 选择抖动小的源（稳定性好）
4. 排除偏差过大的源
5. 综合评分后选择最佳源
```

## **监控和维护**

### **实时监控脚本**
```bash
# 创建监控脚本
cat > monitor-ntp.sh << 'EOF'
#!/bin/bash
while true; do
  clear
  echo "========================================="
  echo "NTP 高可用集群监控"
  echo "========================================="
  echo ""

  echo "=== 服务器状态 ==="
  for i in 1 2 3; do
    echo "--- Server $i ---"
    docker compose exec ntp-server-$i chronyc tracking | grep "Reference ID"
    docker compose exec ntp-server-$i chronyc tracking | grep "Stratum"
    docker compose exec ntp-server-$i chronyc tracking | grep "System time"
    echo ""
  done

  echo "=== 客户端状态 ==="
  docker compose exec client chronyc sources
  echo ""

  echo "更新时间: $(date)"
  sleep 5
done
EOF

chmod +x monitor-ntp.sh
./monitor-ntp.sh
```

### **健康检查脚本**
```bash
cat > health-check.sh << 'EOF'
#!/bin/bash
echo "检查 NTP 高可用集群健康状态..."
echo ""

# 检查服务器
for i in 1 2 3; do
  echo "检查 ntp-server-$i..."
  if docker compose exec ntp-server-$i chronyc tracking >/dev/null 2>&1; then
    echo "  ✓ Server $i 运行正常"
  else
    echo "  ✗ Server $i 异常"
  fi
done

# 检查客户端
echo "检查客户端..."
sources=$(docker compose exec client chronyc sources | grep "^\^[\*\+]" | wc -l)
if [ "$sources" -ge 1 ]; then
  echo "  ✓ 客户端至少有 $sources 个可用时间源"
else
  echo "  ✗ 客户端没有可用时间源"
fi
EOF

chmod +x health-check.sh
./health-check.sh
```

## **故障排查**

### **常见问题**

**1. 对等服务器无法连接**
```bash
# 检查网络连通性
docker compose exec ntp-server-1 ping -c 3 10.0.0.122
docker compose exec ntp-server-1 ping -c 3 10.0.0.123

# 检查端口
docker compose exec ntp-server-1 nc -vuz 10.0.0.122 123
```

**2. 客户端不同步**
```bash
# 检查客户端配置
docker compose exec client cat /etc/chrony.conf

# 查看源状态
docker compose exec client chronyc sources -v

# 查看详细调试信息
docker compose exec client chronyc -n sources
```

**3. 服务器时间不一致**
```bash
# 强制所有服务器同步
for i in 1 2 3; do
  docker compose exec ntp-server-$i chronyc makestep
done
```

## **清理环境**

```bash
# 停止并删除所有容器
docker compose down

# 删除所有资源
docker compose down --volumes
```

## **生产环境建议**

1. **服务器数量**：建议至少 3 台，最好是奇数（3、5、7）
2. **地理分布**：服务器分散在不同机房，避免单点故障
3. **上游源选择**：选择稳定可靠的 NTP 服务器，建议使用多个不同供应商
4. **监控告警**：监控 Stratum、时间偏差、客户端连接数
5. **防火墙**：确保 UDP 123 端口开放
6. **日志管理**：定期归档和清理日志文件
7. **定期检查**：定期检查服务器间同步状态和客户端连接
