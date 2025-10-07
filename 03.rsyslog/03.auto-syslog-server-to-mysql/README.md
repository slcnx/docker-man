# rsyslog 集中式日志服务器（自动化部署）

## 🚀 快速开始

### 1. 启动环境

```bash
cd /root/docker-man/03.rsyslog/03.auto-syslog-server
docker compose up -d
```

### 2. 等待服务就绪

```bash
# 查看容器状态
docker compose ps

# 查看日志（等待所有服务启动完成）
docker compose logs -f
```

**预期看到**：
- MySQL 初始化完成
- log-server 安装 rsyslog-mysql 并启动
- client-1 和 client-2 自动发送测试日志

### 3. 验证日志接收

```bash
# 查询 MySQL 中的日志
docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e "
SELECT ID, ReceivedAt, FromHost, Facility, Priority, Message
FROM SystemEvents
ORDER BY ReceivedAt DESC
LIMIT 10;
"
```

**预期输出**：
```
+----+---------------------+----------+----------+----------+------------------------------------------+
| ID | ReceivedAt          | FromHost | Facility | Priority | Message                                  |
+----+---------------------+----------+----------+----------+------------------------------------------+
|  1 | 2024-10-07 12:30:01 | client-1 |        1 |        6 | CLIENT-1: Started and ready to send logs |
|  2 | 2024-10-07 12:30:02 | client-1 |       16 |        4 | CLIENT-1: Application warning test       |
|  3 | 2024-10-07 12:30:03 | client-2 |        1 |        6 | CLIENT-2: Started and ready to send logs |
|  4 | 2024-10-07 12:30:04 | client-2 |       17 |        5 | CLIENT-2: Database connection test       |
+----+---------------------+----------+----------+----------+------------------------------------------+
```

---

## 📊 架构说明

```
┌─────────────┐       ┌─────────────┐
│  Client-1   │       │  Client-2   │
│ 172.20.0.11  │       │ 172.20.0.12  │
└──────┬──────┘       └──────┬──────┘
       │                     │
       │  TCP 514            │
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

### 组件说明

| 组件 | IP | 功能 | 配置文件 | 健康检查 |
|------|----|----|---------|---------|
| **mysql-server** | 172.20.0.16 | 存储日志 | 自动初始化（rsyslog 官方脚本） | `mysqladmin ping` |
| **log-server** | 172.20.0.13 | 接收并存储日志 | `server-configs/rsyslog.conf` | 检查 514 端口监听 |
| **client-1** | 172.20.0.11 | 发送日志 | `client-configs/rsyslog.conf` | 无（依赖 log-server） |
| **client-2** | 172.20.0.12 | 发送日志 | `client-configs/rsyslog.conf` | 无（依赖 log-server） |

### 启动顺序保证

```
1. mysql-server 启动 → 健康检查通过（mysqladmin ping）
   ↓
2. log-server 启动 → 安装模块 → 初始化表 → 启动 rsyslog → 健康检查通过（514 端口监听）
   ↓
3. client-1 和 client-2 启动 → 发送测试日志
```

**说明**：
- log-server 有 30 秒的 `start_period`，给予足够时间安装模块和初始化
- 健康检查每 5 秒一次，最多重试 10 次
- 只有 log-server 的 514 端口正常监听后，客户端才会启动

---

## 🧪 测试命令

### 从客户端发送日志

```bash
# 在 client-1 发送日志
docker exec client-1 logger -p user.info "TEST: Message from client-1"
docker exec client-1 logger -p local0.warning "APP: Warning from client-1"
docker exec client-1 logger -p authpriv.err "AUTH: Failed login from client-1"

# 在 client-2 发送日志
docker exec client-2 logger -p user.info "TEST: Message from client-2"
docker exec client-2 logger -p cron.info "CRON: Job started on client-2"
docker exec client-2 logger -p local1.notice "DB: Connection from client-2"
```

### 查询日志

```bash
# 查看所有日志
docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e "
SELECT ReceivedAt, FromHost, Facility, Priority, Message
FROM SystemEvents
ORDER BY ReceivedAt DESC
LIMIT 20;
"

# 按主机过滤
docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e "
SELECT ReceivedAt, Message
FROM SystemEvents
WHERE FromHost = 'client-1'
ORDER BY ReceivedAt DESC
LIMIT 10;
"

# 按设施过滤（local0=16, local1=17）
docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e "
SELECT ReceivedAt, FromHost, Facility, Message
FROM SystemEvents
WHERE Facility = 16
ORDER BY ReceivedAt DESC;
"

# 按优先级过滤（err=3, warning=4）
docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e "
SELECT ReceivedAt, FromHost, Priority, Message
FROM SystemEvents
WHERE Priority <= 4
ORDER BY ReceivedAt DESC;
"

# 统计每个主机的日志数量
docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e "
SELECT FromHost, COUNT(*) as LogCount
FROM SystemEvents
GROUP BY FromHost;
"
```

---

## 🔍 验证和调试

### 检查服务状态

```bash
# 查看所有容器状态和健康检查
docker compose ps

# 查看详细健康检查状态
docker inspect mysql-server --format='{{.State.Health.Status}}'
docker inspect log-server --format='{{.State.Health.Status}}'

# 查看 log-server 日志（包含初始化过程）
docker compose logs log-server

# 查看客户端日志
docker compose logs client-1
docker compose logs client-2

# 查看 MySQL 日志
docker compose logs mysql-server
```

**预期健康状态**：
```bash
$ docker compose ps
NAME            STATUS                        PORTS
mysql-server    Up (healthy)                  0.0.0.0:xxx->3306/tcp
log-server      Up (healthy)                  0.0.0.0:xxx->514/tcp, 514/udp
client-1        Up
client-2        Up
```

### 检查网络连通性

```bash
# 测试客户端到服务器的连接
docker exec client-1 ping -c 3 172.20.0.13
docker exec client-1 nc -zv 172.20.0.13 514

# 检查 log-server 端口监听
docker exec log-server netstat -tunlp | grep 514
```

### 检查 rsyslog 进程

```bash
# 检查 log-server
docker exec log-server ps aux | grep rsyslog

# 检查客户端
docker exec client-1 ps aux | grep rsyslog
docker exec client-2 ps aux | grep rsyslog
```

---

## 📝 配置文件说明

### server-configs/rsyslog.conf

log-server 的配置：
- 加载 `imtcp` 和 `imudp` 模块，监听 514 端口
- 加载 `ommysql` 模块，写入 MySQL
- 规则：`*.*  :ommysql:mysql-server,Syslog,rsyslog,rsyslogpass`

### client-configs/rsyslog.conf

客户端的配置：
- 转发规则：`*.*  @@172.20.0.13:514`（TCP 转发）
- `@@` 表示 TCP，`@` 表示 UDP
- 本地也保存一份日志到 `/var/log/messages` 等

### MySQL 表初始化

log-server 启动时自动执行：
- 安装 `rsyslog-mysql` 和 `mariadb` 客户端
- 使用 rsyslog 官方脚本 `/usr/share/doc/rsyslog/mysql-createDB.sql` 初始化表
- 创建 `SystemEvents` 和 `SystemEventsProperties` 表
- 已包含优化的索引（ReceivedAt, FromHost, Facility, Priority）

---

## 🛑 停止和清理

### 停止环境

```bash
docker compose down
```

### 清理数据（可选）

```bash
# 删除数据卷
docker volume ls | grep 03-auto-syslog-server
docker volume rm <volume-name>
```

---

## ✅ 测试检查清单

- [ ] 所有容器成功启动（4 个）
- [ ] MySQL 自动创建 SystemEvents 表
- [ ] log-server 监听 TCP 514 和 UDP 514
- [ ] client-1 和 client-2 自动发送启动日志
- [ ] MySQL 中可以查询到客户端日志
- [ ] 可以手动发送日志并在 MySQL 中查询
- [ ] 可以按主机、设施、优先级过滤日志

---

## 🎯 学习目标

- ✅ 理解 rsyslog 集中式日志架构
- ✅ 掌握自动化部署（Docker Compose + 配置文件挂载）
- ✅ 掌握 rsyslog TCP 接收和转发配置
- ✅ 掌握 rsyslog MySQL 输出配置
- ✅ 掌握 SQL 查询和统计日志

---

## 📖 与手工版本的区别

| 特性 | 手工版（02.manual） | 自动版（03.auto） |
|------|-------------------|------------------|
| 配置方式 | 容器内手工编辑 | 挂载配置文件 |
| MySQL 表 | 手工创建 SQL | 自动初始化脚本 |
| rsyslog-mysql | 手工安装 | 启动脚本自动安装 |
| 测试日志 | 手工发送 | 启动时自动发送 |
| 适用场景 | 学习和调试 | 生产环境快速部署 |

---

## 🔧 扩展和定制

### 添加更多客户端

在 `compose.yml` 中添加：

```yaml
client-3:
  build:
    context: ..
    dockerfile: rsyslog.dockerfile
  container_name: client-3
  hostname: client-3
  networks:
    rsyslog-net:
      ipv4_address: 172.20.0.14
  volumes:
    - ./client-configs/rsyslog.conf:/etc/rsyslog.conf:ro
  command: >
    bash -c "
      /usr/lib/systemd/systemd-journald &
      sleep 2 &&
      ln -sf /run/systemd/journal/dev-log /dev/log &&
      rsyslogd -n &
      sleep 3 &&
      logger -p user.info 'CLIENT-3: Started' &&
      tail -f /dev/null
    "
  depends_on:
    - log-server
  restart: unless-stopped
```

### 修改转发协议（UDP）

编辑 `client-configs/rsyslog.conf`，将 `@@` 改为 `@`：

```bash
# 从 TCP 改为 UDP
*.*  @172.20.0.13:514
```

### 持久化 MySQL 数据

在 `compose.yml` 的 `mysql-server` 中添加：

```yaml
volumes:
  - ./server-configs/init-mysql.sql:/docker-entrypoint-initdb.d/init.sql:ro
  - mysql-data:/var/lib/mysql  # 添加这行

# 在文件末尾添加
volumes:
  mysql-data:
```

---

## ❓ 常见问题

### Q1: 如何查看实时日志？

```bash
# 方式 1：watch MySQL 查询
watch -n 2 "docker exec mysql-server mysql -u rsyslog -prsyslogpass Syslog -e 'SELECT ReceivedAt, FromHost, Message FROM SystemEvents ORDER BY ReceivedAt DESC LIMIT 5'"

# 方式 2：MySQL 客户端
docker exec -it mysql-server mysql -u rsyslog -prsyslogpass Syslog
# 然后反复执行查询
```

### Q2: 如何修改配置文件？

编辑 `server-configs/rsyslog.conf` 或 `client-configs/rsyslog.conf`，然后重启：

```bash
docker compose restart log-server
docker compose restart client-1 client-2
```

### Q3: 日志太多怎么清理？

```bash
# 进入 MySQL
docker exec -it mysql-server mysql -u rsyslog -prsyslogpass Syslog

# 删除旧日志
DELETE FROM SystemEvents WHERE ReceivedAt < DATE_SUB(NOW(), INTERVAL 7 DAY);

# 或清空表
TRUNCATE TABLE SystemEvents;
```

### Q4: 如何切换到 UDP 模式？

UDP 速度更快但可能丢包，适合非关键日志：

1. 编辑 `client-configs/rsyslog.conf`
2. 将 `@@172.20.0.13:514` 改为 `@172.20.0.13:514`
3. 重启客户端：`docker compose restart client-1 client-2`

---

## 📚 参考资料

- **手工配置教程**：参见 `../02.manual-syslog-server/compose.md`
- rsyslog 官方文档：http://www.rsyslog.com/doc/
- ommysql 模块：http://www.rsyslog.com/doc/ommysql.html
