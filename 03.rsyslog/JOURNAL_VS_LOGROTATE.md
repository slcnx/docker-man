# Journal 日志 vs Logrotate 对比文档

## 概述

**Journal (systemd-journald)** 和 **Logrotate** 是 Linux 系统中两种不同的日志管理机制：

- **Journal**: systemd 的日志管理系统，负责收集、存储和管理系统日志
- **Logrotate**: 传统的日志轮转工具，负责管理文本日志文件的归档和清理

## 核心区别

| 特性 | Journal (journald) | Logrotate |
|------|-------------------|-----------|
| **功能定位** | 日志收集 + 存储 + 查询系统 | 日志轮转 + 归档工具 |
| **存储格式** | 二进制格式（.journal 文件） | 文本格式（.log 文件） |
| **工作方式** | 实时收集和索引日志 | 定期（cron）执行日志轮转 |
| **查询方式** | journalctl 命令（结构化查询） | grep/awk/tail（文本搜索） |
| **日志来源** | 内核、systemd 服务、应用 stdout/stderr | 应用写入的文本日志文件 |
| **配置方式** | /etc/systemd/journald.conf | /etc/logrotate.conf + /etc/logrotate.d/* |

## Journal (systemd-journald)

### 优点

1. **结构化存储**
   - 日志以键值对形式存储，包含丰富的元数据
   - 支持按字段精确查询：进程ID、用户、单元、优先级等
   ```bash
   journalctl _PID=1234
   journalctl _SYSTEMD_UNIT=sshd.service
   journalctl PRIORITY=3
   journalctl _SELINUX_CONTEXT="unconfined_t" --since "1 day ago"
   ```

2. **实时索引**
   - 自动建立索引，查询速度快
   - 支持时间范围、正则表达式、字段过滤等复杂查询

3. **自动轮转**
   - 自动管理磁盘空间（SystemMaxUse、SystemKeepFree）
   - 无需 cron 任务，实时监控并轮转

4. **数据完整性**
   - 支持 Forward Secure Sealing (FSS) 加密
   - 二进制格式防篡改，带校验和

5. **统一接口**
   - 收集所有来源的日志（内核、systemd、应用）
   - 统一的 journalctl 查询接口

### 缺点

1. **二进制格式**
   - 无法直接用 cat/grep 查看
   - 需要 journalctl 工具，学习曲线较陡

2. **不便于传输**
   - 二进制文件不适合直接传输到远程日志服务器
   - 通常需要配合 rsyslog 转发

3. **存储空间**
   - 二进制格式可能比压缩的文本日志占用更多空间
   - 元数据增加存储开销

4. **兼容性问题**
   - 传统应用可能不适配 systemd journal
   - 某些监控工具需要文本日志

5. **持久化配置**
   - 默认不持久化（需手动创建 /var/log/journal）
   - 配置相对复杂

## Logrotate

### 优点

1. **灵活的轮转策略**
   - 支持多种轮转条件：大小、时间（daily/weekly/monthly）
   - 可自定义压缩、删除、归档策略
   ```
   /var/log/myapp/*.log {
       daily
       rotate 7
       compress
       delaycompress
       missingok
       notifempty
       create 0644 root root
   }
   ```

2. **文本格式**
   - 易于阅读和处理（cat、grep、awk、tail）
   - 方便调试和临时查看

3. **广泛兼容**
   - 几乎所有应用都支持文本日志
   - 历史悠久，成熟稳定

4. **远程传输友好**
   - 文本文件易于 scp、rsync 传输
   - 压缩后占用空间小

5. **精细控制**
   - 可以针对每个日志文件独立配置
   - 支持轮转前后执行自定义脚本（prerotate/postrotate）

### 缺点

1. **缺乏结构化**
   - 纯文本，缺少元数据
   - 查询需要依赖 grep 等工具，效率低

2. **依赖 Cron**
   - 定期执行，不是实时的
   - 可能在大日志文件轮转时造成性能影响

3. **无自动索引**
   - 大文件查询慢
   - 需要手动构建索引或使用外部工具

4. **配置复杂**
   - 需要为每个应用编写配置
   - 容易出现配置错误（如权限、路径问题）

5. **缺少完整性保护**
   - 文本文件易被篡改
   - 无内置加密或签名机制

## 使用场景

### 适合使用 Journal 的场景

- **系统服务日志**: systemd 管理的服务（sshd、nginx、mysql 等）
- **故障排查**: 需要按时间、进程、优先级等精确查询
- **审计日志**: 需要防篡改和完整性保护
- **开发测试**: 实时查看应用 stdout/stderr 输出

### 适合使用 Logrotate 的场景

- **应用日志文件**: Web 应用、数据库、中间件的文本日志
- **长期归档**: 需要压缩并保存多年的日志
- **远程传输**: 需要定期传输到其他服务器
- **传统环境**: 没有 systemd 的系统（如旧版本 CentOS/RHEL）

## 最佳实践：结合使用

实际生产环境中，通常**结合使用**两者：

```
应用/服务
    ↓
systemd-journald (实时收集 + 结构化存储)
    ↓
rsyslog (转发到文件)
    ↓
logrotate (轮转 + 归档 + 压缩)
    ↓
远程日志服务器 / 备份存储
```

### 典型配置示例

1. **journald 配置** (`/etc/systemd/journald.conf`):
   ```ini
   [Journal]
   Storage=persistent
   SystemMaxUse=2G
   ForwardToSyslog=yes
   ```

2. **rsyslog 配置** (`/etc/rsyslog.conf`):
   ```
   module(load="imjournal")
   *.* /var/log/messages
   ```

3. **logrotate 配置** (`/etc/logrotate.d/rsyslog`):
   ```
   /var/log/messages {
       daily
       rotate 30
       compress
       delaycompress
       postrotate
           /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
       endscript
   }
   ```

## 总结

- **Journal**: 现代化的实时日志系统，适合结构化查询和系统服务日志
- **Logrotate**: 经典的日志轮转工具，适合文本日志的归档管理

两者并非互斥关系，而是**互补关系**：
- Journal 负责**实时收集和查询**
- Logrotate 负责**长期存储和归档**

在 systemd 时代，推荐使用 **Journal → Rsyslog → Logrotate** 的完整日志链路。
