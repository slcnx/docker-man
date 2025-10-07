# NTP 服务命令分类总结

## **软件包管理**
```bash
yum repolist                      # 列出仓库
yum install chrony                # 安装 NTP 服务（Rocky Linux 9 使用 chrony）
yum install ntpdate               # 安装 ntpdate 工具（可选）
yum install net-tools             # 安装网络工具
yum install psmisc                # 安装进程工具
yum install procps-ng             # 安装 ps 命令
yum install vim                   # 安装 vim 编辑器
yum install man                   # 安装手册页
yum install iproute               # 安装 ip 命令
yum install tcpdump               # 安装抓包工具
rpm -ql chrony                    # 列出 chrony 包的文件
```

## **Chrony 服务管理**
```bash
systemctl start chronyd           # 启动 chronyd 服务
systemctl stop chronyd            # 停止 chronyd 服务
systemctl restart chronyd         # 重启 chronyd 服务
systemctl status chronyd          # 查看 chronyd 服务状态
systemctl enable chronyd          # 设置开机自启
systemctl disable chronyd         # 禁用开机自启
systemctl cat chronyd             # 查看服务单元文件

# 容器中前台运行
/usr/sbin/chronyd -d              # 调试模式运行
/usr/sbin/chronyd -d -x           # 不调整时钟，仅测试
```

## **Chrony 客户端命令 (chronyc)**

### **查看时间源状态**
```bash
chronyc sources                   # 显示当前时间源
chronyc sources -v                # 详细显示时间源信息
chronyc sourcestats               # 显示时间源统计
chronyc sourcestats -v            # 详细时间源统计
```

### **查看同步状态**
```bash
chronyc tracking                  # 显示系统时钟性能
chronyc activity                  # 显示在线/离线源数量
chronyc ntpdata                   # 显示 NTP 测量数据
```

### **服务器端命令**
```bash
chronyc clients                   # 显示已连接的客户端
chronyc serverstats               # 显示服务器统计信息
```

### **手动操作**
```bash
chronyc makestep                  # 强制立即同步时间
chronyc burst 4/4                 # 发送 4 个数据包快速同步
chronyc add server <hostname>     # 添加时间源
chronyc delete <hostname>         # 删除时间源
chronyc offline                   # 所有源设为离线
chronyc online                    # 所有源设为在线
chronyc reload sources            # 重新加载时间源配置
```

### **查看配置**
```bash
chronyc dump                      # 转储内部变量
chronyc rtcdata                   # 显示 RTC 信息
chronyc smoothing                 # 显示时间平滑状态
```

### **交互模式**
```bash
chronyc                           # 进入交互模式
# 在交互模式下可以输入上述所有命令
help                              # 显示帮助
quit                              # 退出交互模式
```

## **时间和日期管理**
```bash
date                              # 显示当前日期和时间
date -s "2025-10-07 10:00:00"     # 手动设置时间
timedatectl                       # 显示时间和日期设置
timedatectl status                # 显示详细状态
timedatectl set-time "2025-10-07 10:00:00"  # 设置时间
timedatectl set-timezone Asia/Shanghai       # 设置时区
timedatectl list-timezones        # 列出所有时区
hwclock                           # 显示硬件时钟
hwclock -w                        # 将系统时间写入硬件时钟
hwclock -s                        # 从硬件时钟读取时间到系统
```

## **配置文件**
```bash
cat /etc/chrony.conf              # 查看 chrony 主配置文件
vim /etc/chrony.conf              # 编辑 chrony 配置文件
cat /etc/chrony.keys              # 查看认证密钥文件
man chrony.conf                   # 查看配置文件手册
```

### **重要配置项说明**
```bash
# 时间源配置
server <hostname> iburst          # 添加 NTP 服务器
pool <hostname> iburst            # 使用服务器池

# 访问控制
allow [<subnet>]                  # 允许客户端访问
deny [<subnet>]                   # 拒绝客户端访问

# 本地时钟
local stratum <N>                 # 使用本地时钟作为源

# 时间调整
makestep <threshold> <limit>      # 允许大步长调整
maxupdateskew <value>             # 最大时钟偏差

# 日志
log measurements statistics tracking  # 启用日志
logdir /var/log/chrony            # 日志目录

# 其他
driftfile /var/lib/chrony/drift   # 漂移文件
rtcsync                           # 启用 RTC 同步
```

## **网络测试**
```bash
# 检查 NTP 端口
ss -ulnp | grep 123               # 查看 UDP 123 端口
netstat -ulnp | grep 123          # 传统方法查看端口
lsof -i :123                      # 查看占用 123 端口的进程

# 测试连通性
ping <ntp-server>                 # Ping NTP 服务器
nc -vuz <ntp-server> 123          # 测试 UDP 123 端口
tcpdump -i any port 123           # 抓取 NTP 数据包
```

## **使用 ntpdate (传统工具)**
```bash
ntpdate <ntp-server>              # 同步时间
ntpdate -q <ntp-server>           # 查询时间但不设置
ntpdate -d <ntp-server>           # 调试模式
ntpdate -u <ntp-server>           # 使用非特权端口
```

## **日志和调试**
```bash
# 查看 chrony 日志
journalctl -u chronyd             # 查看服务日志
journalctl -u chronyd -f          # 实时跟踪日志
journalctl -u chronyd --since "1 hour ago"  # 查看最近 1 小时的日志

# chrony 专用日志
cat /var/log/chrony/measurements.log  # 测量日志
cat /var/log/chrony/statistics.log    # 统计日志
cat /var/log/chrony/tracking.log      # 跟踪日志

# 查看系统时钟信息
cat /proc/driver/rtc              # RTC 驱动信息
adjtimex                          # 显示时钟调整参数
```

## **进程管理**
```bash
ps aux | grep chronyd             # 查找 chronyd 进程
pgrep chronyd                     # 获取 chronyd 进程 ID
pkill chronyd                     # 终止 chronyd 进程
killall chronyd                   # 终止所有 chronyd 进程
```

## **性能和监控**
```bash
# 监控时间偏差
watch -n 1 chronyc tracking       # 每秒更新跟踪信息
watch -n 5 chronyc sources        # 每 5 秒更新源状态

# 查看统计信息
chronyc serverstats               # 服务器统计
chronyc clients                   # 客户端连接统计
```

## **故障排查**
```bash
# 检查配置文件语法
chronyd -q 'server pool.ntp.org iburst'  # 测试配置

# 详细调试
chronyd -d -d                     # 双倍详细调试模式
chronyd -d -x -f /etc/chrony.conf # 指定配置文件调试

# 检查防火墙
firewall-cmd --list-all           # 查看防火墙规则
firewall-cmd --add-service=ntp --permanent  # 添加 NTP 服务
firewall-cmd --reload             # 重载防火墙

# 检查 SELinux
getenforce                        # 查看 SELinux 状态
sestatus                          # 详细 SELinux 状态
ausearch -m avc -ts recent        # 查看最近的 SELinux 拒绝
```

## **容器环境相关**
```bash
# Docker 容器中需要的权限
--cap-add=SYS_TIME                # 允许修改系统时间
--cap-add=SYS_NICE                # 允许提高进程优先级

# 容器中的时间同步
docker exec <container> chronyc sources      # 查看容器中的时间源
docker exec <container> date                 # 查看容器时间
docker exec <container> timedatectl status   # 查看容器时间设置
```

## **常用 NTP 服务器**
```bash
# 中国公共 NTP 服务器
ntp.aliyun.com                    # 阿里云
ntp1.aliyun.com
time1.cloud.tencent.com           # 腾讯云
time2.cloud.tencent.com
ntp.ntsc.ac.cn                    # 国家授时中心

# 国际公共 NTP 服务器
pool.ntp.org                      # NTP Pool Project
time.google.com                   # Google
time.cloudflare.com               # Cloudflare
time.apple.com                    # Apple
time.windows.com                  # Microsoft

# 地区池
cn.pool.ntp.org                   # 中国
asia.pool.ntp.org                 # 亚洲
```

## **时区管理**
```bash
# 查看和设置时区
timedatectl list-timezones | grep Shanghai  # 查找时区
timedatectl set-timezone Asia/Shanghai      # 设置为上海时区
timedatectl set-timezone UTC                # 设置为 UTC
ls -l /etc/localtime              # 查看当前时区链接
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime  # 手动设置时区
```

## **其他命令**
```bash
history -w                        # 保存命令历史
man chrony                        # 查看 chrony 手册
man chronyc                       # 查看 chronyc 手册
man chrony.conf                   # 查看配置文件手册
```

## **快速检查清单**
```bash
# 服务器端
systemctl status chronyd          # 1. 检查服务状态
ss -ulnp | grep 123              # 2. 检查端口监听
chronyc sources                   # 3. 检查时间源
chronyc tracking                  # 4. 检查同步状态
chronyc clients                   # 5. 检查客户端连接

# 客户端
systemctl status chronyd          # 1. 检查服务状态
chronyc sources                   # 2. 检查配置的服务器
chronyc tracking                  # 3. 检查同步状态
date                              # 4. 检查当前时间
timedatectl                       # 5. 检查时间设置
```
