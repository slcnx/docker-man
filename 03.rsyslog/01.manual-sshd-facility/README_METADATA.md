# 查看 Journal 元数据的完整方法

## 🎯 核心概念

```python
# 你的代码
syslog.syslog("User login successful")

# 自动附加 20+ 个元数据字段
{
    "MESSAGE": "User login successful",  ← 你写的
    "_PID": "123",                       ← 自动
    "_UID": "0",                         ← 自动
    "_COMM": "python3",                  ← 自动
    "_CMDLINE": "python3 app.py",        ← 自动
    "_HOSTNAME": "server01",             ← 自动
    "_SELINUX_CONTEXT": "...",           ← 自动
    ... 还有 15+ 个
}
```

**关键**：你只写消息，系统自动捕获进程、用户、权限、时间等所有信息！

---

## 📋 快速对比

| 查看方式 | 元数据 | 易用性 | 适用场景 |
|---------|--------|--------|---------|
| **rsyslog 文本** | ❌ 丢失 | ⭐⭐⭐⭐⭐ | 传统运维 |
| **journalctl -o verbose** | ✅ 完整 | ⭐⭐⭐⭐ | 命令行排查 |
| **journalctl -o json** | ✅ 完整 | ⭐⭐⭐ | API/脚本 |
| **Cockpit** | ✅ 完整 | ⭐⭐⭐⭐⭐ | Web UI（推荐）|
| **Grafana Loki** | ✅ 完整 | ⭐⭐⭐ | 企业级 |

---

## 🔍 方法 1: 命令行查看（最快）

### 查看完整元数据
```bash
# verbose 格式（最易读）
journalctl -n 1 -o verbose

# 输出示例：
Tue 2025-10-07 06:33:53
    _UID=0
    _GID=0
    _COMM=logger
    _EXE=/usr/bin/logger
    _CMDLINE=logger -t MyApp "User alice logged in"
    MESSAGE=User alice logged in from 192.168.1.100
```

### JSON 格式（结构化）
```bash
journalctl -n 1 -o json-pretty
```

### 提取特定字段
```bash
# 使用 jq
journalctl -n 10 -o json | jq '._PID, ._UID, .MESSAGE'

# 输出：
"414"
"0"
"User alice logged in"
```

---

## 🏷️ 方法 2: 基于元数据查询（类似 Prometheus）

### Prometheus 风格

```bash
# Prometheus (metrics)
http_requests{method="GET", status="200"}
              ↑             ↑
            标签1         标签2

# journalctl (logs)
journalctl _COMM=nginx PRIORITY=3
           ↑              ↑
         元数据1        元数据2
```

### 实战查询

#### 按进程查询
```bash
journalctl _COMM=nginx          # 所有 nginx 日志
journalctl _COMM=sshd           # 所有 sshd 日志
```

#### 按用户查询
```bash
journalctl _UID=0               # root 用户
journalctl _UID=1000            # 普通用户
```

#### 按优先级查询
```bash
journalctl PRIORITY=3           # 错误级别
journalctl PRIORITY=0..3        # 0-3 级（紧急到错误）
journalctl -p err               # 等价写法
```

#### 按程序标识查询
```bash
journalctl SYSLOG_IDENTIFIER=MyApp
```

#### 组合查询
```bash
# nginx 的错误日志
journalctl _COMM=nginx PRIORITY=3

# root 用户的 MyApp 日志
journalctl _UID=0 SYSLOG_IDENTIFIER=MyApp

# 最近 1 小时的 sshd 错误
journalctl _COMM=sshd PRIORITY=3 --since "1 hour ago"
```

#### 统计查询
```bash
# 统计每个进程的日志数量
journalctl -o json --since today | \
  jq -r '._COMM' | sort | uniq -c | sort -rn

# 输出：
#   1523 nginx
#    876 sshd
#    234 cron
```

---

## 🌐 方法 3: Web UI 查看（最直观）

### 选项 A: Cockpit（推荐 - 开箱即用）

#### 安装
```bash
yum install cockpit cockpit-system
systemctl enable --now cockpit.socket
```

#### 访问
```
https://your-server:9090
→ Logs 菜单
```

#### 功能
- ✅ 实时日志流
- ✅ 按优先级过滤
- ✅ 按服务过滤
- ✅ 按时间范围查询
- ✅ 点击展开查看完整元数据

---

### 选项 B: 自定义 Web 查看器

#### 使用本项目提供的 Python 脚本
```bash
# 在宿主机运行
python3 journal-viewer.py

# 访问
http://localhost:8080
```

#### 功能
- ✅ 类似 Prometheus 的界面
- ✅ 按元数据过滤（_COMM, _UID, PRIORITY）
- ✅ 自动刷新
- ✅ 展示所有元数据字段

---

### 选项 C: Grafana Loki（企业级）

#### 架构
```
应用 → journald → promtail → Loki → Grafana
```

#### promtail 配置
```yaml
# /etc/promtail/config.yml
scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd-journal
    relabel_configs:
      - source_labels: ['__journal__comm']
        target_label: 'comm'
      - source_labels: ['__journal_priority']
        target_label: 'priority'
```

#### Grafana 查询
```logql
# 类似 Prometheus
{comm="nginx"} |= "error"
rate({comm="nginx"}[5m])
```

---

## 📊 元数据字段完整列表

### 进程信息（6 个字段）
```
_PID          进程 ID
_UID          用户 ID
_GID          组 ID
_COMM         命令名
_EXE          可执行文件路径
_CMDLINE      完整命令行
```

### 系统信息（5 个字段）
```
_HOSTNAME     主机名
_MACHINE_ID   机器唯一 ID
_BOOT_ID      本次启动 ID
_RUNTIME_SCOPE 运行范围
_TRANSPORT    传输方式
```

### 安全信息（4 个字段）
```
_SELINUX_CONTEXT  SELinux 上下文
_CAP_EFFECTIVE    进程能力集
_AUDIT_SESSION    审计会话 ID
_AUDIT_LOGINUID   审计登录 UID
```

### 日志元信息（5 个字段）
```
MESSAGE            消息正文
PRIORITY           优先级（0-7）
SYSLOG_IDENTIFIER  程序标识
SYSLOG_FACILITY    日志设施
SYSLOG_TIMESTAMP   原始时间戳
```

### 时间戳（3 个字段）
```
__REALTIME_TIMESTAMP        真实时间戳（微秒）
__MONOTONIC_TIMESTAMP       单调时间戳
_SOURCE_REALTIME_TIMESTAMP  生成时间戳
```

---

## 💡 实战场景

### 场景 1: 安全审计
```bash
# 查找所有 root 执行的删除操作
journalctl _UID=0 _COMM=rm --since "1 week ago" -o json-pretty

# 查看完整命令行
journalctl _UID=0 _COMM=rm -o json | jq '._CMDLINE'
```

### 场景 2: 性能分析
```bash
# 找出日志最多的进程（可能异常）
journalctl -o json --since today | \
  jq -r '._COMM' | sort | uniq -c | sort -rn | head -10
```

### 场景 3: 故障排查
```bash
# nginx 最近的错误日志 + 完整元数据
journalctl _COMM=nginx PRIORITY=3 -n 10 -o verbose

# 查看具体是哪个进程 PID
journalctl _COMM=nginx PRIORITY=3 -o json | jq '._PID'
```

### 场景 4: 入侵检测
```bash
# 查找异常 SELinux 上下文
journalctl -o json --since "1 day ago" | \
  jq -r 'select(._SELINUX_CONTEXT != "system_u:system_r:init_t:s0")'
```

---

## 📈 对比：文本日志 vs 元数据日志

### 文本日志（rsyslog）
```bash
$ tail /var/log/messages
Oct 7 06:33:53 server MyApp[414]: User alice logged in
                ↑      ↑     ↑    ↑
             主机名   标识  PID  消息

# 只能用 grep 查找
grep "MyApp" /var/log/messages
grep "alice" /var/log/messages
```

**元数据**：4 个字段（时间、主机、标识、消息）

---

### 元数据日志（journal）
```bash
$ journalctl -n 1 -o json-pretty
{
  "MESSAGE": "User alice logged in",
  "_PID": "414",
  "_UID": "0",              ← 自动
  "_COMM": "logger",        ← 自动
  "_EXE": "/usr/bin/logger",← 自动
  "_CMDLINE": "logger ...", ← 自动
  "_HOSTNAME": "server",    ← 自动
  "_SELINUX_CONTEXT": "...",← 自动
  ... 20+ 字段
}

# 结构化查询（类似 SQL）
journalctl _COMM=logger _UID=0 SYSLOG_IDENTIFIER=MyApp
```

**元数据**：20+ 个字段（全部自动捕获）

---

## 🎓 总结

### 元数据自动捕获的价值

| 能力 | 文本日志 | 元数据日志 |
|------|---------|-----------|
| **字段数量** | 4 个 | 20+ 个 |
| **查询方式** | grep（线性扫描） | 索引查询 |
| **过滤能力** | 文本匹配 | 结构化过滤 |
| **审计** | 有限 | 完整（UID/PID/命令行）|
| **性能分析** | 困难 | 简单（统计、聚合） |
| **Web UI** | 无 | 多种选择 |

### 推荐方案

- **命令行**：`journalctl -o json-pretty`（快速排查）
- **Web UI**：Cockpit（简单易用）
- **企业级**：Grafana Loki（分布式、告警）

### 核心优势

1. **自动化**：无需程序额外添加元数据
2. **标准化**：所有程序统一字段
3. **强查询**：类似 Prometheus 的标签查询
4. **可视化**：多种 Web UI 方案

**类比**：
```
journal 元数据 = Prometheus 标签
journalctl 查询 = PromQL
```

投递到 `/dev/log`，系统自动附加 20+ 个元数据，比手动日志记录强大得多！
