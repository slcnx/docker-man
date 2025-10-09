# Sersync 实时同步（手工配置）

## 📋 项目说明

本项目提供 **Sersync 实时同步工具**的手工配置学习环境，用于理解基于 inotify + rsync 的实时文件同步方案。

## 🎯 什么是 Sersync

**Sersync** 是一个基于 **inotify + rsync** 的实时文件同步工具，由中国开发者开发，具有以下特点：

### 优势

- ✅ **实时监控**：基于 Linux inotify 机制，实时监控文件变化
- ✅ **自动同步**：检测到变化自动调用 rsync 进行同步
- ✅ **多线程**：支持多线程同步，提高效率
- ✅ **配置简单**：使用 XML 配置文件，易于理解
- ✅ **资源占用低**：相比其他方案更轻量
- ✅ **过滤灵活**：支持多种过滤规则

### 劣势

- ⚠️ **项目停止维护**：2011 年后停止更新（但仍稳定可用）
- ⚠️ **仅支持 Linux**：基于 Linux inotify
- ⚠️ **文档较少**：中文文档为主，社区支持有限

## 🔄 Sersync vs 其他方案

| 特性 | Sersync | rsync+inotify 脚本 | lsyncd |
|------|---------|-------------------|--------|
| **实时监控** | ✅ inotify | ✅ inotify | ✅ inotify |
| **配置方式** | XML 文件 | Shell 脚本 | Lua 脚本 |
| **多线程** | ✅ 支持 | ❌ 单线程 | ✅ 支持 |
| **过滤规则** | 灵活 | 需自行编写 | 灵活 |
| **维护状态** | ⚠️ 停止维护 | ✅ 主动维护 | ✅ 主动维护 |
| **学习曲线** | 低 | 中 | 中 |
| **适用场景** | 中小规模 | 灵活定制 | 大规模 |

## 🏗️ 工作原理

```
源端（sersync-source）
    ↓
1. sersync 进程启动
    ↓
2. 监控 /data/source 目录（inotify）
    ↓
3. 检测到文件变化
    ↓
4. 将变化的文件加入同步队列
    ↓
5. 调用 rsync 命令同步
    ↓ (SSH 或 Daemon 模式)
    ↓
目标端（sersync-backup）
    ↓
6. rsync 接收并写入 /data/backup
```

## 📊 网络架构

```
Docker Bridge: sersync-net (10.0.5.0/24)
├── 10.0.5.1   - 网关
├── 10.0.5.40  - sersync-source（源端）
│   └── Volume: source-data → /data/source
└── 10.0.5.41  - sersync-backup（目标端）
    ├── Volume: backup-data → /data/backup
    ├── Port: 873 → 主机 873（Daemon 模式）
    └── Port: 22 → 主机 8022（SSH 模式）
```

## 🚀 快速开始

### 1. 启动容器

```bash
cd /root/docker-man/05.realtime-sync/05.manual-sersync
docker compose up -d
```

### 2. 查看容器

```bash
docker compose ps

# 预期输出：
# NAME             IMAGE              STATUS
# sersync-source   sersync:latest     Up
# sersync-backup   sersync:latest     Up
```

### 3. 按照文档配置

打开 `compose.md` 文档，按照步骤完成：

1. **选择同步模式**（SSH 或 Daemon）
2. **配置目标端**（SSH 服务或 rsync daemon）
3. **配置源端**（编辑 sersync XML 配置）
4. **启动 sersync**
5. **测试实时同步**

## 🔧 核心配置文件

### sersync XML 配置 (`/etc/sersync/confxml.xml`)

```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<head version="2.5">
    <!-- 本地监控目录 -->
    <localpath watch="/data/source">
        <!-- 远程目标（SSH 模式） -->
        <remote ip="10.0.5.41" name="/data/backup"/>

        <!-- 或者使用 Daemon 模式 -->
        <!-- <remote ip="10.0.5.41" name="backup"/> -->
    </localpath>

    <!-- rsync 配置 -->
    <rsync>
        <commonParams params="-az"/>
        <auth start="false" users="rsyncuser" passwordfile="/etc/rsync.pass"/>

        <!-- SSH 配置 -->
        <userDefinedPort start="true" port="22"/>
        <timeout start="true" time="100"/>

        <!-- SSH 通道参数 -->
        <ssh start="true"/>
    </rsync>

    <!-- 过滤规则 -->
    <filter start="false">
        <exclude expression="(.*)\.log"/>
        <exclude expression="(.*)\.tmp"/>
    </filter>

    <!-- 失败日志 -->
    <failLog path="/var/log/sersync/rsync_fail_log.sh" timeToExecute="60"/>

    <!-- 其他配置 -->
    <crontab start="false" schedule="600">
        <!-- 定时全量同步 -->
    </crontab>
</head>
```

## 🎓 学习目标

通过本项目，你将学会：

1. **理解 Sersync 工作原理**
   - inotify 文件监控机制
   - rsync 同步触发流程
   - 多线程队列管理

2. **掌握 XML 配置**
   - localpath 监控路径配置
   - remote 目标配置
   - rsync 参数配置
   - 过滤规则配置

3. **实践两种传输模式**
   - SSH 模式配置（加密、跨网段）
   - Daemon 模式配置（高性能、内网）

4. **故障排查**
   - 查看 sersync 日志
   - 分析同步失败原因
   - 调试 rsync 命令

## 📁 项目结构

```
05.manual-sersync/
├── compose.yml              # Docker Compose 配置
├── compose.md               # 完整的手工配置文档
└── README.md                # 本文件
```

## 🔗 相关项目对比

### 本系列项目

| 项目 | 工具 | 自动化 | 传输模式 | 适用场景 |
|------|------|--------|---------|---------|
| 01 | rsync+inotify | ❌ 手工 | SSH | 学习 SSH 脚本方案 |
| 02 | rsync+inotify | ✅ 自动 | SSH | 生产环境脚本方案 |
| 03 | rsync daemon | ❌ 手工 | Daemon | 学习 Daemon 原理 |
| 04 | rsync daemon | ✅ 自动 | Daemon | 生产环境 Daemon |
| **05** | **Sersync** | **❌ 手工** | **SSH/Daemon** | **学习 Sersync** |

### 方案选择建议

**选择 Sersync**：
- ✅ 需要图形化（XML）配置
- ✅ 中小规模文件同步
- ✅ 需要多线程同步
- ✅ 接受停止维护的项目

**选择 rsync+inotify 脚本**：
- ✅ 需要完全自定义控制
- ✅ 需要最新版本支持
- ✅ 复杂的业务逻辑

**选择 lsyncd**：
- ✅ 大规模文件同步
- ✅ 需要复杂的同步规则
- ✅ 需要长期维护支持

## ⚠️ 注意事项

### Sersync 项目状态

- 📅 **最后更新**：2011 年
- 🔒 **维护状态**：停止维护
- ✅ **稳定性**：经过多年验证，稳定可靠
- ⚠️ **新功能**：不会有新功能开发
- 📖 **文档**：主要是中文文档和社区经验

### 生产环境建议

1. **评估风险**：考虑项目停止维护的风险
2. **测试验证**：充分测试后再上线
3. **备选方案**：准备 lsyncd 等替代方案
4. **监控告警**：配置完善的监控
5. **定期检查**：定期检查同步状态

## 📚 学习路径

**推荐顺序**：

1. **先学习基础方案**
   - 完成 `01.manual-rsync_inotify`
   - 理解 inotify + rsync 原理

2. **学习 Sersync**
   - 本项目（05.manual-sersync）
   - 对比配置差异

3. **对比其他方案**
   - 阅读 `RSYNC_METHODS_COMPARISON.md`
   - 理解不同方案的优劣

## 🔗 参考资源

### 项目地址

- **GitHub 镜像**: https://github.com/wsgzao/sersync
- **原始项目**: https://code.google.com/archive/p/sersync/ (已停止)

### 文档

- `compose.md` - 本项目详细配置文档
- `../rsync_inotify.md` - Rsync 命令参考
- `../RSYNC_METHODS_COMPARISON.md` - 方法对比总结

### 其他工具

- **lsyncd**: https://github.com/lsyncd/lsyncd (活跃维护)
- **syncthing**: https://syncthing.net/ (P2P 同步)
- **rsync**: https://rsync.samba.org/ (官方)

## 🎯 适用场景

**适合使用 Sersync**：
- ✅ 内网环境文件实时同步
- ✅ 中小规模（< 1000 万文件）
- ✅ 需要简单配置
- ✅ 接受停止维护的工具

**不适合使用 Sersync**：
- ❌ 大规模文件同步（推荐 lsyncd）
- ❌ 要求最新功能支持
- ❌ 需要官方长期维护
- ❌ Windows 环境（仅支持 Linux）

## 🧹 清理环境

```bash
# 停止服务
docker compose down

# 删除所有数据
docker compose down --volumes

# 完全清理
docker compose down --volumes --rmi all
```

---

**完成时间**: 2024-10-09
**文档版本**: v1.0
**适用环境**: 05.manual-sersync
**维护者**: docker-man 项目组
