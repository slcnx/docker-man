# rsyslog 集中式日志服务器（手工配置）

## 📚 第一部分：架构说明

### 1.1 架构图

```
┌─────────────┐       ┌─────────────┐
│  Client-1   │       │  Client-2   │
│ 172.20.0.11  │       │ 172.20.0.12  │
└──────┬──────┘       └──────┬──────┘
       │                     │
       │ TCP/UDP 514         │
       │                     │
       └──────────┬──────────┘
                  ↓
          ┌───────────────┐
          │  Log-server   │
          │  172.20.0.13   │
          │   (rsyslog)   │
          └───────┬───────┘
                  │
                  │ ommysql
                  ↓
          ┌───────────────┐
          │ MySQL-server  │
          │  172.20.0.16   │
          │  (Database)   │
          └───────────────┘
```

### 1.2 组件说明

| 组件 | IP | 角色 | 说明 |
|------|----|----|------|
| **client-1** | 172.20.0.11 | 日志客户端 | 生成日志，通过 TCP/UDP 转发到 log-server |
| **client-2** | 172.20.0.12 | 日志客户端 | 生成日志，通过 TCP/UDP 转发到 log-server |
| **log-server** | 172.20.0.13 | 日志服务器 | 接收远程日志，写入 MySQL 数据库 |
| **mysql-server** | 172.20.0.16 | MySQL 数据库 | 存储日志数据 |

### 1.3 日志流

```
应用（logger）
    ↓
客户端 rsyslog
    ↓ 转发（TCP/UDP 514）
log-server rsyslog
    ↓ ommysql 模块
MySQL 数据库
    ↓
SystemEvents 表
```

---

## 🚀 第二部分：启动环境

### 2.1 启动所有容器

```bash
cd /root/docker-man/03.rsyslog/02.manual-syslog-server
docker compose up -d
```

### 2.2 验证容器状态

```bash
docker compose ps
```

**预期输出**：
```
NAME            IMAGE           STATUS         PORTS
client-1        ...             Up
client-2        ...             Up
log-server      ...             Up             0.0.0.0:xxx->514/tcp, 514/udp
mysql-server    mysql:8.0       Up             0.0.0.0:xxx->3306/tcp
```

### 2.3 查看网络和 IP

```bash
docker inspect -f '{{.Name}} - {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $(docker compose ps -q)
```

---

## 🗄️ 第三部分：初始化 MySQL 数据库表

### 3.1 进入 log-server 容器

```bash
docker exec -it log-server bash
```

### 3.2 安装 rsyslog-mysql（包含官方 SQL 脚本）

```bash
yum install -y rsyslog-mysql mariadb
```

**说明**：
- `rsyslog-mysql`：rsyslog 的 MySQL 输出模块，包含官方表结构脚本
- `mariadb`：MySQL 客户端工具，用于连接 MySQL 服务器

### 3.3 导入官方表结构

```bash
mysql -h mysql-server -u rsyslog -prsyslogpass Syslog < /usr/share/doc/rsyslog/mysql-createDB.sql
```

**说明**：
- `/usr/share/doc/rsyslog/mysql-createDB.sql` 是 rsyslog 官方提供的标准表结构
- 自动创建 `SystemEvents` 和 `SystemEventsProperties` 两张表
- 已优化索引，适合生产环境使用

### 3.4 验证表创建

**在 MySQL 容器中验证**：

```bash
docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e "SHOW TABLES;"
```

**预期输出**：
```
+---------------------------+
| Tables_in_Syslog          |
+---------------------------+
| SystemEvents              |
| SystemEventsProperties    |
+---------------------------+
```

**查看表结构**：

```bash
docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e "DESC SystemEvents;"
```

---

## 🖥️ 第四部分：配置 Log-server（日志服务器）

### 4.1 继续在 log-server 容器中（如已退出，重新进入）

```bash
docker exec -it log-server bash
```

**注意**：此时已经安装了 rsyslog-mysql 和 mariadb（第三部分已完成）

### 4.2 编辑 rsyslog 配置

```bash
vim /etc/rsyslog.conf
```

### 4.3 添加以下配置

在文件中添加（或修改）以下内容：

```bash
#### GLOBAL DIRECTIVES ####
global(workDirectory="/var/lib/rsyslog")

#### MODULES ####

# 加载输出模块
module(load="builtin:omfile" Template="RSYSLOG_TraditionalFileFormat")

# 加载 MySQL 输出模块
module(load="ommysql")

# 加载 TCP 输入模块（接收远程日志）
module(load="imtcp")
input(type="imtcp" port="514")

# 加载 UDP 输入模块（接收远程日志）
module(load="imudp")
input(type="imudp" port="514")

# 本地日志支持
module(load="imuxsock" SysSock.Use="off")
module(load="imjournal"
       UsePid="system"
       StateFile="imjournal.state")

#### RULES ####

# 所有日志写入 MySQL
*.*  :ommysql:mysql-server,Syslog,rsyslog,rsyslogpass

# 本地日志也保存到文件
*.info;mail.none;authpriv.none;cron.none    /var/log/messages
authpriv.*                                  /var/log/secure
mail.*                                      -/var/log/maillog
cron.*                                      /var/log/cron
*.emerg                                     :omusrmsg:*
```

### 4.4 配置说明

| 配置项 | 说明 |
|--------|------|
| `module(load="imtcp")` | 加载 TCP 输入模块 |
| `input(type="imtcp" port="514")` | 监听 TCP 514 端口 |
| `module(load="imudp")` | 加载 UDP 输入模块 |
| `input(type="imudp" port="514")` | 监听 UDP 514 端口 |
| `module(load="ommysql")` | 加载 MySQL 输出模块 |
| `:ommysql:` | MySQL 输出动作 |
| `mysql-server` | MySQL 主机名（容器名） |
| `Syslog` | 数据库名 |
| `rsyslog` | MySQL 用户名 |
| `rsyslogpass` | MySQL 密码 |

### 4.5 测试配置语法

```bash
rsyslogd -N1
```

如果没有错误，继续下一步。

### 4.6 启动 rsyslog

```bash
# 启动 journald（如果需要）
/usr/lib/systemd/systemd-journald &
sleep 2

# 创建 /dev/log 链接
ln -sf /run/systemd/journal/dev-log /dev/log

# 启动 rsyslog（前台调试模式）
rsyslogd -dn
```

**或者后台运行**：

```bash
/usr/lib/systemd/systemd-journald &
sleep 2
ln -sf /run/systemd/journal/dev-log /dev/log
rsyslogd -n &
```

### 4.7 验证端口监听

在**宿主机**新开终端：

```bash
docker exec -it log-server bash
netstat -tunlp | grep 514
```

**预期输出**：
```
tcp        0      0 0.0.0.0:514             0.0.0.0:*               LISTEN      123/rsyslogd
udp        0      0 0.0.0.0:514             0.0.0.0:*                           123/rsyslogd
```

---

## 📡 第五部分：配置客户端（Client-1 和 Client-2）

### 5.1 进入客户端容器

```bash
# 客户端 1
docker exec -it client-1 bash
```

### 5.2 编辑 rsyslog 配置

```bash
vim /etc/rsyslog.conf
```

### 5.3 添加转发规则

在 `#### RULES ####` 部分**最前面**添加：

```bash
#### RULES ####

# 转发所有日志到 log-server（TCP）
*.*  @@172.20.0.13:514

# 或者使用 UDP（二选一）
# *.*  @172.20.0.13:514

# 本地也保存一份（可选）
*.info;mail.none;authpriv.none;cron.none    /var/log/messages
authpriv.*                                  /var/log/secure
```

### 5.4 转发语法说明

| 语法 | 协议 | 说明 |
|------|------|------|
| `@@172.20.0.13:514` | TCP | 可靠传输，双 `@` 表示 TCP |
| `@172.20.0.13:514` | UDP | 快速但可能丢失，单 `@` 表示 UDP |

**推荐使用 TCP**，保证日志不丢失。

### 5.5 启动 rsyslog

```bash
/usr/lib/systemd/systemd-journald &
sleep 2
ln -sf /run/systemd/journal/dev-log /dev/log
rsyslogd -n &
```

### 5.6 对 Client-2 重复相同配置

```bash
# 退出 client-1
exit

# 进入 client-2
docker exec -it client-2 bash

# 重复 5.2 - 5.5 步骤
```

---

## 🧪 第六部分：测试和验证

### 6.1 从客户端发送测试日志

在 **client-1** 容器中：

```bash
logger -p user.info "TEST: Message from client-1"
logger -p local0.warning "APP: Warning from client-1"
logger -p authpriv.err "AUTH: Failed login from client-1"
```

在 **client-2** 容器中：

```bash
logger -p user.info "TEST: Message from client-2"
logger -p cron.info "CRON: Job started on client-2"
logger -p local1.notice "DB: Connection from client-2"
```

### 6.2 在 log-server 查看日志

```bash
docker exec -it log-server bash
tail -f /var/log/messages
```

**预期看到客户端的日志**。

### 6.3 查询 MySQL 数据库

```bash
docker exec -it mysql-server mysql -u rsyslog -prsyslogpass Syslog
```

```sql
-- 查看所有日志
SELECT ID, ReceivedAt, FromHost, Facility, Priority, SysLogTag, Message
FROM SystemEvents
ORDER BY ReceivedAt DESC
LIMIT 10;

-- 按主机过滤
SELECT ReceivedAt, FromHost, Message
FROM SystemEvents
WHERE FromHost = 'client-1'
ORDER BY ReceivedAt DESC
LIMIT 5;

-- 按设施过滤（user=1, authpriv=10, local0=16）
SELECT ReceivedAt, FromHost, Facility, Message
FROM SystemEvents
WHERE Facility = 16
ORDER BY ReceivedAt DESC;

-- 按优先级过滤（info=6, warning=4, err=3）
SELECT ReceivedAt, FromHost, Priority, Message
FROM SystemEvents
WHERE Priority <= 4
ORDER BY ReceivedAt DESC;

-- 统计每个主机的日志数量
SELECT FromHost, COUNT(*) as LogCount
FROM SystemEvents
GROUP BY FromHost;
```

### 6.4 预期输出示例

```
+----+---------------------+----------+----------+----------+------------+----------------------------------+
| ID | ReceivedAt          | FromHost | Facility | Priority | SysLogTag  | Message                          |
+----+---------------------+----------+----------+----------+------------+----------------------------------+
|  1 | 2024-10-07 12:30:01 | client-1 |        1 |        6 | root       | TEST: Message from client-1      |
|  2 | 2024-10-07 12:30:05 | client-1 |       16 |        4 | root       | APP: Warning from client-1       |
|  3 | 2024-10-07 12:30:10 | client-1 |       10 |        3 | root       | AUTH: Failed login from client-1 |
|  4 | 2024-10-07 12:30:15 | client-2 |        1 |        6 | root       | TEST: Message from client-2      |
|  5 | 2024-10-07 12:30:20 | client-2 |        9 |        6 | root       | CRON: Job started on client-2    |
+----+---------------------+----------+----------+----------+------------+----------------------------------+
```

---

## 🔍 第七部分：故障排查

### 7.1 日志服务器未收到日志

**检查 log-server 端口监听**：
```bash
docker exec log-server netstat -tunlp | grep 514
```

**检查 rsyslog 是否运行**：
```bash
docker exec log-server ps aux | grep rsyslog
```

**查看 rsyslog 错误日志**：
```bash
docker exec log-server journalctl -u rsyslog -n 50
```

### 7.2 MySQL 连接失败

**测试 MySQL 连接**：
```bash
docker exec -it log-server bash
mysql -h mysql-server -u rsyslog -prsyslogpass Syslog -e "SHOW TABLES;"
```

**检查 MySQL 容器日志**：
```bash
docker logs mysql-server
```

### 7.3 客户端无法转发日志

**检查客户端配置**：
```bash
docker exec client-1 cat /etc/rsyslog.conf | grep "@@"
```

**测试网络连通性**：
```bash
docker exec client-1 ping -c 3 172.20.0.13
docker exec client-1 nc -zv 172.20.0.13 514
```

**重启客户端 rsyslog**：
```bash
docker exec client-1 pkill rsyslogd
docker exec client-1 rsyslogd -n &
```

### 7.4 查看 rsyslog 调试信息

在 log-server 前台运行调试模式：

```bash
docker exec -it log-server bash
pkill rsyslogd
rsyslogd -dn
```

观察是否有错误信息。

---

## 📊 第八部分：高级查询和监控

### 8.1 实时监控日志（MySQL）

```sql
-- 每 5 秒刷新一次（在 MySQL 客户端外使用 watch）
watch -n 5 "docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e 'SELECT ReceivedAt, FromHost, Message FROM SystemEvents ORDER BY ReceivedAt DESC LIMIT 5'"
```

### 8.2 日志统计分析

```sql
-- 按小时统计日志数量
SELECT
    DATE_FORMAT(ReceivedAt, '%Y-%m-%d %H:00') as Hour,
    COUNT(*) as LogCount
FROM SystemEvents
GROUP BY Hour
ORDER BY Hour DESC;

-- 按设施统计
SELECT
    Facility,
    CASE Facility
        WHEN 0 THEN 'kern'
        WHEN 1 THEN 'user'
        WHEN 9 THEN 'cron'
        WHEN 10 THEN 'authpriv'
        WHEN 16 THEN 'local0'
        WHEN 17 THEN 'local1'
        ELSE 'other'
    END as FacilityName,
    COUNT(*) as LogCount
FROM SystemEvents
GROUP BY Facility
ORDER BY LogCount DESC;

-- 按优先级统计（错误和警告）
SELECT
    Priority,
    CASE Priority
        WHEN 0 THEN 'emerg'
        WHEN 1 THEN 'alert'
        WHEN 2 THEN 'crit'
        WHEN 3 THEN 'err'
        WHEN 4 THEN 'warning'
        WHEN 5 THEN 'notice'
        WHEN 6 THEN 'info'
        WHEN 7 THEN 'debug'
    END as PriorityName,
    COUNT(*) as LogCount
FROM SystemEvents
WHERE Priority <= 4
GROUP BY Priority
ORDER BY Priority;
```

### 8.3 搜索特定内容

```sql
-- 搜索包含特定关键词的日志
SELECT ReceivedAt, FromHost, Message
FROM SystemEvents
WHERE Message LIKE '%error%'
ORDER BY ReceivedAt DESC
LIMIT 10;

-- 搜索特定时间范围
SELECT ReceivedAt, FromHost, Message
FROM SystemEvents
WHERE ReceivedAt >= '2024-10-07 12:00:00'
  AND ReceivedAt <= '2024-10-07 13:00:00'
ORDER BY ReceivedAt DESC;
```

---

## 📝 第九部分：清理和停止

### 9.1 停止容器

```bash
cd /root/docker-man/03.rsyslog/02.manual-syslog-server
docker compose down
```

### 9.2 清理数据（可选）

```bash
# 删除 MySQL 数据卷
docker volume ls | grep 02-manual-syslog-server
docker volume rm <volume-name>
```

---

## ✅ 第十部分：测试检查清单

- [ ] 所有容器成功启动（4 个容器）
- [ ] MySQL 数据库创建成功，表结构正确
- [ ] log-server 监听 TCP 514 和 UDP 514 端口
- [ ] log-server 成功加载 ommysql 模块
- [ ] client-1 和 client-2 配置转发规则
- [ ] 从 client-1 发送测试日志，MySQL 收到
- [ ] 从 client-2 发送测试日志，MySQL 收到
- [ ] 可以通过 SQL 查询不同主机的日志
- [ ] 可以按设施和优先级过滤日志
- [ ] 理解 TCP (@@ ) 和 UDP (@) 转发的区别

---

## 🎯 学习目标

- ✅ 理解 rsyslog 集中式日志架构
- ✅ 掌握 rsyslog TCP/UDP 接收配置（imtcp/imudp）
- ✅ 掌握 rsyslog MySQL 输出配置（ommysql）
- ✅ 掌握客户端日志转发配置（@@host:port）
- ✅ 理解 SystemEvents 表结构
- ✅ 掌握 SQL 查询日志的方法
- ✅ 故障排查和调试技巧

---

## 📖 参考资料

- rsyslog 官方文档：http://www.rsyslog.com/doc/
- ommysql 模块：http://www.rsyslog.com/doc/ommysql.html
- imtcp 模块：http://www.rsyslog.com/doc/imtcp.html
- imudp 模块：http://www.rsyslog.com/doc/imudp.html

---

## ❓ 常见问题

### Q1: TCP 和 UDP 哪个更好？

- **TCP (`@@`)**：可靠传输，适合重要日志，但性能稍低
- **UDP (`@`)**：高性能，适合大量非关键日志，可能丢失

**建议**：生产环境用 TCP。

### Q2: 如何防止 MySQL 数据库过大？

定期清理旧日志：

```sql
-- 删除 30 天前的日志
DELETE FROM SystemEvents
WHERE ReceivedAt < DATE_SUB(NOW(), INTERVAL 30 DAY);
```

或者使用分区表、归档策略。

### Q3: 可以同时写入文件和 MySQL 吗？

可以，在 log-server 的规则中保留文件输出：

```bash
*.*  :ommysql:mysql-server,Syslog,rsyslog,rsyslogpass
*.*  /var/log/all.log
```

### Q4: 如何增加更多客户端？

在 `compose.yml` 中添加新的 client-3、client-4 服务，然后重复客户端配置步骤。
