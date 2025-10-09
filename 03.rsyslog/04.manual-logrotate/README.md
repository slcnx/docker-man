# Logrotate 手工测试环境

## 🚀 快速开始

### 1. 构建并启动容器

```bash
cd /root/docker-man/04.manual-logrotate
docker compose up -d
```

### 2. 进入容器

```bash
docker exec -it logrotate-test bash
```

### 3. 创建测试日志

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

### 4. 测试 logrotate 配置

```bash
# 测试配置语法（不实际执行）
logrotate -d /etc/logrotate.d/test-app

# 强制执行轮转
logrotate -f /etc/logrotate.d/test-app

# 查看轮转结果
ls -lh /var/log/test-app/
```

### 5. 查看轮转后的日志

```bash
# 查看当前日志
cat /var/log/test-app/app.log

# 查看旧日志（未压缩）
cat /var/log/test-app/app.log.1

# 查看压缩后的日志
zcat /var/log/test-app/app.log.2.gz | head
```

### 6. 停止容器

```bash
docker compose down
```

---

## 📚 文档

详细文档请查看 [compose.md](./compose.md)

---

## 🏗️ 架构说明

本环境使用以下组件：

```
容器启动流程：
  1. systemd-journald (后台) - 日志收集
  2. 创建 /dev/log 链接
  3. rsyslogd (后台) - 生成系统日志
  4. tail -f /dev/null - 保持容器运行

日志轮转流程：
  应用日志文件 → logrotate → 重命名 → 压缩 → 删除旧文件
```

---

## 📋 测试内容

### 基础测试

1. **配置语法测试** - 使用 `-d` 参数测试配置
2. **强制轮转** - 使用 `-f` 参数强制执行
3. **压缩测试** - 验证 gzip 压缩功能
4. **延迟压缩** - 验证 delaycompress 功能
5. **状态文件** - 查看 `/var/lib/logrotate/logrotate.status`

### 进阶测试

1. **按大小轮转** - 配置 `size 100M` 测试
2. **按时间轮转** - 配置 `daily/weekly/monthly` 测试
3. **postrotate 脚本** - 测试轮转后执行脚本
4. **copytruncate** - 测试复制截断模式
5. **多文件轮转** - 使用通配符 `*.log` 测试

---

## 🎯 学习目标

- ✅ 理解 logrotate 的工作原理
- ✅ 掌握 logrotate 配置语法
- ✅ 理解轮转、压缩、删除的机制
- ✅ 掌握 prerotate/postrotate 钩子
- ✅ 学会调试 logrotate 配置
- ✅ 为实际应用配置日志轮转

---

## 📁 文件说明

- `compose.yaml` - Docker Compose 配置
- `compose.md` - 详细文档（Logrotate 完整教程）
- `logrotate.conf` - Logrotate 测试配置
- `README.md` - 本文件

---

## 🔍 常用命令

```bash
# 测试配置（不实际执行）
logrotate -d /etc/logrotate.d/test-app

# 强制执行轮转
logrotate -f /etc/logrotate.d/test-app

# 详细输出
logrotate -v /etc/logrotate.conf

# 查看状态文件
cat /var/lib/logrotate/logrotate.status

# 查看压缩日志
zcat /var/log/test-app/app.log.2.gz

# 搜索压缩日志
zgrep "keyword" /var/log/test-app/app.log.*.gz
```

---

## 💡 提示

- 使用 `-d` (debug) 参数可以查看执行计划而不实际执行
- 使用 `-f` (force) 参数可以忽略时间条件强制轮转
- `delaycompress` 会保留最新的 `.1` 文件不压缩，便于快速查看
- `postrotate` 脚本通常用于通知应用重新打开日志文件
- 实际生产环境中，logrotate 由 cron 每天自动执行
