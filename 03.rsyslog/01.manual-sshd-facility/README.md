# rsyslog 设施（Facility）和优先级（Priority）测试

## 🚀 快速开始

### 1. 构建并启动容器

```bash
cd /root/docker-man/03.rsyslog/01.manual-sshd-facility
docker compose up -d
```

### 2. 查看容器日志（可选）

```bash
docker compose logs -f
```

### 3. 进入容器

```bash
docker exec -it rsyslog-facility-test bash
```

### 4. 运行测试脚本

```bash
bash /root/test-facility.sh
```

### 5. 手动测试

```bash
# 发送不同设施的日志
logger -p auth.info "AUTH: User login"
logger -p cron.info "CRON: Job started"
logger -p local0.warning "LOCAL0: Custom app warning"

# 查看日志文件
tail -f /var/log/auth.log
tail -f /var/log/cron.log
tail -f /var/log/local0.log

# 使用 journalctl
journalctl -f
journalctl SYSLOG_FACILITY=10  # authpriv
journalctl PRIORITY=3          # error
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
  2. 创建 /dev/log → /run/systemd/journal/dev-log 链接
  3. rsyslogd -dn - 日志处理（前台 debug 模式）

日志流：
  logger → /dev/log → journald → rsyslog → 按设施分类存储
```

---

## 📋 测试内容

自动化测试脚本 `test-facility.sh` 包含：

1. **设施测试** - 测试所有标准设施和 local 设施
2. **优先级测试** - 测试 8 个优先级（emerg 到 debug）
3. **SSH 模拟** - 模拟 sshd 认证日志（authpriv 设施）
4. **Cron 模拟** - 模拟 cron 任务日志（cron 设施）
5. **自定义应用** - 演示 Nginx、MySQL、Web 应用使用 local 设施
6. **日志查看** - 显示不同日志文件的内容
7. **journalctl 查询** - 演示按设施、优先级过滤
8. **统计分析** - 统计各设施和优先级的日志数量

---

## 🎯 学习目标

- ✅ 理解 syslog 设施（0-23）的分类和用途
- ✅ 理解 syslog 优先级（0-7）的含义
- ✅ 掌握 logger 命令的使用
- ✅ 配置 rsyslog 按设施路由日志
- ✅ 使用 journalctl 查询和过滤日志
- ✅ 为自定义应用选择合适的设施

---

## 📁 文件说明

- `compose.yml` - Docker Compose 配置
- `compose.md` - 详细文档（设施/优先级说明）
- `rsyslog.conf` - rsyslog 配置（按设施分类）
- `test-facility.sh` - 自动化测试脚本
- `README.md` - 本文件
