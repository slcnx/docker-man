# rsyslog 设施（Facility）和优先级（Priority）手工测试

## 📚 第一部分：基础知识

### 1.1 什么是设施（Facility）

设施（Facility）用于**标识日志的来源类型**，将不同类型的日志分类存储和处理。

#### 标准设施（0-11）

| 设施 | 数值 | 说明 | 典型应用 | 用途 |
|------|------|------|---------|------|
| **kern** | 0 | 内核消息 | Linux 内核 | 系统启动、硬件错误 |
| **user** | 1 | 用户级消息（默认） | 用户进程 | 普通应用程序日志 |
| **mail** | 2 | 邮件系统 | Postfix, Sendmail | 邮件收发日志 |
| **daemon** | 3 | 系统守护进程 | systemd, cron | 后台服务日志 |
| **auth** | 4 | 安全/认证（非敏感） | login, su | 认证尝试 |
| **syslog** | 5 | syslog 内部消息 | rsyslog 自身 | rsyslog 启动、错误 |
| **lpr** | 6 | 打印子系统 | CUPS | 打印任务 |
| **news** | 7 | 网络新闻子系统 | NNTP | 新闻组 |
| **uucp** | 8 | UUCP 子系统 | 已过时 | Unix间文件传输 |
| **cron** | 9 | 时钟守护进程 | cron, at | 定时任务日志 |
| **authpriv** | 10 | 安全/认证（敏感） | sshd, sudo | SSH、密码等敏感信息 |
| **ftp** | 11 | FTP 守护进程 | vsftpd, proftpd | FTP 传输日志 |

#### 本地自定义设施（16-23）

| 设施 | 数值 | 推荐用途 | 典型应用 |
|------|------|---------|---------|
| **local0** | 16 | Web 服务器 | Nginx, Apache |
| **local1** | 17 | 数据库 | MySQL, PostgreSQL |
| **local2** | 18 | 应用程序 | 自定义 Web 应用 |
| **local3** | 19 | 监控系统 | Zabbix, Prometheus |
| **local4** | 20 | 中间件 | Redis, RabbitMQ |
| **local5** | 21 | 容器平台 | Docker, Kubernetes |
| **local6** | 22 | 备份系统 | rsync, Bacula |
| **local7** | 23 | 其他自定义 | - |

---

### 1.2 什么是优先级（Priority/Severity）

优先级（Priority）表示**日志的严重程度**，从最严重（0）到最不严重（7）。

| 优先级 | 数值 | 说明 | 使用场景 | 示例 | 是否告警 |
|--------|------|------|---------|------|---------|
| **emerg** | 0 | 紧急：系统不可用 | 系统崩溃、内核 panic | "System panic" | 🔴 立即 |
| **alert** | 1 | 警报：必须立即采取行动 | 数据库损坏、硬盘故障 | "Database corrupted" | 🔴 立即 |
| **crit** | 2 | 严重：严重错误条件 | 关键服务失败 | "Primary disk failure" | 🔴 立即 |
| **err** | 3 | 错误：错误条件 | 应用程序错误 | "Connection refused" | 🟡 定期检查 |
| **warning** | 4 | 警告：警告条件 | 资源不足、性能下降 | "Memory usage 85%" | 🟡 定期检查 |
| **notice** | 5 | 通知：正常但重要 | 配置更改、服务重启 | "Service restarted" | ⚪ 记录 |
| **info** | 6 | 信息：一般信息 | 常规操作日志 | "User logged in" | ⚪ 记录 |
| **debug** | 7 | 调试：调试级别 | 开发调试信息 | "Variable x=10" | ⚪ 记录 |

---

### 1.3 logger 命令语法

```bash
logger -p <facility>.<priority> [-t tag] "message"
```

**示例**：
```bash
logger -p authpriv.info "User login"          # authpriv 设施（敏感登录），info 优先级
logger -p cron.err "Job failed"               # cron 设施，error 优先级
logger -t nginx -p local0.warning "Alert"     # local0 设施，warning 优先级，标签 nginx
logger "Test"                                 # 默认：user.notice
```

---

## 🚀 第二部分：启动环境

### 2.1 启动容器

```bash
cd /root/docker-man/03.rsyslog/01.manual-sshd-facility
docker compose up -d
```

### 2.2 进入容器

```bash
docker exec -it rsyslog-facility-test bash
```

### 2.3 检查服务状态

```bash
# 检查 journald（后台运行）
ps aux | grep journald
# 应该看到：/usr/lib/systemd/systemd-journald

# 检查 rsyslog（前台 debug 模式）
ps aux | grep rsyslog
# 应该看到：rsyslogd -dn

# 检查 /dev/log 链接
ls -la /dev/log
# 输出：/dev/log -> /run/systemd/journal/dev-log
```

---

## 📐 第三部分：日志流转架构

### 3.1 架构图

```
应用程序（logger）
    ↓ 写入
/dev/log (socket)
    ↓ 符号链接指向
/run/systemd/journal/dev-log
    ↓ systemd-journald 监听
systemd-journald
    ↓ 存储为二进制
/run/log/journal/.../system.journal
    │
    ├─→ journalctl 查询（结构化，带元数据）
    │
    └─→ rsyslog 通过 imjournal 模块读取
            ↓ 过滤、格式化、路由
        rsyslog 规则匹配
            ↓ 按设施分类写入
        /var/log/*.log（文本文件）
```

### 3.2 数据流说明

1. **应用写入**：`logger` 命令写入 `/dev/log`
2. **journald 收集**：systemd-journald 监听 `/run/systemd/journal/dev-log`
3. **结构化存储**：日志以二进制格式存储，包含丰富的元数据
4. **rsyslog 读取**：rsyslog 通过 `imjournal` 模块读取 journal
5. **文本输出**：rsyslog 根据规则将日志写入对应的文本文件

### 3.3 为什么要这样设计？

| 组件 | 作用 | 优势 |
|------|------|------|
| **journald** | 收集日志、添加元数据 | 结构化存储、丰富查询能力 |
| **rsyslog** | 过滤、路由、转发 | 传统文本日志、远程转发、兼容性 |

**两者结合**：既有 journald 的强大查询，又有 rsyslog 的灵活路由。

---

## 🧪 第四部分：测试每个设施

### 4.1 发送测试日志（所有设施）

在容器内执行：

```bash
# 标准设施
logger -p kern.info "KERN: Kernel message"
logger -p user.info "USER: User message"
logger -p mail.info "MAIL: Mail system message"
logger -p daemon.info "DAEMON: Daemon message"
logger -p auth.info "AUTH: Authentication message"
logger -p syslog.info "SYSLOG: Syslog internal message"
logger -p cron.info "CRON: Cron job message"
logger -p authpriv.info "AUTHPRIV: Sensitive auth message"

# 本地自定义设施
logger -p local0.info "LOCAL0: Web server message"
logger -p local1.info "LOCAL1: Database message"
logger -p local2.info "LOCAL2: Application message"
logger -p local3.info "LOCAL3: Monitoring message"
logger -p local4.info "LOCAL4: Middleware message"
logger -p local5.info "LOCAL5: Container message"
logger -p local6.info "LOCAL6: Backup message"
logger -p local7.info "LOCAL7: Custom message"
```

### 4.2 测试所有优先级（使用 user 设施）

```bash
logger -p user.emerg "EMERG (0): System unusable"
logger -p user.alert "ALERT (1): Action required immediately"
logger -p user.crit "CRIT (2): Critical conditions"
logger -p user.err "ERR (3): Error conditions"
logger -p user.warning "WARNING (4): Warning conditions"
logger -p user.notice "NOTICE (5): Normal but significant"
logger -p user.info "INFO (6): Informational"
logger -p user.debug "DEBUG (7): Debug-level"
```

---

## 🔍 第五部分：查看 journal 日志

### 5.1 查看最新日志（JSON 格式，包含元数据）

```bash
journalctl -n 1 -o json-pretty
```

**输出示例**：
```json
{
  "_TRANSPORT" : "syslog",
  "PRIORITY" : "6",                    ← 优先级（6 = info）
  "SYSLOG_FACILITY" : "1",            ← 设施（1 = user）
  "SYSLOG_IDENTIFIER" : "root",
  "MESSAGE" : "USER: User message",   ← 消息内容
  "_PID" : "123",                      ← 自动捕获的进程 ID
  "_UID" : "0",                        ← 自动捕获的用户 ID
  "_GID" : "0",
  "_COMM" : "logger",                  ← 命令名
  "_EXE" : "/usr/bin/logger",          ← 可执行文件路径
  "_CMDLINE" : "logger -p user.info USER: User message",  ← 完整命令行
  "_HOSTNAME" : "rsyslog-test",
  "_MACHINE_ID" : "...",
  "_BOOT_ID" : "...",
  "__REALTIME_TIMESTAMP" : "...",
  "__MONOTONIC_TIMESTAMP" : "..."
}
```

**关键字段说明**：
- `SYSLOG_FACILITY`: 设施数值（1 = user）
- `PRIORITY`: 优先级数值（6 = info）
- `MESSAGE`: 日志消息正文
- `_PID`, `_UID`, `_COMM` 等：journald 自动捕获的元数据

### 5.2 按设施查询

```bash
# 查看 authpriv (10) 设施的日志
journalctl SYSLOG_FACILITY=10 --since "5 minutes ago" --no-pager

# 查看 cron (9) 设施的日志
journalctl SYSLOG_FACILITY=9 --since "5 minutes ago" --no-pager

# 查看 local0 (16) 设施的日志
journalctl SYSLOG_FACILITY=16 --since "5 minutes ago" --no-pager
```

### 5.3 按优先级查询

```bash
# 查看 error (3) 及以上优先级的日志
journalctl PRIORITY=0..3 --since "5 minutes ago" --no-pager

# 查看 warning (4) 优先级的日志
journalctl PRIORITY=4 --since "5 minutes ago" --no-pager
```

### 5.4 组合查询

```bash
# 查看 authpriv 设施的 error 日志
journalctl SYSLOG_FACILITY=10 PRIORITY=3 --since "5 minutes ago" --no-pager
```

---

## 📂 第六部分：rsyslog 配置详解

### 6.1 查看默认配置

```bash
cat /etc/rsyslog.conf
```

### 6.2 配置结构说明

rsyslog 配置分为三个部分：

```
#### GLOBAL DIRECTIVES ####
   （全局指令）

#### MODULES ####
   （模块加载）

#### RULES ####
   （规则：设施.优先级 → 动作）
```

---

### 6.3 GLOBAL DIRECTIVES（全局指令）

```bash
#### GLOBAL DIRECTIVES ####
global(workDirectory="/var/lib/rsyslog")
```

**含义**：
- `workDirectory`: rsyslog 工作目录，用于存储状态文件、队列等
- 示例：`/var/lib/rsyslog/imjournal.state` 记录 journal 的读取位置

**其他常见全局指令**：
```bash
global(
    workDirectory="/var/lib/rsyslog"
    maxMessageSize="64k"           # 最大消息大小
)
```

---

### 6.4 MODULES（模块加载）

```bash
#### MODULES ####
module(load="builtin:omfile" Template="RSYSLOG_TraditionalFileFormat")

module(load="imuxsock"     # 提供本地系统日志支持（如 logger 命令）
       SysSock.Use="off")  # 关闭本地 socket 接收；本地消息通过 imjournal 获取

module(load="imjournal"    # 访问 systemd journal
       UsePid="system"     # PID 来自日志条目的源进程
       FileCreateMode="0644"  # 状态文件权限
       StateFile="imjournal.state")  # 存储 journal 读取位置

#module(load="imklog")     # 读取内核消息（已从 journald 读取，无需重复）
```

**模块说明**：

| 模块 | 类型 | 作用 | 说明 |
|------|------|------|------|
| `builtin:omfile` | 输出模块 | 写入文件 | `om` = output module，使用传统时间戳格式 |
| `imuxsock` | 输入模块 | Unix Socket | `im` = input module，但 `SysSock.Use="off"` 关闭了直接接收 |
| `imjournal` | 输入模块 | Journal 日志 | **核心模块**：从 systemd-journald 读取所有日志 |
| `imklog` | 输入模块 | 内核日志 | 已注释（内核日志已包含在 journal 中） |

**为什么使用 imjournal？**

| 配置方式 | 日志流 | 优缺点 |
|---------|--------|--------|
| **传统方式**<br>`imuxsock` | logger → `/dev/log` → rsyslog | ❌ 没有 journal 的元数据<br>❌ 无法使用 journalctl 查询 |
| **现代方式**<br>`imjournal` | logger → `/dev/log` → journald → rsyslog | ✅ 保留 journal 元数据<br>✅ 可用 journalctl 查询<br>✅ rsyslog 也能处理 |

**关键点**：
- `SysSock.Use="off"`: 关闭 rsyslog 直接监听 `/dev/log`
- `/dev/log` 由 journald 监听（链接到 `/run/systemd/journal/dev-log`）
- rsyslog 通过 `imjournal` 从 journal 读取，获得更丰富的信息

**模块命名规则**：
- `im` 开头：Input Module（输入模块）
- `om` 开头：Output Module（输出模块）
- `pm` 开头：Parser Module（解析模块）

**常见输入模块**：
- `imuxsock`: 本地 Unix socket（`/dev/log`）
- `imjournal`: systemd journal
- `imklog`: 内核日志
- `imudp`: UDP 514 端口（远程 syslog）
- `imtcp`: TCP 514 端口（远程 syslog）
- `imfile`: 监控文本日志文件

**常见输出模块**：
- `omfile`: 写入本地文件
- `omfwd`: 转发到远程 syslog 服务器
- `ommysql`: 写入 MySQL 数据库
- `omelasticsearch`: 写入 Elasticsearch

---

### 6.5 RULES（规则）

规则格式：
```
<selector>    <action>
   ↑             ↑
设施.优先级   执行动作
```

#### 规则 1：authpriv 敏感日志

```bash
authpriv.*    /var/log/secure
```

**含义**：
- `authpriv`: 设施 10（敏感认证信息）
- `.*`: 所有优先级（0-7，即 emerg 到 debug）
- `/var/log/secure`: 写入敏感日志文件（权限通常是 600）

**为什么单独存储？**
- SSH 登录、sudo、密码等敏感信息
- 严格的文件权限，防止普通用户查看

**匹配的日志**：
```bash
logger -p authpriv.info "SSH login from 192.168.1.100"  ← 匹配
logger -p authpriv.err "sudo authentication failure"    ← 匹配
logger -p auth.info "Test"                              ← 不匹配（auth ≠ authpriv）
```

---

#### 规则 2：mail 邮件日志（异步写入）

```bash
mail.*    -/var/log/maillog
```

**含义**：
- `mail`: mail 设施（数值 2）
- `.*`: 所有优先级
- `-/var/log/maillog`: **异步写入**（注意前面的 `-`）

**为什么异步？**
- 邮件日志量可能很大
- 异步写入避免阻塞日志进程
- 提升性能，但可能在崩溃时丢失少量未写入的日志

---

#### 规则 3：cron 日志

```bash
cron.*    /var/log/cron
```

**含义**：
- `cron`: cron 设施（数值 9）
- `.*`: 所有优先级
- `/var/log/cron`: cron 专用日志文件

---

#### 规则 4：messages 汇总日志（重要）

```bash
*.info;mail.none;authpriv.none;cron.none    /var/log/messages
```

**详细解析**：

| 部分 | 含义 | 说明 |
|------|------|------|
| `*.info` | 所有设施的 info 及以上 | info(6), notice(5), ..., emerg(0) |
| `;` | 分隔符 | 用于组合多个选择器 |
| `mail.none` | 排除 mail 设施 | `none` = 不记录 |
| `authpriv.none` | 排除 authpriv 设施 | 敏感日志不放 messages |
| `cron.none` | 排除 cron 设施 | cron 有专门的日志文件 |

**为什么要排除**？
- `authpriv`: 敏感信息，单独存储，严格权限（600）
- `mail`, `cron`: 日志量大，单独存储便于管理

**匹配示例**：
```bash
logger -p user.info "Test"       ← 匹配（写入 messages）
logger -p daemon.warning "Test"  ← 匹配（写入 messages）
logger -p authpriv.info "Test"   ← 不匹配（被排除）
logger -p cron.info "Test"       ← 不匹配（被排除）
logger -p user.debug "Test"      ← 不匹配（debug < info）
```

---

#### 规则 5：紧急日志广播

```bash
*.emerg    :omusrmsg:*
```

**含义**：
- `*.emerg`: 所有设施的 emerg (0) 优先级
- `:omusrmsg:`: 特殊动作模块（output module user message）
- `*`: 发送给所有登录用户

**作用**：系统不可用时，向所有登录用户的终端显示紧急消息。

**测试**：
```bash
logger -p user.emerg "EMERGENCY: System is down!"
# 所有登录用户的终端会显示这条消息
```

---

#### 规则 6：UUCP 和 News 严重错误

```bash
uucp,news.crit    /var/log/spooler
```

**含义**：
- `uucp,news`: 两个设施（8 和 7）
- `.crit`: crit 及以上优先级（crit=2, alert=1, emerg=0）
- `/var/log/spooler`: 写入 spooler 日志文件

**说明**：
- UUCP 和 NNTP 是传统的 Unix 服务，现在较少使用
- 只记录严重错误（crit 及以上）

---

#### 规则 7：启动日志（local7）

```bash
local7.*    /var/log/boot.log
```

**含义**：
- `local7`: 本地设施 7（数值 23）
- `.*`: 所有优先级
- `/var/log/boot.log`: 系统启动日志

**说明**：
- Red Hat/CentOS 系统习惯用 `local7` 记录启动信息
- 包含 rc.sysinit、rc.local 等启动脚本的日志

---

### 6.6 选择器语法总结

| 语法 | 含义 | 示例 | 说明 |
|------|------|------|------|
| `facility.*` | 所有优先级 | `cron.*` | emerg(0) 到 debug(7) |
| `facility.priority` | 指定优先级及以上 | `mail.err` | err(3) 到 emerg(0) |
| `facility.=priority` | 仅指定优先级 | `user.=info` | 仅 info(6) |
| `facility.!priority` | 低于指定优先级 | `user.!err` | warning(4) 到 debug(7) |
| `facility.none` | 排除该设施 | `mail.none` | 不记录 mail |
| `*.*` | 所有设施所有优先级 | `*.*` | 全部日志 |
| `facility1,facility2` | 多个设施 | `auth,authpriv.*` | 两个设施 |
| `;` | 组合多个条件 | `*.info;mail.none` | AND 逻辑 |

---

## 🛠️ 第七部分：手工配置 rsyslog

### 7.1 备份原配置（可选）

```bash
cp /etc/rsyslog.conf /etc/rsyslog.conf.bak
```

### 7.2 复制参考配置

容器启动后，可以使用项目提供的参考配置：

```bash
# 查看项目参考配置（在宿主机）
cat /root/docker-man/03.rsyslog/01.manual-sshd-facility/rsyslog.conf
```

### 7.3 编辑配置文件

```bash
vim /etc/rsyslog.conf
```

**Rocky Linux 默认配置已包含以下规则**：

```bash
# 汇总日志（排除 mail/authpriv/cron）
*.info;mail.none;authpriv.none;cron.none    /var/log/messages

# 敏感认证日志
authpriv.*                                  /var/log/secure

# 邮件日志（异步写入）
mail.*                                      -/var/log/maillog

# Cron 日志
cron.*                                      /var/log/cron

# 紧急消息广播
*.emerg                                     :omusrmsg:*

# UUCP/News 严重错误
uucp,news.crit                              /var/log/spooler

# 启动日志
local7.*                                    /var/log/boot.log
```

### 7.4 添加自定义设施（可选）

如果要为应用添加自定义日志文件：

```bash
# 在 RULES 部分添加
local0.*    /var/log/local0.log   # Web 服务器
local1.*    /var/log/local1.log   # 数据库
local2.*    /var/log/local2.log   # 应用程序
```

### 7.5 重新加载配置

**方式 A**：杀掉并重启 rsyslog

```bash
pkill rsyslogd
rsyslogd -dn
```

**方式 B**：在新终端进入容器

```bash
# 在宿主机开新终端
docker exec -it rsyslog-facility-test bash
```

---

## 📊 第八部分：查看 rsyslog 日志文件

### 8.1 查看按设施分类的日志

```bash
# authpriv 敏感日志
tail /var/log/secure

# cron 日志
tail /var/log/cron

# mail 日志
tail /var/log/maillog

# 启动日志（local7）
tail /var/log/boot.log

# UUCP/News 日志
tail /var/log/spooler

# messages 汇总日志（所有其他设施）
tail /var/log/messages
```

### 8.2 查看自定义设施日志（如果添加了）

```bash
# local0 日志（Web 服务器）
tail /var/log/local0.log

# local1 日志（数据库）
tail /var/log/local1.log
```

### 8.3 对比 journal 和 rsyslog 日志

**journal 日志（结构化，包含元数据）**：
```bash
journalctl -n 5 -o json-pretty | grep -A 20 "Test message"
```

**rsyslog 日志（文本格式）**：
```bash
# user 设施的日志写入 messages（因为没有单独的 user.log）
grep "Test message" /var/log/messages
```

**对比**：
| 特性 | journal | rsyslog 文件 |
|------|---------|------------|
| 格式 | 二进制（JSON 导出） | 纯文本 |
| 元数据 | 20+ 个字段 | 5 个字段 |
| 查询 | 结构化查询 | grep/awk |
| 存储 | `/run/log/journal/` | `/var/log/*.log` |

---

## 🔧 第九部分：配置开源服务使用自定义 FACILITY

### 9.1 选择开源服务：Nginx

我们让 Nginx 的日志使用 **local0** 设施。

### 9.2 配置步骤

#### Step 1: 在容器内安装 Nginx（可选，仅演示）

```bash
yum install -y nginx
```

#### Step 2: 配置 Nginx 使用 syslog

编辑 Nginx 配置：
```bash
vim /etc/nginx/nginx.conf
```

找到 `access_log` 和 `error_log`，修改为：

```nginx
http {
    # Access log 使用 local0.info
    access_log syslog:server=unix:/dev/log,facility=local0,tag=nginx,severity=info;

    # Error log 使用 local0.err
    error_log syslog:server=unix:/dev/log,facility=local0,tag=nginx,severity=error;
}
```

**参数说明**：
- `server=unix:/dev/log`: 写入本地 `/dev/log`
- `facility=local0`: 使用 local0 设施（数值 16）
- `tag=nginx`: 日志标签为 nginx
- `severity=info/error`: 优先级

#### Step 3: 配置 rsyslog 接收 Nginx 日志

在 `/etc/rsyslog.conf` 中确认有：

```bash
local0.*    /var/log/local0.log
```

或者添加更详细的规则：

```bash
# Nginx access log (local0.info)
local0.info    /var/log/nginx/access.log

# Nginx error log (local0.err)
local0.err     /var/log/nginx/error.log

# 所有 local0 日志
local0.*       /var/log/local0.log
```

#### Step 4: 创建日志目录

```bash
mkdir -p /var/log/nginx
```

#### Step 5: 重启服务

```bash
# 重启 rsyslog
pkill rsyslogd
rsyslogd -dn &

# 启动 Nginx（如果已安装）
nginx
```

#### Step 6: 生成测试日志

**方式 A：使用 logger 模拟**（推荐，无需安装 Nginx）

```bash
# 模拟 Nginx access log
logger -t nginx -p local0.info '192.168.1.100 - - [07/Oct/2024:10:00:00 +0000] "GET / HTTP/1.1" 200 1234'
logger -t nginx -p local0.info '192.168.1.101 - - [07/Oct/2024:10:00:01 +0000] "GET /index.html HTTP/1.1" 200 5678'

# 模拟 Nginx error log
logger -t nginx -p local0.err 'upstream timed out (110: Connection timed out) while connecting to upstream'
logger -t nginx -p local0.err 'connect() failed (111: Connection refused) while connecting to upstream'
```

**方式 B：实际访问 Nginx**（如果已安装）

```bash
curl http://localhost/
curl http://localhost/nonexist
```

#### Step 7: 查看日志

```bash
# 查看 local0 日志
tail -f /var/log/local0.log

# 查看 Nginx 专用日志（如果配置了）
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# 使用 journalctl 查询
journalctl SYSLOG_FACILITY=16 -t nginx --no-pager

# 查看详细元数据
journalctl SYSLOG_FACILITY=16 -t nginx -n 1 -o json-pretty
```

---

### 9.3 其他开源服务配置示例

#### MySQL 使用 local1

```bash
# /etc/my.cnf
[mysqld]
log-error = syslog:local1
```

**rsyslog 配置**：
```bash
local1.*    /var/log/mysql.log
```

**测试**：
```bash
logger -t mysql -p local1.info "MySQL server started"
logger -t mysql -p local1.warning "Slow query: 5.2 seconds"
logger -t mysql -p local1.err "Connection timeout"
```

---

#### Redis 使用 local4

Redis 配置：
```bash
# /etc/redis/redis.conf
syslog-enabled yes
syslog-ident redis
syslog-facility local4
```

**rsyslog 配置**：
```bash
local4.*    /var/log/redis.log
```

**测试**：
```bash
logger -t redis -p local4.info "Redis server started on port 6379"
logger -t redis -p local4.warning "Memory usage: 85%"
```

---

#### HAProxy 使用 local2

HAProxy 配置：
```bash
# /etc/haproxy/haproxy.cfg
global
    log /dev/log local2 info
```

**rsyslog 配置**：
```bash
local2.*    /var/log/haproxy.log
```

**测试**：
```bash
logger -t haproxy -p local2.info "Backend server1 is UP"
logger -t haproxy -p local2.warning "Backend server2 is DOWN"
```

---

## 📋 第十部分：测试检查清单

完成所有测试后，验证以下内容：

### 10.1 基础知识

- [ ] 理解设施（Facility）的概念和 0-23 的分类
- [ ] 理解优先级（Priority）的概念和 0-7 的分类
- [ ] 理解 `/dev/log → journald → rsyslog` 的流转架构

### 10.2 实际操作

- [ ] 使用 `logger -p <facility>.<priority>` 发送日志
- [ ] 使用 `journalctl -o json-pretty` 查看元数据
- [ ] 查看 rsyslog 日志文件（`/var/log/*.log`）
- [ ] 理解 rsyslog 配置的三个部分（GLOBAL/MODULES/RULES）

### 10.3 规则理解

- [ ] 理解 `facility.*` 的含义
- [ ] 理解 `*.info;mail.none;authpriv.none` 的组合规则
- [ ] 理解 `:omusrmsg:*` 的特殊动作
- [ ] 能够编写自己的 rsyslog 规则

### 10.4 实战配置

- [ ] 配置开源服务（Nginx/MySQL/Redis）使用自定义设施
- [ ] 验证日志正确写入对应的文件
- [ ] 使用 journalctl 按设施和优先级过滤日志

---

## 📖 参考资料

- **rsyslog 官方文档**: https://www.rsyslog.com/doc/
- **RFC 5424**: The Syslog Protocol
- **man 手册**: `man rsyslog.conf`, `man logger`, `man journalctl`

---

## 💡 常见问题

### Q1: 为什么我的日志没有出现在预期的文件中？

**排查步骤**：
1. 检查 rsyslog 配置语法：`rsyslogd -N1`
2. 检查 rsyslog 是否运行：`ps aux | grep rsyslog`
3. 检查日志文件权限
4. 使用 `journalctl -f` 确认日志进入 journal
5. 查看 rsyslog debug 输出（如果以 `-dn` 模式运行）

### Q2: authpriv 和 auth 有什么区别？

- **auth (4)**: 普通认证日志，文件权限较宽（644）
- **authpriv (10)**: 敏感认证日志，文件权限严格（600），包含密码、SSH 密钥等

**建议**：使用 authpriv 更安全。

### Q3: 如何让自定义应用使用指定设施？

**Python 示例**：
```python
import syslog
syslog.openlog('myapp', facility=syslog.LOG_LOCAL0)
syslog.syslog(syslog.LOG_INFO, "Application started")
```

**Shell 脚本**：
```bash
logger -p local0.info -t myapp "Script started"
```

---

## 🎓 学习总结

通过本环境的学习，你应该掌握：

1. **设施分类**：0-23 的设施代码和用途
2. **优先级分类**：0-7 的优先级和严重程度
3. **日志流转**：devlog → journald → rsyslog 的完整流程
4. **rsyslog 配置**：GLOBAL、MODULES、RULES 三部分的含义
5. **规则编写**：掌握 facility.priority 选择器语法
6. **实战应用**：为开源服务配置自定义设施

---

**完成学习后，记得清理环境**：

```bash
# 退出容器
exit

# 停止容器
docker compose down
```
