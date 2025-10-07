# NTP 服务 - 手工配置

## **架构概览**
```
网络架构：
├── 10.0.0.1     - 网关
├── 10.0.0.123   - NTP 服务器 (ntp-server)
└── 10.0.0.124   - NTP 客户端 (client)

NTP 服务：
- 服务器：使用 chrony 提供 NTP 时间同步服务
- 客户端：从 NTP 服务器同步时间
```

## **服务启动**
```bash
# 1. 启动所有服务
docker compose up -d

# 2. 检查服务状态
docker compose ps

# 3. 查看网络配置
docker network inspect 01manual-ntp_ntp-net
```

## **配置 NTP 服务器**

### **进入 NTP 服务器容器**
```bash
docker compose exec -it ntp-server bash
```

### **配置 chrony 服务器**
```bash
# 1. 备份原配置文件
cp /etc/chrony.conf /etc/chrony.conf.bak

# 2. 编辑 chrony 配置文件
vim /etc/chrony.conf

# 主要配置项：
# 删除或注释掉默认的 pool 配置
# pool 2.rocky.pool.ntp.org iburst

# 添加上游 NTP 服务器（中国 NTP 服务器池）
server ntp.aliyun.com iburst
server ntp1.aliyun.com iburst
server time1.cloud.tencent.com iburst
server time2.cloud.tencent.com iburst

# 允许本地网络的客户端同步时间
allow 10.0.0.0/24

# 即使未同步到时间源，也允许客户端同步（本地时钟作为源）
local stratum 10

# 记录日志
logdir /var/log/chrony
log measurements statistics tracking

# 3. 检查配置文件语法
chronyd -q 'server ntp.aliyun.com iburst'

# 4. 重启 chronyd 服务
# 由于容器中 chronyd 运行在前台，需要重启容器
exit
```

```bash
# 重启 NTP 服务器容器
docker compose restart ntp-server

# 等待几秒钟后，再次进入容器
docker compose exec -it ntp-server bash

# 5. 验证 NTP 服务器状态
chronyc sources -v
# 输出示例：
# MS Name/IP address         Stratum Poll Reach LastRx Last sample
# ^* ntp.aliyun.com                2   6   377    32   +123us[ +150us] +/-   15ms

chronyc tracking
# 输出示例：
# Reference ID    : C0A80001 (ntp.aliyun.com)
# Stratum         : 3
# Ref time (UTC)  : Mon Oct 07 10:00:00 2025
# System time     : 0.000123000 seconds fast of NTP time

chronyc clients
# 显示已连接的客户端

# 6. 查看时间同步状态
timedatectl status

# 7. 退出容器
exit
```

## **配置 NTP 客户端**

### **进入客户端容器**
```bash
docker compose exec -it client bash
```

### **配置客户端同步**
```bash
# 1. 备份原配置文件
cp /etc/chrony.conf /etc/chrony.conf.bak

# 2. 编辑 chrony 配置文件
vim /etc/chrony.conf

# 删除或注释掉默认的 pool 配置
# pool 2.rocky.pool.ntp.org iburst

# 指定 NTP 服务器
server 10.0.0.123 iburst

# 3. 重启 chronyd
# 停止后台可能运行的 chronyd
pkill chronyd

# 启动 chronyd
chronyd

# 4. 等待几秒钟，然后验证同步状态
chronyc sources -v
# 应该看到 NTP 服务器 10.0.0.123

chronyc tracking
# 查看详细同步信息

# 5. 强制立即同步（可选）
chronyc makestep
# 或
chronyc -a 'burst 4/4'

# 6. 验证时间
date
timedatectl

# 7. 退出容器
exit
```

## **时间同步验证**

```bash
# 1. 在服务器上查看当前时间
docker compose exec ntp-server date

# 2. 在客户端查看当前时间
docker compose exec client date

# 3. 查看客户端的同步源
docker compose exec client chronyc sources -v

# 4. 查看客户端的跟踪信息
docker compose exec client chronyc tracking

# 5. 在服务器上查看连接的客户端
docker compose exec ntp-server chronyc clients

# 6. 测试客户端与服务器的时间偏差
docker compose exec client chronyc sourcestats -v
```

## **常用 chrony 命令**

```bash
# 查看时间源
chronyc sources
chronyc sources -v        # 详细输出

# 查看同步状态
chronyc tracking

# 查看客户端连接（服务器端）
chronyc clients

# 查看时间源统计
chronyc sourcestats

# 强制立即同步
chronyc makestep

# 手动添加时间源
chronyc add server ntp.aliyun.com

# 删除时间源
chronyc delete ntp.aliyun.com

# 查看活动信息
chronyc activity

# 显示 NTP 数据
chronyc ntpdata
```

## **故障排查**

```bash
# 1. 检查 chronyd 进程
ps aux | grep chronyd

# 2. 检查端口监听
ss -ulnp | grep 123

# 3. 测试 NTP 端口连通性（从客户端）
nc -vuz 10.0.0.123 123

# 4. 查看日志
cat /var/log/chrony/measurements.log
cat /var/log/chrony/statistics.log
cat /var/log/chrony/tracking.log

# 5. 使用 ntpdate 测试（如果安装了）
yum install -y ntpdate
ntpdate -q 10.0.0.123

# 6. 使用 chronyc 查看详细调试信息
chronyc -n sources
chronyc tracking
chronyc sourcestats
```

## **清理环境**

```bash
# 停止并删除所有容器
docker compose down

# 删除网络
docker compose down --volumes
```

## **注意事项**

1. **CAP_SYS_TIME 权限**：容器需要 `SYS_TIME` 和 `SYS_NICE` 权限才能修改系统时间
2. **时间同步延迟**：chrony 默认会逐步调整时间，避免时间跳变
3. **防火墙**：确保 UDP 123 端口开放
4. **时区设置**：可以通过 `timedatectl set-timezone Asia/Shanghai` 设置时区
5. **Stratum 层级**：Stratum 值越小，时间源越准确（0=原子钟，1=直连原子钟的服务器）
