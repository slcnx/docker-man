# Logrotate 手工测试环境

## 📚 第一部分：基础知识

### 1.1 什么是 Logrotate

Logrotate 是 Linux 系统中用于**自动轮转、压缩、删除和邮件发送日志文件**的工具，防止日志文件无限增长导致磁盘空间耗尽。

#### 核心概念

| 概念 | 说明 | 示例 |
|------|------|------|
| **轮转（Rotate）** | 将当前日志文件重命名，创建新的空日志文件 | `app.log` → `app.log.1` |
| **压缩（Compress）** | 压缩旧日志文件以节省空间 | `app.log.1` → `app.log.1.gz` |
| **删除（Delete）** | 删除过期的旧日志文件 | 删除 `app.log.30.gz` |
| **保留数量（Rotate）** | 保留多少个旧日志文件 | `rotate 7` = 保留 7 个 |

---

### 1.2 Logrotate 工作原理

```
日志文件增长
    ↓
定时任务（cron）触发 logrotate
    ↓
检查轮转条件（大小/时间）
    ↓
执行轮转操作：
    1. 运行 prerotate 脚本（可选）
    2. 重命名日志文件（app.log → app.log.1）
    3. 创建新的空日志文件
    4. 通知应用重新打开日志文件（postrotate）
    5. 压缩旧日志文件（可选）
    6. 删除过期日志文件
```

---

### 1.3 Logrotate 配置文件位置

| 文件/目录 | 说明 | 用途 |
|----------|------|------|
| `/etc/logrotate.conf` | 主配置文件 | 全局默认设置 |
| `/etc/logrotate.d/` | 配置目录 | 各应用的独立配置 |
| `/var/lib/logrotate/logrotate.status` | 状态文件 | 记录上次轮转时间 |

---

## 🚀 第二部分：启动环境

### 2.1 启动容器

```bash
cd /root/docker-man/04.manual-logrotate
docker compose up -d
```

### 2.2 进入容器

```bash
docker exec -it logrotate-test bash
```

### 2.3 检查 logrotate 安装

```bash
# 检查 logrotate 版本
logrotate --version

# 查看主配置文件
cat /etc/logrotate.conf

# 查看应用配置目录
ls -la /etc/logrotate.d/
```

---

## 📐 第三部分：Logrotate 配置详解

### 3.1 基本配置结构

```
/path/to/logfile {
    # 轮转频率
    daily | weekly | monthly | yearly

    # 保留数量
    rotate 7

    # 压缩选项
    compress
    delaycompress

    # 文件处理
    missingok
    notifempty
    create 0644 user group

    # 执行脚本
    prerotate
        # 轮转前执行的命令
    endscript

    postrotate
        # 轮转后执行的命令
    endscript
}
```

---

### 3.2 常用配置指令

#### 轮转时间

| 指令 | 说明 | 示例 |
|------|------|------|
| `daily` | 每天轮转 | 适合高流量日志 |
| `weekly` | 每周轮转 | 适合中等流量日志 |
| `monthly` | 每月轮转 | 适合低流量日志 |
| `yearly` | 每年轮转 | 适合归档日志 |
| `size` | 按大小轮转 | `size 100M` = 超过 100MB 轮转 |

#### 轮转数量

| 指令 | 说明 | 示例 |
|------|------|------|
| `rotate N` | 保留 N 个旧日志 | `rotate 7` = 保留 7 个 |
| `maxage N` | 删除 N 天前的日志 | `maxage 30` = 删除 30 天前 |

#### 压缩选项

| 指令 | 说明 | 示例 |
|------|------|------|
| `compress` | 启用压缩 | 使用 gzip 压缩 |
| `nocompress` | 不压缩 | 保留原始文件 |
| `delaycompress` | 延迟压缩 | 下次轮转时才压缩 |
| `compresscmd` | 指定压缩命令 | `compresscmd /usr/bin/bzip2` |
| `compressext` | 压缩文件扩展名 | `compressext .bz2` |
| `compressoptions` | 压缩选项 | `compressoptions -9` = 最大压缩 |

#### 文件处理

| 指令 | 说明 | 作用 |
|------|------|------|
| `create mode owner group` | 创建新日志文件 | `create 0644 root root` |
| `nocreate` | 不创建新文件 | 应用自己创建 |
| `copytruncate` | 复制并截断 | 不重命名，适合无法重新打开的应用 |
| `missingok` | 文件不存在不报错 | 避免 cron 发送错误邮件 |
| `nomissingok` | 文件不存在报错 | 默认行为 |
| `notifempty` | 空文件不轮转 | 避免生成空的旧日志 |
| `ifempty` | 空文件也轮转 | 默认行为 |
| `sharedscripts` | 脚本只运行一次 | 多个日志文件共享 postrotate |

#### 脚本执行

| 指令 | 说明 | 典型用途 |
|------|------|---------|
| `prerotate` ... `endscript` | 轮转前执行 | 停止服务 |
| `postrotate` ... `endscript` | 轮转后执行 | 通知服务重新打开日志 |
| `firstaction` ... `endscript` | 第一次轮转前 | 初始化操作 |
| `lastaction` ... `endscript` | 最后一次轮转后 | 清理操作 |

---

### 3.3 实际配置示例

#### 示例 1：Web 应用日志

```
/var/log/webapp/*.log {
    daily                    # 每天轮转
    rotate 7                 # 保留 7 天
    compress                 # 启用压缩
    delaycompress            # 延迟压缩（保留最新的 .1 文件不压缩）
    missingok                # 文件不存在不报错
    notifempty               # 空文件不轮转
    create 0644 www-data www-data  # 创建新文件，权限 644，所有者 www-data
    sharedscripts            # 多个日志文件共享 postrotate
    postrotate
        # 通知应用重新打开日志文件
        /usr/bin/killall -SIGUSR1 webapp
    endscript
}
```

#### 示例 2：Nginx 日志

```
/var/log/nginx/*.log {
    daily
    rotate 14                # 保留 14 天
    compress
    delaycompress
    missingok
    notifempty
    create 0640 nginx adm
    sharedscripts
    postrotate
        # 通知 Nginx 重新打开日志文件
        [ -f /var/run/nginx.pid ] && kill -USR1 `cat /var/run/nginx.pid`
    endscript
}
```

#### 示例 3：按大小轮转

```
/var/log/myapp/app.log {
    size 100M                # 超过 100MB 轮转
    rotate 5                 # 保留 5 个
    compress
    missingok
    notifempty
    create 0644 myapp myapp
    postrotate
        /usr/bin/systemctl reload myapp
    endscript
}
```

#### 示例 4：使用 copytruncate（应用无法重新打开日志）

```
/var/log/java-app/app.log {
    daily
    rotate 7
    compress
    delaycompress
    copytruncate             # 复制后截断（不重命名）
    missingok
    notifempty
}
```

**copytruncate 说明**：
- 适用于无法接收信号重新打开日志的应用（如某些 Java 应用）
- 缺点：轮转期间可能丢失少量日志

---

## 🧪 第四部分：手工测试 Logrotate

### 4.1 创建测试日志文件

在容器内执行：

```bash
# 创建测试目录
mkdir -p /var/log/test-app

# 生成测试日志
for i in {1..1000}; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Test log entry $i" >> /var/log/test-app/app.log
done

# 查看文件大小
ls -lh /var/log/test-app/app.log
```

---

### 4.2 创建 Logrotate 配置

```bash
cat > /etc/logrotate.d/test-app <<'EOF'
/var/log/test-app/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    postrotate
        echo "Logrotate executed at $(date)" >> /var/log/test-app/rotate.log
    endscript
}
EOF
```

---

### 4.3 测试配置语法

```bash
# 测试配置文件语法
logrotate -d /etc/logrotate.d/test-app

# 输出：显示详细的执行计划（不实际执行）
```

**关键输出**：
- `reading config file /etc/logrotate.d/test-app`
- `Handling 1 logs`
- `log needs rotating` 或 `log does not need rotating`

---

### 4.4 手动执行轮转（强制）

```bash
# 强制执行轮转（忽略时间条件）
logrotate -f /etc/logrotate.d/test-app

# 查看结果
ls -lh /var/log/test-app/
```

**预期结果**：
```
app.log          # 新的空文件
app.log.1        # 重命名的旧文件（未压缩，因为 delaycompress）
rotate.log       # postrotate 脚本生成的日志
```

---

### 4.5 再次生成日志并轮转

```bash
# 生成新日志
for i in {1..500}; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] New log entry $i" >> /var/log/test-app/app.log
done

# 再次强制轮转
logrotate -f /etc/logrotate.d/test-app

# 查看结果
ls -lh /var/log/test-app/
```

**预期结果**：
```
app.log          # 新的空文件
app.log.1        # 第二次轮转的文件（未压缩）
app.log.2.gz     # 第一次轮转的文件（已压缩）
rotate.log       # postrotate 日志
```

---

### 4.6 查看压缩后的日志

```bash
# 解压查看
zcat /var/log/test-app/app.log.2.gz | head -10

# 或使用 zgrep 搜索
zgrep "Test log entry" /var/log/test-app/app.log.2.gz
```

---

## 🔍 第五部分：Logrotate 状态文件

### 5.1 查看状态文件

```bash
cat /var/lib/logrotate/logrotate.status
```

**输出示例**：
```
"/var/log/test-app/app.log" 2024-10-7-14:30:0
"/var/log/yum.log" 2024-10-1-0:0:0
"/var/log/messages" 2024-10-7-0:0:0
```

**说明**：记录每个日志文件的最后轮转时间。

---

### 5.2 手动修改状态文件（测试用）

```bash
# 修改时间为过去（触发轮转）
sed -i 's/2024-10-7/2024-09-1/' /var/lib/logrotate/logrotate.status

# 查看修改结果
grep test-app /var/lib/logrotate/logrotate.status

# 不使用 -f，logrotate 会根据 daily 判断是否需要轮转
logrotate /etc/logrotate.d/test-app
```

---

## 🛠️ 第六部分：常见应用配置

### 6.1 Rsyslog 日志

```bash
cat > /etc/logrotate.d/rsyslog <<'EOF'
/var/log/messages
/var/log/secure
/var/log/maillog
/var/log/cron
{
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        /bin/kill -HUP `cat /var/run/rsyslogd.pid 2> /dev/null` 2> /dev/null || true
    endscript
}
EOF
```

**说明**：
- `rotate 30`: 保留 30 天
- `postrotate`: 发送 HUP 信号给 rsyslog，让其重新打开日志文件

---

### 6.2 Apache/Nginx 日志

```bash
cat > /etc/logrotate.d/nginx <<'EOF'
/var/log/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 nginx adm
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 `cat /var/run/nginx.pid`
    endscript
}
EOF
```

---

### 6.3 MySQL 日志

```bash
cat > /etc/logrotate.d/mysql <<'EOF'
/var/log/mysql/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 mysql mysql
    sharedscripts
    postrotate
        /usr/bin/mysqladmin flush-logs
    endscript
}
EOF
```

---

## 📊 第七部分：Cron 自动化

### 7.1 查看 Cron 任务

Logrotate 通常由 cron 定时任务触发：

```bash
# 查看 cron 配置
cat /etc/cron.daily/logrotate
```

**典型内容**：
```bash
#!/bin/sh
/usr/sbin/logrotate /etc/logrotate.conf
```

**说明**：
- 位于 `/etc/cron.daily/` 表示每天执行一次
- 执行时间由 `anacron` 或 `cron` 决定（通常在凌晨）

---

### 7.2 查看 Cron 执行时间

```bash
# 查看 anacron 配置（Rocky Linux/CentOS）
cat /etc/anacrontab

# 查看 cron.daily 执行时间
grep RANDOM_DELAY /etc/anacrontab
```

**输出示例**：
```
RANDOM_DELAY=45          # 随机延迟 0-45 分钟
START_HOURS_RANGE=3-22   # 3:00-22:00 之间执行
1       5       cron.daily    nice run-parts /etc/cron.daily
```

---

### 7.3 手动模拟 Cron 执行

```bash
# 以 cron 的方式运行 logrotate
/etc/cron.daily/logrotate

# 查看执行结果
echo $?   # 0 表示成功
```

---

## 🔧 第八部分：调试和故障排查

### 8.1 调试模式（不实际执行）

```bash
# -d: debug 模式，显示详细信息但不实际执行
logrotate -d /etc/logrotate.conf

# 针对特定配置文件
logrotate -d /etc/logrotate.d/test-app
```

**输出解读**：
- `reading config file`: 读取配置
- `log does not need rotating`: 不需要轮转（时间未到）
- `log needs rotating`: 需要轮转
- `rotating pattern`: 显示匹配的文件

---

### 8.2 强制执行（忽略时间）

```bash
# -f: force 强制执行，忽略时间条件
logrotate -f /etc/logrotate.conf

# 针对特定配置
logrotate -f /etc/logrotate.d/test-app
```

---

### 8.3 详细输出

```bash
# -v: verbose 详细输出
logrotate -v /etc/logrotate.conf

# 结合强制执行
logrotate -fv /etc/logrotate.d/test-app
```

---

### 8.4 常见错误

#### 错误 1：权限问题

```
error: skipping "/var/log/app.log" because parent directory has insecure permissions
```

**解决**：
```bash
chmod 755 /var/log
chmod 644 /var/log/app.log
```

---

#### 错误 2：配置语法错误

```
error: /etc/logrotate.d/test-app:5 unexpected text
```

**解决**：检查语法，确保 `{` 和 `}` 配对，指令拼写正确。

---

#### 错误 3：postrotate 脚本失败

```
error: error running non-shared postrotate script for /var/log/app.log
```

**解决**：
- 检查脚本是否有执行权限
- 检查脚本语法是否正确
- 使用 `set -x` 调试脚本

---

## 📋 第九部分：最佳实践

### 9.1 配置建议

1. **使用 missingok**：避免文件不存在时报错
2. **使用 notifempty**：避免轮转空文件
3. **使用 delaycompress**：保留最新的 `.1` 文件不压缩，便于查看
4. **使用 sharedscripts**：多个日志共享 postrotate，避免重复执行
5. **create 指定权限**：确保新文件权限正确

---

### 9.2 安全建议

1. **日志文件权限**：敏感日志使用 `0600` 或 `0640`
2. **目录权限**：日志目录使用 `0755`
3. **所有者**：使用应用的专用用户（如 `nginx`、`mysql`）
4. **避免 copytruncate**：优先使用信号通知应用重新打开日志

---

### 9.3 性能建议

1. **按大小轮转**：高流量应用使用 `size` 而非 `daily`
2. **异步压缩**：使用 `delaycompress` 避免轮转时 CPU 峰值
3. **分散轮转时间**：不同应用使用不同的 cron 时间（hourly/daily/weekly）

---

## 📖 第十部分：与 Journal 对比

| 特性 | Logrotate | systemd-journald |
|------|-----------|------------------|
| **管理对象** | 文本日志文件 | 二进制 journal 文件 |
| **触发方式** | Cron 定时任务 | 实时自动管理 |
| **配置方式** | `/etc/logrotate.d/` | `/etc/systemd/journald.conf` |
| **轮转条件** | 时间/大小 | SystemMaxUse / SystemKeepFree |
| **压缩** | 手动配置（gzip/bzip2） | 自动管理 |
| **适用场景** | 应用文本日志 | 系统服务日志 |

**总结**：
- **Logrotate**：管理应用的**文本日志文件**
- **Journal**：管理 systemd 的**二进制日志**

两者互补，通常同时使用。

---

## 🎓 学习总结

通过本环境的学习，你应该掌握：

1. **基本概念**：轮转、压缩、删除、保留数量
2. **配置语法**：daily/weekly、rotate、compress、create 等指令
3. **脚本钩子**：prerotate、postrotate 的使用
4. **调试方法**：`-d`（debug）、`-f`（force）、`-v`（verbose）
5. **实战配置**：Nginx、Rsyslog、MySQL 等常见应用
6. **故障排查**：权限问题、语法错误、脚本失败

---

## 🔗 参考资料

- **man 手册**: `man logrotate`
- **主配置文件**: `/etc/logrotate.conf`
- **示例配置**: `/etc/logrotate.d/*`

---

**完成学习后，记得清理环境**：

```bash
# 退出容器
exit

# 停止容器
docker compose down
```
