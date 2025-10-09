# Rsync 命令选项完全指南

**版本**: rsync 3.2.5
**协议版本**: 31
**文档更新**: 2025-10-09

---

## 📋 目录

0. [**Rsync 协议与命令格式**](#0-rsync-协议与命令格式) ⭐
1. [基础传输选项](#1-基础传输选项)
2. [文件属性保留](#2-文件属性保留)
3. [文件过滤与排除](#3-文件过滤与排除)
4. [同步策略](#4-同步策略)
5. [性能优化](#5-性能优化)
6. [网络与连接](#6-网络与连接)
7. [安全与权限](#7-安全与权限)
8. [日志与监控](#8-日志与监控)
9. [高级功能](#9-高级功能)
10. [常用场景组合](#10-常用场景组合)

---

## 0. Rsync 协议与命令格式

### 0.1 三种工作模式概览

Rsync 支持三种基本工作模式，每种模式的**命令格式**和**使用场景**都不同。

| 模式 | 命令格式 | 传输方式 | 端口 | 适用场景 |
|------|---------|---------|------|---------|
| **本地模式** | `rsync [选项] SRC DEST` | 本地文件复制 | - | 同一主机内复制 |
| **SSH 模式** | `rsync [选项] SRC user@host:/dest` | SSH 加密传输 | 22 | 互联网、高安全需求 |
| **Daemon 模式** | `rsync [选项] SRC rsync://user@host/module` | rsync 协议 | 873 | 内网、高性能需求 |

---

### 0.2 本地模式（Local）

**用途**：在同一台主机内复制文件，类似 `cp` 命令但功能更强大。

**命令格式**：
```bash
rsync [选项] /source/ /destination/
```

**示例**：
```bash
# 本地完整备份
rsync -av /data/source/ /backup/

# 本地镜像同步
rsync -av --delete /web/ /backup/web/

# 跨挂载点本地复制
rsync -av /home/ /mnt/backup/home/
```

**特点**：
- ✅ 不涉及网络传输
- ✅ 支持增量复制（比 cp 更高效）
- ✅ 可以使用所有 rsync 功能（排除、删除等）
- ⚠️ 默认使用增量算法，本地可用 `-W` 加速

---

### 0.3 SSH 模式（Remote Shell）

**用途**：通过 SSH 协议进行远程传输，数据全程加密。

#### 0.3.1 命令格式

**标准格式**：
```bash
# 推送到远程
rsync [选项] /local/source/ user@remote-host:/remote/dest/

# 从远程拉取
rsync [选项] user@remote-host:/remote/source/ /local/dest/

# 远程到远程（不推荐）
rsync [选项] user@host1:/path1/ user@host2:/path2/
```

**关键点**：
- 使用 **单冒号 `:`** 分隔主机和路径
- 路径是**绝对路径**（从根目录开始）或**相对路径**（相对于用户家目录）

#### 0.3.2 详细示例

```bash
# 示例 1：推送到远程服务器（绝对路径）
rsync -avz /data/source/ root@192.168.1.100:/backup/dest/
#                        ^^^^              ^^^^^^^^^^^^
#                        用户@主机         绝对路径

# 示例 2：推送到远程服务器（相对路径，相对于 root 家目录）
rsync -avz /data/source/ root@192.168.1.100:backup/
#                                           ^^^^^^^
#                                           相对路径 = /root/backup/

# 示例 3：从远程拉取
rsync -avz user@server:/var/www/ /local/www/

# 示例 4：指定 SSH 端口
rsync -avz -e "ssh -p 2222" /source/ user@host:/dest/

# 示例 5：指定 SSH 密钥
rsync -avz -e "ssh -i /root/.ssh/id_rsa" /source/ user@host:/dest/

# 示例 6：SSH 跳过主机验证
rsync -avz -e "ssh -o StrictHostKeyChecking=no" /source/ user@host:/dest/
```

#### 0.3.3 工作原理

```
本地                                     远程
 ↓                                        ↓
rsync 命令                             SSH 服务器 (sshd)
 ↓                                        ↓
建立 SSH 连接 ──────────────────────────→ 验证 SSH 密钥
 ↓                                        ↓
在 SSH 通道内发送 rsync 协议              启动 rsync 子进程
 ↓                                        ↓
加密传输文件数据 ←──────────────────────→ 接收并写入文件
```

#### 0.3.4 特点总结

| 特性 | 说明 |
|------|------|
| **认证方式** | SSH 密钥或 SSH 密码 |
| **加密** | ✅ 全程加密（SSH） |
| **端口** | 22（SSH 默认端口） |
| **性能** | 中等（有加密开销） |
| **安全性** | 高 |
| **配置** | 需要配置 SSH 密钥或密码 |
| **适用场景** | 互联网、跨网段、高安全需求 |

---

### 0.4 Daemon 模式（Rsync Daemon）

**用途**：通过 rsync daemon 服务进行传输，适合内网高性能场景。

#### 0.4.1 两种命令格式

Daemon 模式有**两种等价的写法**：

##### 格式 1：URL 风格（推荐）

```bash
# 使用 rsync:// 协议头（推荐）
rsync [选项] /local/ rsync://user@host/module/path
rsync [选项] /local/ rsync://user@host:port/module/path  # 指定端口
```

**示例**：
```bash
# 推送到 rsync daemon
rsync -avz /data/source/ rsync://rsyncuser@10.0.5.21/backup/

# 从 rsync daemon 拉取
rsync -avz rsync://rsyncuser@10.0.5.21/backup/ /local/dest/

# 指定非标准端口
rsync -avz /source/ rsync://user@host:8873/module/

# 列出服务器上的模块
rsync rsync://10.0.5.21/

# 列出模块内的文件
rsync rsync://rsyncuser@10.0.5.21/backup/
```

##### 格式 2：传统风格（双冒号）

```bash
# 使用双冒号 :: 分隔主机和模块（传统写法）
rsync [选项] /local/ user@host::module/path
```

**示例**：
```bash
# 推送（双冒号写法）
rsync -avz /data/source/ rsyncuser@10.0.5.21::backup/

# 拉取（双冒号写法）
rsync -avz rsyncuser@10.0.5.21::backup/ /local/dest/

# 列出模块（双冒号写法）
rsync user@host::
```

#### 0.4.2 关键点对比

| 特性 | URL 风格 | 双冒号风格 |
|------|---------|-----------|
| **格式** | `rsync://user@host/module/` | `user@host::module/` |
| **可读性** | ✅ 更清晰 | 一般 |
| **指定端口** | `rsync://host:port/module/` | 需要 `--port` 选项 |
| **标准化** | ✅ 符合 URI 标准 | 传统格式 |
| **推荐程度** | ⭐⭐⭐ 推荐 | 兼容旧版 |

**⚠️ 重要区别**：
- SSH 模式：`user@host:/path`（**单冒号** + 文件路径）
- Daemon 模式：`user@host::module`（**双冒号** + 模块名）

#### 0.4.3 模块（Module）概念

**什么是模块？**

- Daemon 模式使用**模块**而非直接的文件路径
- 模块在服务端的 `rsyncd.conf` 中定义
- 每个模块对应一个实际的文件系统路径
- 每个模块可以有独立的权限和认证配置

**服务端配置示例** (`/etc/rsync/rsyncd.conf`):
```ini
[backup]                          # 模块名
    path = /data/backup           # 实际路径
    read only = no
    auth users = rsyncuser
    secrets file = /etc/rsync/rsyncd.secrets

[public]                          # 另一个模块
    path = /data/public
    read only = yes
    list = yes
```

**客户端访问**：
```bash
# 访问 backup 模块（对应 /data/backup）
rsync -avz /source/ rsync://rsyncuser@server/backup/

# 访问 public 模块（对应 /data/public）
rsync -avz rsync://server/public/ /local/public/
```

#### 0.4.4 认证方式

**方法 1：交互式输入密码**
```bash
rsync -avz /source/ rsync://rsyncuser@10.0.5.21/backup/
# 提示：Password:
# 输入：rsyncpass123
```

**方法 2：使用密码文件（自动化）**
```bash
# 创建密码文件（仅包含密码）
echo "rsyncpass123" > /etc/rsync/rsync.pass
chmod 600 /etc/rsync/rsync.pass

# 使用密码文件
rsync -avz --password-file=/etc/rsync/rsync.pass \
    /source/ rsync://rsyncuser@10.0.5.21/backup/
```

**⚠️ 密码文件权限**：
- 必须是 **600**（仅所有者可读写）
- 否则 rsync 会拒绝使用并报错

#### 0.4.5 完整示例

```bash
# 示例 1：推送数据到 daemon（使用密码文件）
rsync -avz --password-file=/etc/rsync/rsync.pass \
    /data/source/ rsync://rsyncuser@10.0.5.21/backup/

# 示例 2：从 daemon 拉取数据
rsync -avz --password-file=/etc/rsync/rsync.pass \
    rsync://rsyncuser@10.0.5.21/backup/ /data/restore/

# 示例 3：镜像同步（删除多余文件）
rsync -avz --delete --password-file=/etc/rsync/rsync.pass \
    /source/ rsync://rsyncuser@10.0.5.21/backup/

# 示例 4：列出服务器所有模块
rsync rsync://10.0.5.21/

# 输出示例：
# backup         Backup Module with Authentication
# public         Public Read-Only Module

# 示例 5：列出模块内的文件
rsync rsync://rsyncuser@10.0.5.21/backup/

# 示例 6：指定非标准端口（URL 格式）
rsync -avz /source/ rsync://user@host:8873/module/

# 示例 7：指定非标准端口（双冒号格式）
rsync -avz --port=8873 /source/ user@host::module/
```

#### 0.4.6 工作原理

```
客户端                                服务端
  ↓                                    ↓
rsync 命令                         rsync daemon (rsyncd)
  ↓                                    ↓
连接端口 873 ──────────────────────→ 监听端口 873
  ↓                                    ↓
发送模块名和认证信息                  读取 rsyncd.conf
  ↓                                    ↓
发送用户名+密码 ───────────────────→ 验证 rsyncd.secrets
  ↓                                    ↓
                                      检查 IP 白名单
  ↓                                    ↓
明文传输 rsync 协议 ←─────────────→ 写入模块路径
```

#### 0.4.7 特点总结

| 特性 | 说明 |
|------|------|
| **认证方式** | 用户名+密码（rsyncd.secrets） |
| **加密** | ❌ 明文传输（可用 stunnel 加密） |
| **端口** | 873（rsync daemon 默认端口） |
| **性能** | 高（无加密开销） |
| **安全性** | 低（仅适合内网） |
| **配置** | 需要配置 rsyncd.conf 和 secrets |
| **模块化** | ✅ 支持多个共享模块 |
| **适用场景** | 内网、局域网、高性能需求 |

---

### 0.5 三种模式对比总结

#### 0.5.1 命令格式对比

```bash
# 本地模式（无冒号）
rsync -av /source/ /dest/

# SSH 模式（单冒号 :）
rsync -avz /source/ user@host:/dest/
rsync -avz user@host:/source/ /dest/

# Daemon 模式（双冒号 :: 或 rsync://）
rsync -avz /source/ rsync://user@host/module/      # URL 格式（推荐）
rsync -avz /source/ user@host::module/             # 双冒号格式
rsync -avz rsync://user@host/module/ /dest/        # 从 daemon 拉取
```

#### 0.5.2 快速识别表

| 格式 | 模式 | 示例 |
|------|------|------|
| `/path/to/dest` | 本地 | `rsync -av /src/ /dst/` |
| `user@host:/path` | SSH | `rsync -av /src/ user@host:/dst/` |
| `rsync://user@host/module` | Daemon (URL) | `rsync -av /src/ rsync://user@host/mod/` |
| `user@host::module` | Daemon (双冒号) | `rsync -av /src/ user@host::mod/` |

#### 0.5.3 使用建议

**互联网环境**：
```bash
# ✅ 使用 SSH 模式（加密安全）
rsync -avz -e ssh /source/ user@remote.com:/backup/
```

**内网环境（高性能需求）**：
```bash
# ✅ 使用 Daemon 模式（高性能）
rsync -avz --password-file=/etc/rsync/rsync.pass \
    /source/ rsync://user@10.0.5.21/backup/
```

**本地备份**：
```bash
# ✅ 使用本地模式
rsync -av /data/ /backup/
```

---

### 0.6 常见错误与识别

#### 错误 1：SSH 模式误用双冒号

```bash
# ❌ 错误：SSH 模式使用双冒号
rsync -av -e ssh /source/ user@host::dest/

# ✅ 正确：SSH 模式使用单冒号
rsync -av -e ssh /source/ user@host:/dest/
```

#### 错误 2：Daemon 模式使用文件路径而非模块

```bash
# ❌ 错误：Daemon 模式直接使用路径
rsync -av /source/ rsync://user@host/data/backup/

# ✅ 正确：Daemon 模式使用模块名
rsync -av /source/ rsync://user@host/backup/
#                                    ^^^^^^
#                                    模块名（在 rsyncd.conf 中定义）
```

#### 错误 3：忘记末尾斜杠

```bash
# ⚠️ 注意：末尾斜杠的区别

# 同步目录内容到 /backup/（/backup/file1.txt）
rsync -av /source/ /backup/

# 同步整个目录到 /backup/（/backup/source/file1.txt）
rsync -av /source /backup/
```

---

### 0.7 实践建议

1. **优先使用 URL 格式**（`rsync://`）：
   - 更符合现代 URI 标准
   - 可读性更好
   - 方便指定端口

2. **生产环境密码文件**：
   ```bash
   # 创建密码文件
   echo "password123" > /etc/rsync/.rsync-pass
   chmod 600 /etc/rsync/.rsync-pass

   # 在脚本中使用
   rsync -avz --password-file=/etc/rsync/.rsync-pass \
       /source/ rsync://user@host/module/
   ```

3. **测试连接**：
   ```bash
   # SSH 模式测试
   ssh user@host "echo 'SSH 连接成功'"

   # Daemon 模式测试（列出模块）
   rsync rsync://host/

   # Daemon 模式测试（列出文件）
   rsync rsync://user@host/module/
   ```

4. **查看详细调试信息**：
   ```bash
   # SSH 模式调试
   rsync -avvv -e ssh /source/ user@host:/dest/

   # Daemon 模式调试
   rsync -avvv rsync://user@host/module/ /dest/
   ```

---

### 0.8 参考项目

本目录下的实践项目：

| 项目 | 模式 | 目录 |
|------|------|------|
| **SSH 手工配置** | SSH | `01.manual-rsync_inotify/` |
| **SSH 自动化** | SSH | `02.auto-rsync_inotify/` |
| **Daemon 手工配置** | Daemon | `03.manual-rsync-service/` |
| **Daemon 自动化** | Daemon | `04.auto-rsync-service/` |
| **方法对比总结** | 全部 | `RSYNC_METHODS_COMPARISON.md` |

---

## 1. 基础传输选项

### 1.1 归档模式

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-a, --archive` | 归档模式 = `-rlptgoD` | **最常用**，完整备份时使用 |
| `-r, --recursive` | 递归复制目录 | 仅需递归，不需保留属性 |
| `-d, --dirs` | 传输目录但不递归 | 只同步目录结构 |

**示例**：
```bash
# 完整归档备份
rsync -a /source/ /dest/

# 仅递归复制，不保留属性
rsync -r /source/ /dest/
```

### 1.2 输出控制

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-v, --verbose` | 显示详细信息 | 调试、查看传输过程 |
| `-q, --quiet` | 静默模式，仅显示错误 | 脚本中使用 |
| `--progress` | 显示传输进度 | 交互式查看进度 |
| `-P` | = `--partial --progress` | **推荐**，断点续传+进度 |
| `-i, --itemize-changes` | 显示文件变化摘要 | 详细了解每个文件的变化 |
| `--stats` | 显示传输统计信息 | 分析传输性能 |

**示例**：
```bash
# 显示详细进度
rsync -avP /source/ /dest/

# 静默模式（脚本）
rsync -aq /source/ /dest/

# 详细变化摘要
rsync -avi /source/ /dest/
```

### 1.3 测试与验证

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-n, --dry-run` | 模拟运行，不实际操作 | **重要**，测试同步结果 |
| `-c, --checksum` | 基于校验和而非时间戳 | 确保文件完全一致 |
| `--list-only` | 仅列出文件，不复制 | 查看源端文件列表 |

**示例**：
```bash
# 测试会同步什么文件
rsync -avz --dry-run /source/ /dest/

# 基于校验和验证
rsync -avc /source/ /dest/
```

---

## 2. 文件属性保留

### 2.1 时间戳

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-t, --times` | 保留修改时间 | **常用**，归档包含此项 |
| `-U, --atimes` | 保留访问时间 | 需要精确时间信息 |
| `-N, --crtimes` | 保留创建时间 | 文件系统支持时 |
| `-O, --omit-dir-times` | 不设置目录时间 | 仅同步文件时间 |
| `-J, --omit-link-times` | 不设置链接时间 | 跳过符号链接时间 |

**示例**：
```bash
# 保留所有时间属性
rsync -atUN /source/ /dest/
```

### 2.2 权限与所有权

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-p, --perms` | 保留权限 | **常用**，归档包含此项 |
| `-o, --owner` | 保留所有者（需root） | 系统级备份 |
| `-g, --group` | 保留组 | 多用户环境 |
| `-E, --executability` | 保留可执行属性 | 仅需保留执行权限 |
| `--chmod=CHMOD` | 修改文件权限 | 调整权限 |
| `--chown=USER:GROUP` | 更改所有者 | 统一所有权 |

**示例**：
```bash
# 完整权限备份（需root）
rsync -avog /source/ /dest/

# 调整权限
rsync -av --chmod=D755,F644 /source/ /dest/
```

### 2.3 链接与设备

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-l, --links` | 保留符号链接 | **常用**，归档包含此项 |
| `-L, --copy-links` | 将符号链接转换为实际文件 | 解除链接依赖 |
| `-H, --hard-links` | 保留硬链接 | 节省空间 |
| `-K, --keep-dirlinks` | 保留目录符号链接 | 特殊目录结构 |
| `--devices` | 保留设备文件（需root） | 系统备份 |
| `--specials` | 保留特殊文件 | 完整系统备份 |
| `-D` | = `--devices --specials` | 系统级备份 |

**示例**：
```bash
# 保留硬链接
rsync -avH /source/ /dest/

# 转换符号链接为文件
rsync -avL /source/ /dest/
```

### 2.4 扩展属性

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-A, --acls` | 保留ACL（访问控制列表） | Linux权限管理 |
| `-X, --xattrs` | 保留扩展属性 | SELinux、文件标签 |
| `--fake-super` | 使用xattr存储特权属性 | 非root备份 |

**示例**：
```bash
# 完整属性备份
rsync -avAX /source/ /dest/

# 非root模拟super权限
rsync -av --fake-super /source/ /dest/
```

---

## 3. 文件过滤与排除

### 3.1 排除模式

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--exclude=PATTERN` | 排除匹配的文件 | **常用**，排除特定文件 |
| `--exclude-from=FILE` | 从文件读取排除规则 | 复杂排除规则 |
| `--include=PATTERN` | 包含匹配的文件 | 与exclude配合使用 |
| `--include-from=FILE` | 从文件读取包含规则 | 复杂包含规则 |
| `-C, --cvs-exclude` | CVS风格排除 | 排除.git、.svn等 |

**示例**：
```bash
# 排除日志和临时文件
rsync -av --exclude='*.log' --exclude='tmp/' /source/ /dest/

# 使用排除文件
rsync -av --exclude-from=/path/exclude.txt /source/ /dest/

# 仅同步特定文件类型
rsync -av --include='*.txt' --exclude='*' /source/ /dest/
```

### 3.2 过滤器

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-f, --filter=RULE` | 添加过滤规则 | 高级过滤 |
| `-F` | = `--filter='dir-merge /.rsync-filter'` | 每目录过滤规则 |
| `--files-from=FILE` | 从文件读取源文件列表 | 精确控制同步文件 |

**示例**：
```bash
# 高级过滤
rsync -av -f '- *.log' -f '+ *.txt' /source/ /dest/

# 从文件列表同步
rsync -av --files-from=filelist.txt /source/ /dest/
```

### 3.3 大小限制

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--max-size=SIZE` | 不传输大于SIZE的文件 | 排除大文件 |
| `--min-size=SIZE` | 不传输小于SIZE的文件 | 排除小文件 |
| `--max-delete=NUM` | 最多删除NUM个文件 | 防止误删 |

**示例**：
```bash
# 仅同步小于100M的文件
rsync -av --max-size=100M /source/ /dest/

# 防止大量删除
rsync -av --delete --max-delete=10 /source/ /dest/
```

---

## 4. 同步策略

### 4.1 删除策略

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--delete` | 删除目标多余文件 | **镜像同步** |
| `--delete-before` | 传输前删除 | 节省空间 |
| `--delete-during` | 传输中删除 | 默认方式 |
| `--delete-after` | 传输后删除 | 更安全 |
| `--delete-delay` | 延迟删除 | 大量文件时 |
| `--delete-excluded` | 删除排除的文件 | 清理排除文件 |
| `--ignore-errors` | 有错误时仍删除 | 强制同步 |
| `--force` | 强制删除非空目录 | 清理目录 |

**示例**：
```bash
# 标准镜像同步
rsync -av --delete /source/ /dest/

# 更安全的删除
rsync -av --delete-after /source/ /dest/

# 删除排除的文件
rsync -av --delete --delete-excluded --exclude='*.log' /source/ /dest/
```

### 4.2 更新策略

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-u, --update` | 跳过目标端较新的文件 | 双向同步保护 |
| `--ignore-existing` | 跳过已存在的文件 | 仅添加新文件 |
| `--existing` | 仅更新已存在的文件 | 不创建新文件 |
| `--size-only` | 仅基于大小判断 | 快速同步 |
| `--ignore-times, -I` | 不跳过相同大小和时间 | 强制检查 |
| `--modify-window=NUM` | 时间戳容差（秒） | 跨平台同步 |

**示例**：
```bash
# 不覆盖新文件
rsync -avu /source/ /dest/

# 仅更新已存在文件
rsync -av --existing /source/ /dest/

# Windows-Linux同步（时间精度）
rsync -av --modify-window=1 /source/ /dest/
```

### 4.3 备份策略

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-b, --backup` | 备份被替换的文件 | 保留旧版本 |
| `--backup-dir=DIR` | 备份文件存放目录 | 集中管理备份 |
| `--suffix=SUFFIX` | 备份文件后缀 | 自定义备份标识 |

**示例**：
```bash
# 备份到指定目录
rsync -av --backup --backup-dir=/backup/old /source/ /dest/

# 自定义备份后缀
rsync -av --backup --suffix=.bak /source/ /dest/
```

---

## 5. 性能优化

### 5.1 传输优化

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-z, --compress` | 压缩传输数据 | **网络传输** |
| `--compress-choice=STR` | 选择压缩算法（zstd/lz4/zlib） | 性能调优 |
| `--compress-level=NUM` | 压缩级别（0-9） | 平衡速度和压缩率 |
| `--skip-compress=LIST` | 跳过已压缩文件 | 避免重复压缩 |
| `-W, --whole-file` | 不使用增量算法 | 本地快速复制 |
| `--inplace` | 就地更新文件 | 节省空间 |
| `--append` | 附加数据到短文件 | 断点续传 |
| `--append-verify` | 附加+校验 | 更安全的续传 |

**示例**：
```bash
# 网络传输压缩
rsync -avz /source/ remote:/dest/

# 使用zstd高性能压缩
rsync -av --compress-choice=zstd /source/ remote:/dest/

# 本地快速复制
rsync -av --whole-file /source/ /dest/

# 就地更新大文件
rsync -av --inplace /source/ /dest/
```

### 5.2 并发与限制

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--bwlimit=RATE` | 限制带宽（KB/s） | 避免占满带宽 |
| `--timeout=SECONDS` | I/O超时时间 | 网络不稳定时 |
| `--contimeout=SECONDS` | 连接超时时间 | daemon模式 |
| `--max-alloc=SIZE` | 内存分配限制 | 资源受限环境 |

**示例**：
```bash
# 限速1MB/s
rsync -av --bwlimit=1024 /source/ /dest/

# 设置超时
rsync -av --timeout=300 /source/ remote:/dest/
```

### 5.3 优化选项

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-S, --sparse` | 稀疏文件优化 | 虚拟机镜像 |
| `--preallocate` | 预分配目标文件 | 减少碎片 |
| `--partial` | 保留部分传输文件 | 断点续传 |
| `--partial-dir=DIR` | 部分文件存放目录 | 集中管理临时文件 |
| `--delay-updates` | 传输完成后更新 | 原子性更新 |
| `-m, --prune-empty-dirs` | 删除空目录链 | 清理目录树 |

**示例**：
```bash
# 稀疏文件优化
rsync -avS /vms/ /backup/vms/

# 断点续传
rsync -avP --partial-dir=/tmp/rsync-partial /source/ /dest/
```

---

## 6. 网络与连接

### 6.1 远程Shell

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-e, --rsh=COMMAND` | 指定远程shell | **SSH传输** |
| `--rsync-path=PROGRAM` | 指定远程rsync路径 | 非标准路径 |
| `--blocking-io` | 使用阻塞I/O | 远程shell兼容 |
| `--protect-args, -s` | 保护参数不展开 | 特殊字符处理 |

**示例**：
```bash
# 使用SSH传输
rsync -av -e "ssh -p 2222" /source/ user@remote:/dest/

# SSH选项
rsync -av -e "ssh -o StrictHostKeyChecking=no" /source/ remote:/dest/

# 指定远程rsync路径
rsync -av --rsync-path=/usr/local/bin/rsync /source/ remote:/dest/
```

### 6.2 Daemon模式

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--port=PORT` | 指定端口 | 非标准端口 |
| `--password-file=FILE` | 密码文件 | 自动化认证 |
| `--address=ADDRESS` | 绑定地址 | 多IP服务器 |
| `--sockopts=OPTIONS` | TCP选项 | 网络调优 |
| `--no-motd` | 不显示MOTD | 脚本使用 |

**示例**：
```bash
# Daemon模式传输
rsync -av rsync://user@server/module/ /dest/

# 使用密码文件
rsync -av --password-file=/root/.rsync-pass rsync://server/module/ /dest/
```

### 6.3 协议版本

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--protocol=NUM` | 强制使用旧协议 | 兼容性 |
| `-4, --ipv4` | 使用IPv4 | 强制IPv4 |
| `-6, --ipv6` | 使用IPv6 | 强制IPv6 |

**示例**：
```bash
# 兼容旧版rsync
rsync -av --protocol=29 /source/ old-server:/dest/
```

---

## 7. 安全与权限

### 7.1 权限控制

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--super` | 尝试超级用户操作 | root权限备份 |
| `--fake-super` | 使用xattr模拟权限 | **非root备份** |
| `--numeric-ids` | 不映射UID/GID | 跨系统备份 |
| `--usermap=STRING` | 用户名映射 | 用户名不同 |
| `--groupmap=STRING` | 组名映射 | 组名不同 |
| `--copy-as=USER[:GROUP]` | 以指定用户身份复制 | 权限控制 |

**示例**：
```bash
# 非root完整备份
rsync -av --fake-super /source/ /dest/

# 用户映射
rsync -av --usermap=olduser:newuser /source/ /dest/
```

### 7.2 文件系统

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-x, --one-file-system` | 不跨文件系统 | 避免挂载点 |
| `--iconv=CONVERT_SPEC` | 字符集转换 | 跨平台 |

**示例**：
```bash
# 不跨越挂载点
rsync -avx / /backup/

# 字符集转换
rsync -av --iconv=UTF-8,GBK /source/ /dest/
```

---

## 8. 日志与监控

### 8.1 输出格式

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--out-format=FORMAT` | 自定义输出格式 | 日志分析 |
| `-h, --human-readable` | 人类可读格式 | 交互使用 |
| `-8, --8-bit-output` | 8位字符输出 | 非ASCII文件名 |
| `--outbuf=N\|L\|B` | 输出缓冲（无\|行\|块） | 日志控制 |

**示例**：
```bash
# 人类可读
rsync -avh /source/ /dest/

# 自定义输出
rsync -av --out-format='%t %f %b' /source/ /dest/
```

### 8.2 日志文件

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--log-file=FILE` | 记录到文件 | 审计追踪 |
| `--log-file-format=FMT` | 日志格式 | 自定义日志 |
| `--info=FLAGS` | 精细信息级别 | 详细调试 |
| `--debug=FLAGS` | 调试信息 | 故障排查 |

**示例**：
```bash
# 记录日志
rsync -av --log-file=/var/log/rsync.log /source/ /dest/

# 调试信息
rsync -av --debug=ALL /source/ /dest/
```

---

## 9. 高级功能

### 9.1 批处理

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--write-batch=FILE` | 写入批处理文件 | 离线传输 |
| `--only-write-batch=FILE` | 仅写批处理 | 不更新目标 |
| `--read-batch=FILE` | 读取批处理文件 | 应用批处理 |

**示例**：
```bash
# 创建批处理
rsync -av --write-batch=/tmp/batch /source/ /dest/

# 应用批处理
rsync -av --read-batch=/tmp/batch /dest/
```

### 9.2 相似文件

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `-y, --fuzzy` | 查找相似文件 | 重命名检测 |
| `--compare-dest=DIR` | 比较目录 | 增量备份 |
| `--copy-dest=DIR` | 复制未变化文件 | 快速备份 |
| `--link-dest=DIR` | 硬链接未变化文件 | **增量备份** |

**示例**：
```bash
# 硬链接增量备份
rsync -av --link-dest=/backup/yesterday /source/ /backup/today/

# 模糊匹配
rsync -avy /source/ /dest/
```

### 9.3 其他高级选项

| 选项 | 说明 | 使用场景 |
|------|------|----------|
| `--checksum-seed=NUM` | 校验和种子 | 高级调试 |
| `--temp-dir=DIR, -T` | 临时文件目录 | 自定义临时位置 |
| `--fsync` | 每个文件fsync | 确保写入磁盘 |
| `--remove-source-files` | 删除源文件 | 移动而非复制 |

**示例**：
```bash
# 移动文件
rsync -av --remove-source-files /source/ /dest/

# 确保同步到磁盘
rsync -av --fsync /source/ /dest/
```

---

## 10. 常用场景组合

### 10.1 本地完整备份

```bash
# 场景：完整系统备份
rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / /backup/

# 说明：
# -a: 归档模式
# -A: 保留ACL
# -X: 保留扩展属性
# -v: 详细输出
# --exclude: 排除系统目录
```

### 10.2 远程增量备份

```bash
# 场景：SSH远程增量备份
rsync -avz --delete -e "ssh -p 22" /source/ user@remote:/backup/

# 说明：
# -z: 压缩传输
# --delete: 镜像同步
# -e ssh: 使用SSH
```

### 10.3 大文件同步

```bash
# 场景：大文件传输（断点续传）
rsync -avP --inplace --partial-dir=/tmp/rsync /large-files/ /dest/

# 说明：
# -P: 进度+部分传输
# --inplace: 就地更新
# --partial-dir: 临时文件目录
```

### 10.4 镜像网站

```bash
# 场景：网站完整镜像
rsync -avz --delete --exclude='*.log' --exclude='cache/*' /var/www/ remote:/var/www/

# 说明：
# --delete: 删除多余文件
# --exclude: 排除日志和缓存
```

### 10.5 实时同步脚本配合

```bash
# 场景：Inotify + Rsync 实时同步
rsync -avz --delete -e "ssh -o StrictHostKeyChecking=no" /data/source/ root@backup:/data/dest/

# 说明：
# 用于inotify触发的同步
# -o StrictHostKeyChecking=no: 跳过SSH验证
```

### 10.6 增量快照备份

```bash
# 场景：每日增量快照（硬链接）
TODAY=$(date +%Y%m%d)
YESTERDAY=$(date -d "yesterday" +%Y%m%d)

rsync -av --delete --link-dest=/backup/$YESTERDAY /source/ /backup/$TODAY/

# 说明：
# --link-dest: 未变化文件硬链接到昨天
# 节省大量空间
```

### 10.7 限速同步

```bash
# 场景：限制带宽避免影响业务
rsync -avz --bwlimit=5120 --timeout=300 /source/ remote:/dest/

# 说明：
# --bwlimit=5120: 限速5MB/s
# --timeout=300: 5分钟超时
```

### 10.8 仅同步特定文件类型

```bash
# 场景：仅同步图片文件
rsync -av --include='*.jpg' --include='*.png' --include='*/' --exclude='*' /photos/ /backup/

# 说明：
# 必须先include目录（*/），再exclude其他
```

### 10.9 双向同步（谨慎使用）

```bash
# 场景：双向同步（使用update避免覆盖新文件）
rsync -avu /dir1/ /dir2/
rsync -avu /dir2/ /dir1/

# 警告：
# 这不是真正的双向同步
# 建议使用unison等专用工具
```

### 10.10 Docker容器数据备份

```bash
# 场景：Docker Volume备份
VOLUME_PATH=$(docker volume inspect volume_name --format '{{ .Mountpoint }}')
rsync -aAXv $VOLUME_PATH/ /backup/docker-volumes/volume_name/

# 说明：
# 保留完整权限和属性
```

---

## 📚 常见问题与技巧

### Q1: 如何测试不实际执行？
```bash
rsync -avz --dry-run /source/ /dest/
```

### Q2: 如何排除多个目录？
```bash
rsync -av --exclude={'dir1','dir2','*.log'} /source/ /dest/
```

### Q3: 如何限制传输速度？
```bash
rsync -av --bwlimit=1024 /source/ /dest/  # 1MB/s
```

### Q4: 如何显示传输进度？
```bash
rsync -avP /source/ /dest/
# 或
rsync -av --progress /source/ /dest/
```

### Q5: 如何保留删除的文件？
```bash
rsync -av --delete --backup --backup-dir=/backup/deleted /source/ /dest/
```

### Q6: 末尾的 / 有什么区别？
```bash
/source/   # 同步目录内容
/source    # 同步目录本身

# 示例：
rsync -av /data/source/ /backup/    # /backup/下直接是文件
rsync -av /data/source  /backup/    # /backup/source/下是文件
```

### Q7: 如何处理特殊字符文件名？
```bash
rsync -av -s /source/ /dest/  # --protect-args
```

### Q8: 如何同步稀疏文件（虚拟机镜像）？
```bash
rsync -avS /vms/ /backup/vms/
```

---

## 🔗 参考资源

- **官方文档**: https://rsync.samba.org/
- **Man手册**: `man rsync`
- **版本查看**: `rsync --version`
- **实践项目**: `/root/docker-man/05.realtime-sync/01.manual-rsync_inotify/`

---

**文档版本**: v1.0
**更新日期**: 2025-10-09
**维护者**: docker-man 项目组
