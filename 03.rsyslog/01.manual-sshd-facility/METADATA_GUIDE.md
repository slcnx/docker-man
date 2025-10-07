# Journal 元数据完整指南

## 📊 对比：文本日志 vs 结构化日志

### rsyslog 文本日志（丢失元数据）
```bash
$ tail /var/log/messages
Oct  7 06:33:53 9821ebe294f6 MyApp[414]: User alice logged in from 192.168.1.100
                  ↑          ↑     ↑    ↑
                主机名      标识  PID  消息
```

**只有 4 个字段**：时间戳、主机名、程序标识[PID]、消息

---

### journal 结构化日志（完整元数据）
```bash
$ journalctl -n 1 -o json-pretty
{
    "MESSAGE": "User alice logged in from 192.168.1.100",
    "_PID": "414",
    "_UID": "0",
    "_GID": "0",
    "_COMM": "logger",
    "_EXE": "/usr/bin/logger",
    "_CMDLINE": "logger -t MyApp \"User alice...\"",
    "_HOSTNAME": "9821ebe294f6",
    "_MACHINE_ID": "e4afc1133390402090d5bafc57d014ce",
    "_BOOT_ID": "2375c59081b64356af0bd45a658cca2c",
    "_RUNTIME_SCOPE": "system",
    "_TRANSPORT": "syslog",
    "_SELINUX_CONTEXT": "docker-default (enforce)",
    "_CAP_EFFECTIVE": "a80425fb",
    "SYSLOG_IDENTIFIER": "MyApp",
    "SYSLOG_FACILITY": "1",
    "SYSLOG_TIMESTAMP": "Oct  7 06:33:53 ",
    "PRIORITY": "5",
    "__REALTIME_TIMESTAMP": "1759818833232116",
    "__MONOTONIC_TIMESTAMP": "5538497510",
    "__CURSOR": "s=a62c0e0925ea44cd...",
    "_SOURCE_REALTIME_TIMESTAMP": "1759818833231989"
}
```

**20+ 个字段**，全部自动附加！

---

## 🏷️ 完整元数据字段列表

### 1. **进程信息**（自动捕获）

| 字段 | 说明 | 示例 |
|------|------|------|
| `_PID` | 进程 ID | `414` |
| `_UID` | 用户 ID | `0` (root) |
| `_GID` | 组 ID | `0` (root) |
| `_COMM` | 命令名（截断至 15 字符）| `logger` |
| `_EXE` | 可执行文件完整路径 | `/usr/bin/logger` |
| `_CMDLINE` | 完整命令行 | `logger -t MyApp "User..."` |

**价值**：
- 追溯日志来源
- 审计用户行为（UID）
- 调试进程问题

---

### 2. **系统信息**（自动捕获）

| 字段 | 说明 | 示例 |
|------|------|------|
| `_HOSTNAME` | 主机名 | `9821ebe294f6` |
| `_MACHINE_ID` | 机器唯一 ID | `e4afc1133390402...` |
| `_BOOT_ID` | 本次启动会话 ID | `2375c59081b643...` |
| `_RUNTIME_SCOPE` | 运行范围 | `system` |
| `_TRANSPORT` | 传输方式 | `syslog`/`journal`/`stdout` |

**价值**：
- 区分不同机器的日志（分布式环境）
- 追溯重启前后的日志
- 识别日志来源方式

---

### 3. **安全信息**（自动捕获）

| 字段 | 说明 | 示例 |
|------|------|------|
| `_SELINUX_CONTEXT` | SELinux 上下文 | `docker-default (enforce)` |
| `_CAP_EFFECTIVE` | 进程有效能力集 | `a80425fb` |
| `_AUDIT_SESSION` | 审计会话 ID | `123` |
| `_AUDIT_LOGINUID` | 审计登录 UID | `1000` |

**价值**：
- 安全审计
- 权限问题排查
- 入侵检测

---

### 4. **日志元信息**（自动附加）

| 字段 | 说明 | 示例 |
|------|------|------|
| `MESSAGE` | 日志消息正文 | `User alice logged in...` |
| `PRIORITY` | 优先级（0-7） | `5` (notice) |
| `SYSLOG_IDENTIFIER` | 程序标识符 | `MyApp` |
| `SYSLOG_FACILITY` | 日志设施（0-23） | `1` (user) |
| `SYSLOG_TIMESTAMP` | syslog 原始时间戳 | `Oct  7 06:33:53` |

---

### 5. **时间戳**（多种精度）

| 字段 | 说明 | 精度 |
|------|------|------|
| `__REALTIME_TIMESTAMP` | 真实时间戳 | 微秒 |
| `__MONOTONIC_TIMESTAMP` | 单调时间戳（自启动） | 微秒 |
| `_SOURCE_REALTIME_TIMESTAMP` | 日志生成时间 | 微秒 |

---

### 6. **systemd 服务信息**（如果是 systemd 服务）

| 字段 | 说明 | 示例 |
|------|------|------|
| `_SYSTEMD_UNIT` | systemd 单元名 | `nginx.service` |
| `_SYSTEMD_SLICE` | systemd slice | `system.slice` |
| `_SYSTEMD_CGROUP` | cgroup 路径 | `/system.slice/nginx.service` |

---

## 🔍 查看元数据的 4 种方法

### 方法 1: verbose 格式（最易读）
```bash
journalctl -n 1 -o verbose
```

**输出**：
```
_UID=0
_GID=0
_COMM=logger
MESSAGE=User alice logged in
...
```

---

### 方法 2: JSON 格式（最结构化）
```bash
journalctl -n 1 -o json-pretty
```

**输出**：
```json
{
  "_UID": "0",
  "_GID": "0",
  "MESSAGE": "User alice logged in",
  ...
}
```

**用途**：API 集成、脚本处理

---

### 方法 3: export 格式（二进制导出）
```bash
journalctl -n 10 -o export > logs.export
```

**用途**：备份、迁移到其他系统

---

### 方法 4: 查看特定字段
```bash
journalctl -n 10 -o json | jq '._PID, ._UID, .MESSAGE'
```

**输出**：
```
"414"
"0"
"User alice logged in"
```

---

## 🏷️ 基于元数据的查询（类似 Prometheus）

### Prometheus 风格查询对比

#### Prometheus (metrics)
```promql
http_requests_total{method="GET", status="200"}
                    ↑          ↑         ↑
                  标签1      标签2     标签3
```

#### journalctl (logs)
```bash
journalctl _COMM=nginx PRIORITY=3
           ↑              ↑
         元数据1        元数据2
```

---

### 实战查询示例

#### 1. **按进程名查询**
```bash
# 所有 nginx 的日志
journalctl _COMM=nginx
```

#### 2. **按用户查询**
```bash
# 所有 root 用户的日志
journalctl _UID=0

# 所有非 root 用户的日志
journalctl _UID=1000
```

#### 3. **按优先级查询**
```bash
# 所有错误级别日志（优先级 0-3）
journalctl PRIORITY=0..3

# 等价于
journalctl -p err
```

#### 4. **按 systemd 服务查询**
```bash
# nginx 服务的所有日志
journalctl -u nginx.service

# 等价于
journalctl _SYSTEMD_UNIT=nginx.service
```

#### 5. **按启动会话查询**
```bash
# 当前启动的所有日志
journalctl -b

# 上次启动的日志
journalctl -b -1

# 指定 BOOT_ID
journalctl _BOOT_ID=2375c59081b64356af0bd45a658cca2c
```

#### 6. **组合查询（AND）**
```bash
# nginx 进程 AND 错误级别
journalctl _COMM=nginx PRIORITY=3

# 特定用户 AND 特定程序
journalctl _UID=0 SYSLOG_IDENTIFIER=MyApp
```

#### 7. **时间范围 + 元数据**
```bash
# 最近 1 小时的 nginx 错误
journalctl _COMM=nginx PRIORITY=3 --since "1 hour ago"

# 2024-01-01 到今天的 sshd 日志
journalctl _COMM=sshd --since "2024-01-01" --until "now"
```

#### 8. **统计查询**
```bash
# 统计每个 _COMM 的日志条数
journalctl -o json --since today | jq -r '._COMM' | sort | uniq -c | sort -rn

# 输出示例：
#   1523 nginx
#    876 sshd
#    234 cron
```

---

## 🌐 Web UI 查看元数据（类似 Prometheus）

### 方案 1: **systemd-journal-gatewayd**（官方轻量）

#### 安装并启动
```bash
yum install systemd-journal-gateway
systemd-journal-gatewayd --port 19531 &
```

#### 访问
```bash
# JSON API
curl http://localhost:19531/entries?_COMM=nginx

# Web 界面（需要额外配置）
curl http://localhost:19531/browse
```

**优点**：
- ✅ 官方支持
- ✅ REST API
- ✅ JSON 输出

**缺点**：
- ❌ UI 简陋
- ❌ 无图表

---

### 方案 2: **Cockpit**（推荐 - 最简单）

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

**功能**：
- ✅ 完整 Web UI
- ✅ 实时日志
- ✅ 元数据过滤
- ✅ 时间范围选择
- ✅ 按优先级、服务、进程过滤

**截图示例**：
```
┌─────────────────────────────────────────┐
│ Logs                             [⚙️]   │
├─────────────────────────────────────────┤
│ Priority: [All ▼]  Since: [1h ▼]       │
│ Service:  [nginx ▼]                     │
├─────────────────────────────────────────┤
│ Oct 7 06:33:53  nginx[123]  ▶️          │
│   MESSAGE: Started nginx                │
│   _PID: 123                             │
│   _UID: 0                               │
│   _COMM: nginx                          │
│   _CMDLINE: /usr/sbin/nginx             │
└─────────────────────────────────────────┘
```

---

### 方案 3: **Grafana Loki**（企业级 - 最强大）

#### 架构
```
应用 → journald → promtail → Loki → Grafana
                     ↑                  ↑
                  采集器            可视化
```

#### 安装 promtail（采集 journal）
```yaml
# /etc/promtail/config.yml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      labels:
        job: systemd-journal
    relabel_configs:
      - source_labels: ['__journal__systemd_unit']
        target_label: 'unit'
      - source_labels: ['__journal__comm']
        target_label: 'comm'
      - source_labels: ['__journal_priority']
        target_label: 'priority'
```

#### Grafana 查询（类似 Prometheus）
```logql
# 所有 nginx 错误日志
{comm="nginx"} |= "error"

# 统计错误率
rate({comm="nginx"} |= "error" [5m])

# 按优先级聚合
sum by (priority) (count_over_time({job="systemd-journal"}[1h]))
```

**效果**：
- ✅ 类似 Prometheus 的查询语法
- ✅ 图表、仪表盘
- ✅ 告警
- ✅ 分布式支持

---

### 方案 4: **journald-web**（简单 Python 工具）

#### 安装
```bash
pip3 install journald-web
```

#### 启动
```bash
journald-web --port 8080
```

#### 访问
```
http://localhost:8080
```

**功能**：
- ✅ 简单 Web UI
- ✅ 搜索过滤
- ✅ 实时日志

**缺点**：
- ⚠️ 非官方
- ⚠️ 功能有限

---

## 📊 元数据价值示例

### 场景 1: 安全审计
```bash
# 查找所有 root 用户执行的危险操作
journalctl _UID=0 _COMM=rm --since "1 week ago"
journalctl _UID=0 _COMM=iptables --since "1 week ago"
```

### 场景 2: 性能分析
```bash
# 找出日志最多的进程（可能有问题）
journalctl -o json --since today | jq -r '._COMM' | sort | uniq -c | sort -rn | head -10
```

### 场景 3: 故障排查
```bash
# 某个服务重启前的最后 100 条日志
journalctl _SYSTEMD_UNIT=nginx.service -n 100 -r
```

### 场景 4: 入侵检测
```bash
# 查找异常 SELinux 上下文的进程
journalctl _SELINUX_CONTEXT="unconfined_t" --since "1 day ago"
```

---

## 💡 总结

### 自动元数据 vs 手动日志

| 方式 | 元数据字段 | 查询能力 | 可视化 |
|------|-----------|---------|--------|
| **文本日志** | 4 个（时间、主机、程序、PID） | grep/awk | ❌ |
| **journal** | 20+ 个（自动捕获） | 结构化查询 | ✅ 多种方案 |

### 最佳实践

1. **开发/测试**：journalctl 命令行足够
2. **小团队**：Cockpit（简单易用）
3. **企业级**：Grafana Loki（分布式、告警）
4. **API 集成**：systemd-journal-gatewayd

### 关键优势

- ✅ **自动化**：无需程序额外添加元数据
- ✅ **标准化**：所有程序统一字段
- ✅ **强查询**：类似数据库的查询能力
- ✅ **可视化**：多种 Web UI 方案

**结论**：journal 的元数据 = Prometheus 的标签，提供了传统文本日志无法比拟的查询和分析能力！
