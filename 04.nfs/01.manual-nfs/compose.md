# Docker Compose NFS 完整实践指南

## 📚 第一部分：基础知识

### 1.1 什么是 NFS（Network File System）

NFS（网络文件系统）是一种**分布式文件系统协议**，允许客户端通过网络访问远程服务器上的文件，就像访问本地文件一样。

#### NFS 的特点

| 特性 | 说明 | 优势 |
|------|------|------|
| **透明访问** | 客户端无需关心文件实际位置 | 使用简单，如同本地文件 |
| **集中存储** | 数据集中在 NFS 服务器 | 便于管理、备份、共享 |
| **多客户端** | 多个客户端同时访问 | 适合集群、容器环境 |
| **权限控制** | 支持 UID/GID 映射 | 灵活的访问控制 |

#### NFS 版本对比

| 版本 | 特性 | 推荐场景 |
|------|------|---------|
| **NFSv3** | 无状态、UDP 支持、性能较好 | 传统 Unix 环境 |
| **NFSv4** | 有状态、仅 TCP、安全性强、防火墙友好 | 现代生产环境（推荐） |
| **NFSv4.1** | 并行访问、性能优化 | 高性能需求 |
| **NFSv4.2** | 服务端复制、稀疏文件 | 最新特性 |

---

### 1.2 NFS 工作原理

#### 1.2.1 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                         NFS 客户端                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  应用程序（读写文件）                                    │  │
│  └───────────────┬───────────────────────────────────────┘  │
│                  ↓ VFS (Virtual File System)                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  NFS Client Module                                     │  │
│  │  - mount.nfs (挂载)                                    │  │
│  │  - rpc.statd (文件锁定)                                │  │
│  │  - rpcbind (RPC 端口映射)                              │  │
│  └───────────────┬───────────────────────────────────────┘  │
└──────────────────┼───────────────────────────────────────────┘
                   ↓ 网络 (TCP/UDP)
┌──────────────────┼───────────────────────────────────────────┐
│  ┌───────────────┴───────────────────────────────────────┐  │
│  │  NFS Server Module                                     │  │
│  │  - rpcbind (端口 111)                                  │  │
│  │  - rpc.nfsd (主进程，端口 2049)                        │  │
│  │  - rpc.mountd (挂载管理，端口 20048)                   │  │
│  │  - rpc.statd (文件锁定)                                │  │
│  └───────────────┬───────────────────────────────────────┘  │
│                  ↓                                           │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  /data/share (共享目录)                                │  │
│  │  - 通过 Docker Volume 挂载                             │  │
│  │  - 必须是真实文件系统（不能是 overlay）                 │  │
│  └───────────────────────────────────────────────────────┘  │
│                         NFS 服务器                           │
└─────────────────────────────────────────────────────────────┘
```

#### 1.2.2 关键进程说明

| 进程 | 端口 | 作用 | 必需性 |
|------|------|------|--------|
| **rpcbind** | 111 (TCP/UDP) | RPC 端口映射服务 | ✅ 必需 |
| **rpc.nfsd** | 2049 (TCP/UDP) | NFS 主进程，处理文件操作 | ✅ 必需 |
| **rpc.mountd** | 20048 (TCP/UDP) | 挂载/卸载管理，权限验证 | ✅ 必需 |
| **rpc.statd** | 动态端口 | 文件锁定和崩溃恢复 | ⚠️ 可选 |

---

### 1.3 Docker 环境中的 NFS 特殊要求

#### 1.3.1 为什么必须使用 Docker Volume？

| 文件系统类型 | 是否支持 NFS 导出 | 原因 |
|-------------|------------------|------|
| **overlay2**（容器默认） | ❌ 不支持 | NFS 内核模块无法导出 overlay 文件系统 |
| **ext4/xfs**（Volume） | ✅ 支持 | 真实的本地文件系统 |

**错误示例**（会失败）：
```bash
# ❌ 直接在容器内创建目录并导出
mkdir /data/share
exportfs /data/share
# 错误：does not support NFS export
```

**正确示例**（使用 Volume）：
```yaml
volumes:
  - nfs-data:/data/share  # ✅ Volume 映射到真实文件系统
```

#### 1.3.2 为什么需要 privileged 模式？

| 权限需求 | 说明 |
|---------|------|
| **加载内核模块** | nfsd, lockd 等内核模块 |
| **绑定特权端口** | 端口 111, 2049 (< 1024) |
| **修改网络栈** | RPC 服务注册 |

---

## 🌐 第二部分：网络架构与环境说明

### 2.1 网络拓扑

```
Docker Bridge 网络：nfs-net (10.0.4.0/24)
├── 10.0.4.1   - 网关（Docker 网桥）
├── 10.0.4.10  - NFS 服务器（nfs-server）
│   ├── Volume: nfs-data → /data/share
│   └── 端口：111, 2049, 20048
└── 10.0.4.11  - NFS 客户端（nfs-client）
    └── 挂载点：/mnt/nfs → 10.0.4.10:/data/share
```

### 2.2 Docker Compose 配置说明

```yaml
version: '3.8'

services:
  nfs-server:
    # NFS 服务器容器
    container_name: nfs-server
    hostname: nfs-server
    networks:
      nfs-net:
        ipv4_address: 10.0.4.10        # 固定 IP
    privileged: true                    # 必需：加载内核模块
    volumes:
      - nfs-data:/data/share            # 必需：Volume 映射
    ports:                              # 暴露 NFS 端口
      - "2049/tcp"                      # NFS 主端口
      - "111/tcp"                       # RPC 端口映射
      - "20048/tcp"                     # mountd 端口

  nfs-client:
    # NFS 客户端容器
    container_name: nfs-client
    hostname: nfs-client
    networks:
      nfs-net:
        ipv4_address: 10.0.4.11        # 固定 IP
    privileged: true                    # 必需：挂载 NFS
    command: tail -f /dev/null          # 保持运行
    depends_on:
      - nfs-server

networks:
  nfs-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.4.0/24
          gateway: 10.0.4.1

volumes:
  nfs-data:                             # 命名卷，映射到真实文件系统
    driver: local
```

---

## 🚀 第三部分：服务启动与配置

### 3.1 启动环境

```bash
# 1. 进入项目目录
cd /root/docker-man/04.nfs/01.manual-nfs

# 2. 启动所有服务
docker compose up -d

# 3. 检查服务状态
docker compose ps

# 4. 查看网络配置
docker network inspect 01manual-nfs_nfs-net

# 5. 验证 Volume 创建
docker volume ls | grep nfs-data
docker volume inspect 01manual-nfs_nfs-data
```

---

### 3.2 NFS 服务器配置

#### 3.2.1 进入服务器容器

```bash
docker compose exec -it nfs-server bash
```

#### 3.2.2 验证 Volume 挂载

```bash
# 1. 检查挂载点（应显示 ext4 等真实文件系统，而非 overlay）
df -T /data/share

# 预期输出：
# Filesystem     Type  Size  Used Avail Use% Mounted on
# /dev/sda1      ext4   50G  10G   38G  21% /data/share

# 2. 验证目录权限
ls -ld /data/share

# 3. 创建测试文件
echo "NFS Server Share Data" > /data/share/test.txt
ls -l /data/share/
```

#### 3.2.3 配置 NFS 导出

**配置文件：`/etc/exports`**

```bash
# 编辑配置文件
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(rw,sync,no_subtree_check,sec=sys,wdelay,root_squash,no_all_squash)
EOF

# 查看配置
cat /etc/exports
```

**配置语法详解**：

```
/data/share  10.0.4.0/24(rw,sync,no_root_squash,no_all_squash)
    ↑             ↑              ↑
  共享路径      客户端        导出选项（无空格！）
```

#### 3.2.4 导出选项详解

| 选项 | 默认值 | 说明 | 推荐场景 |
|------|--------|------|---------|
| **rw** | ro | 读写权限 | 需要写入数据 |
| **ro** | - | 只读权限 | 仅查询数据 |
| **sync** | ✅ | 同步写入磁盘（安全） | 生产环境 |
| **async** | - | 异步写入（快速） | 测试环境 |
| **no_root_squash** | - | 客户端 root = 服务器 root | 可信客户端 |
| **root_squash** | ✅ | 客户端 root → nobody | 不可信客户端 |
| **all_squash** | - | 所有用户 → nobody | 匿名访问 |
| **no_all_squash** | ✅ | 保留用户身份 | 多用户环境 |
| **no_subtree_check** | - | 不检查父目录权限（快） | 推荐 |
| **subtree_check** | ✅ | 检查父目录权限（慢） | 共享子目录 |

**组合示例**：

```bash
# 场景 1：开发测试（全权限）
/data/share 10.0.4.0/24(rw,sync,no_root_squash,no_all_squash)

# 场景 2：生产环境（限制 root）
/data/share 10.0.4.0/24(rw,sync,root_squash,no_all_squash)

# 场景 3：只读共享（公共数据）
/data/share 10.0.4.0/24(ro,sync,root_squash)

# 场景 4：匿名访问（所有用户映射为 nobody）
/data/share *(rw,sync,all_squash,anonuid=65534,anongid=65534)

# 场景 5：多个客户端不同权限
/data/share 10.0.4.11(rw,sync) 10.0.4.12(ro,sync)
```

**⚠️ 注意事项**：
- **选项之间不能有空格**：`(rw,sync)` ✅ | `(rw, sync)` ❌
- **路径与客户端之间有空格**：`/path 10.0.4.0/24(rw)` ✅
- **客户端与选项之间无空格**：`10.0.4.0/24(rw)` ✅

#### 3.2.5 导出共享并验证

```bash
# 1. 重新导出所有共享（-a: all, -r: re-export, -v: verbose）
exportfs -arv

# 预期输出：
# exporting 10.0.4.0/24:/data/share

# 2. 查看已导出的共享（详细模式）
exportfs -v

# 预期输出：
# /data/share  10.0.4.0/24(sync,wdelay,hide,no_subtree_check,sec=sys,rw,
#              secure,no_root_squash,no_all_squash)

# 3. 查看本地可挂载的共享
showmount -e localhost

# 预期输出：
# Export list for localhost:
# /data/share 10.0.4.0/24

# 4. 检查 RPC 服务
rpcinfo -p

# 预期输出应包含：
# program vers proto   port  service
#  100000    4   tcp    111  portmapper
#  100003    3   tcp   2049  nfs
#  100005    3   tcp  20048  mountd

# 5. 检查 NFS 进程
ps aux | grep -E 'rpc|nfs'

# 预期输出应包含：
# rpcbind
# rpc.nfsd
# rpc.mountd
```

---

## 💻 第四部分：NFS 客户端配置

### 4.1 进入客户端容器

```bash
docker compose exec -it nfs-client bash
```

### 4.2 启动客户端 RPC 服务

```bash
# 1. 启动 RPC 端口映射服务
rpcbind

# 2. 启动文件锁定服务（可选，用于文件锁定）
rpc.statd

# 3. 验证服务启动
ps aux | grep rpc
```

### 4.3 查看服务器共享列表

```bash
# 查看 NFS 服务器的导出列表
showmount -e 10.0.4.10

# 预期输出：
# Export list for 10.0.4.10:
# /data/share 10.0.4.0/24

# 如果失败，排查步骤：
# 1. 检查网络连通性
ping 10.0.4.10

# 2. 检查端口是否可达
telnet 10.0.4.10 2049
telnet 10.0.4.10 111

# 3. 检查服务器端 RPC 服务
rpcinfo -p 10.0.4.10
```

### 4.4 挂载 NFS 共享

#### 4.4.1 创建挂载点

```bash
mkdir -p /mnt/nfs
```

#### 4.4.2 挂载命令

```bash
# 基础挂载（使用默认选项）
mount -t nfs 10.0.4.10:/data/share /mnt/nfs

# 带选项挂载（推荐）
mount -t nfs -o rw,sync,hard,intr 10.0.4.10:/data/share /mnt/nfs

# 指定 NFS 版本（NFSv4）
mount -t nfs -o vers=4 10.0.4.10:/data/share /mnt/nfs

# 高性能挂载（异步、大缓冲区）
mount -t nfs -o async,rsize=1048576,wsize=1048576 10.0.4.10:/data/share /mnt/nfs
```

#### 4.4.3 挂载选项详解

| 选项 | 默认值 | 说明 | 推荐场景 |
|------|--------|------|---------|
| **rw** | ✅ | 读写挂载 | 数据写入 |
| **ro** | - | 只读挂载 | 只读数据 |
| **sync** | - | 同步写入（安全） | 重要数据 |
| **async** | ✅ | 异步写入（快速） | 性能优先 |
| **hard** | ✅ | 挂载失败时持续重试 | 生产环境 |
| **soft** | - | 挂载失败时返回错误 | 临时挂载 |
| **intr** | - | 允许中断挂载操作 | 配合 hard |
| **timeo=600** | 600 | 超时时间（0.1 秒单位） | 网络慢时增大 |
| **retrans=2** | 2 | 重传次数 | 网络不稳定时增大 |
| **rsize=N** | 协商 | 读缓冲区大小（字节） | 性能优化 |
| **wsize=N** | 协商 | 写缓冲区大小（字节） | 性能优化 |
| **vers=4** | 4.2 | 指定 NFS 版本 | 兼容性 |
| **nolock** | - | 禁用文件锁定 | 不需要锁 |
| **_netdev** | - | 网络文件系统标记 | /etc/fstab 必需 |

**推荐组合**：

```bash
# 生产环境（可靠性优先）
mount -t nfs -o rw,sync,hard,intr,timeo=600,retrans=3 10.0.4.10:/data/share /mnt/nfs

# 开发环境（性能优先）
mount -t nfs -o rw,async,rsize=1048576,wsize=1048576 10.0.4.10:/data/share /mnt/nfs

# 容器环境（推荐）
mount -t nfs -o vers=4,rw,hard,intr,nolock 10.0.4.10:/data/share /mnt/nfs
```

### 4.5 验证挂载

```bash
# 1. 查看挂载状态
mount | grep nfs

# 预期输出：
# 10.0.4.10:/data/share on /mnt/nfs type nfs4
# (rw,relatime,vers=4.2,rsize=262144,wsize=262144,namlen=255,hard,proto=tcp,...)

# 2. 查看磁盘使用情况
df -h | grep nfs

# 预期输出：
# 10.0.4.10:/data/share   50G  10G  38G  21% /mnt/nfs

# 3. 查看挂载详细信息
df -T /mnt/nfs

# 4. 列出远程目录内容
ls -l /mnt/nfs

# 预期输出：
# -rw-r--r-- 1 root root 22 Oct 18 10:00 test.txt
```

### 4.6 测试读写

```bash
# 1. 读取服务器创建的文件
cat /mnt/nfs/test.txt

# 预期输出：
# NFS Server Share Data

# 2. 测试写入（创建新文件）
echo "Client Write Test" > /mnt/nfs/client-test.txt

# 3. 验证文件创建成功
ls -l /mnt/nfs/

# 4. 返回服务器端验证（在另一个终端）
docker compose exec nfs-server ls -l /data/share

# 预期输出应包含 client-test.txt
```

---

## 🔑 第五部分：权限控制详解

### 5.1 用户身份映射机制

#### 5.1.1 映射规则表

| 导出选项 | 客户端 root | 客户端普通用户 | 说明 |
|---------|-----------|--------------|------|
| **默认** | → nobody (65534) | 保持原 UID/GID | 安全模式 |
| **no_root_squash** | 保持 root (0) | 保持原 UID/GID | 可信客户端 |
| **all_squash** | → nobody (65534) | → nobody (65534) | 匿名模式 |
| **all_squash + anonuid** | → 指定 UID | → 指定 UID | 统一用户 |

#### 5.1.2 测试用户映射

**场景 1：默认配置（root_squash）**

```bash
# 服务器配置
/data/share 10.0.4.0/24(rw,sync)  # 默认包含 root_squash

# 客户端测试（root 用户）
docker compose exec nfs-client bash
echo "root file" > /mnt/nfs/root-test.txt
ls -l /mnt/nfs/root-test.txt

# 输出：
# -rw-r--r-- 1 nobody nogroup 10 Oct 18 10:00 root-test.txt
#               ↑ root 被映射为 nobody

# 客户端测试（普通用户）
useradd testuser
su - testuser
echo "user file" > /mnt/nfs/user-test.txt
exit

ls -l /mnt/nfs/user-test.txt
# 输出：
# -rw-r--r-- 1 testuser testuser 10 Oct 18 10:01 user-test.txt
#               ↑ 普通用户保持原身份
```

**场景 2：no_root_squash（允许 root）**

```bash
# 服务器配置
/data/share 10.0.4.0/24(rw,sync,no_root_squash)

exportfs -arv

# 客户端测试
echo "root file 2" > /mnt/nfs/root-test2.txt
ls -l /mnt/nfs/root-test2.txt

# 输出：
# -rw-r--r-- 1 root root 12 Oct 18 10:02 root-test2.txt
#               ↑ root 身份保留
```

**场景 3：all_squash（所有用户匿名）**

```bash
# 服务器配置
/data/share 10.0.4.0/24(rw,sync,all_squash)

exportfs -arv

# 客户端测试（root）
echo "test 1" > /mnt/nfs/all-squash-root.txt

# 客户端测试（普通用户）
su - testuser
echo "test 2" > /mnt/nfs/all-squash-user.txt
exit

# 查看文件
ls -l /mnt/nfs/all-squash-*.txt

# 输出（所有文件都是 nobody）：
# -rw-r--r-- 1 nobody nogroup 7 Oct 18 10:03 all-squash-root.txt
# -rw-r--r-- 1 nobody nogroup 7 Oct 18 10:03 all-squash-user.txt
```

**场景 4：统一用户映射（Web 服务器场景）**

```bash
# 服务器配置（映射到 www-data, UID=33）
/data/share 10.0.4.0/24(rw,sync,all_squash,anonuid=33,anongid=33)

exportfs -arv

# 客户端测试
echo "www file" > /mnt/nfs/www-test.txt
ls -l /mnt/nfs/www-test.txt

# 输出（所有文件属于 www-data）：
# -rw-r--r-- 1 www-data www-data 9 Oct 18 10:04 www-test.txt
```

### 5.2 文件系统权限与 NFS 权限的关系

**重要概念**：
- **NFS 导出选项**：控制客户端是否有 `rw` 权限
- **文件系统权限**：控制用户是否能实际写入文件

**问题示例**：

```bash
# 服务器配置（允许读写）
/data/share 10.0.4.0/24(rw,sync,no_root_squash)

# 但共享目录权限不足
ls -ld /data/share
# drwxr-xr-x 2 root root 4096 Oct 18 10:00 /data/share
#         ↑ 其他用户无写权限

# 客户端挂载后尝试写入
echo "test" > /mnt/nfs/test.txt
# 错误：Permission denied
```

**解决方法**：

```bash
# 方法 1：修改目录权限（推荐）
chmod 777 /data/share  # 或 chmod o+w /data/share

# 方法 2：修改目录所有者
chown www-data:www-data /data/share

# 方法 3：使用 ACL
setfacl -m u:www-data:rwx /data/share
```

---

## 📊 第六部分：性能测试与优化

### 6.1 性能测试

#### 6.1.1 写入性能测试

```bash
# 在客户端执行

# 测试 1：写入 1GB 数据（同步模式）
time dd if=/dev/zero of=/mnt/nfs/testfile bs=1M count=1024

# 测试 2：写入 1GB 数据（异步模式）
# 先重新挂载为 async
umount /mnt/nfs
mount -t nfs -o async 10.0.4.10:/data/share /mnt/nfs
time dd if=/dev/zero of=/mnt/nfs/testfile bs=1M count=1024

# 测试 3：小文件写入（创建 1000 个小文件）
time for i in {1..1000}; do echo "test $i" > /mnt/nfs/file_$i.txt; done
```

#### 6.1.2 读取性能测试

```bash
# 测试 1：读取 1GB 数据
time dd if=/mnt/nfs/testfile of=/dev/null bs=1M

# 测试 2：读取小文件
time cat /mnt/nfs/file_*.txt > /dev/null

# 测试 3：缓存效果（第二次读取应该更快）
time dd if=/mnt/nfs/testfile of=/dev/null bs=1M
```

#### 6.1.3 清理测试文件

```bash
rm -f /mnt/nfs/testfile
rm -f /mnt/nfs/file_*.txt
```

### 6.2 性能优化建议

| 优化项 | 配置 | 性能提升 | 风险 |
|-------|------|---------|------|
| **异步写入** | `async` | 写入速度提升 50-300% | 断电可能丢数据 |
| **增大缓冲区** | `rsize=1048576,wsize=1048576` | 大文件传输提升 20-50% | 内存占用增加 |
| **禁用文件锁** | `nolock` | 并发性能提升 10-20% | 无文件锁保护 |
| **NFSv4.1** | `vers=4.1` | 并行访问性能提升 | 兼容性要求 |
| **网络优化** | 使用万兆网卡、Jumbo Frame | 传输速度提升 | 硬件成本 |

**推荐配置**：

```bash
# 生产环境（平衡性能与安全）
mount -t nfs -o vers=4,rw,hard,intr,rsize=262144,wsize=262144 \
  10.0.4.10:/data/share /mnt/nfs

# 高性能场景（接受数据丢失风险）
mount -t nfs -o vers=4,rw,async,nolock,rsize=1048576,wsize=1048576 \
  10.0.4.10:/data/share /mnt/nfs
```

---

## 🔧 第七部分：故障排除

### 7.1 常见错误与解决方法

#### 错误 1：does not support NFS export

```bash
# 错误信息
exportfs: /data/share does not support NFS export

# 原因
df -T /data/share
# Filesystem     Type     Size  Used Avail Use% Mounted on
# overlay        overlay   50G   10G   38G  21% /data/share
#   ↑ overlay 文件系统不支持 NFS 导出

# 解决
# 必须使用 Docker Volume，修改 compose.yml：
volumes:
  - nfs-data:/data/share  # 使用命名卷
```

#### 错误 2：access denied by server

```bash
# 错误信息
mount.nfs: access denied by server while mounting 10.0.4.10:/data/share

# 原因 1：客户端 IP 不在允许范围内
# 检查服务器 /etc/exports
cat /etc/exports
# /data/share 10.0.4.11(rw)  # 只允许 10.0.4.11，不允许其他 IP

# 解决：修改为网段
/data/share 10.0.4.0/24(rw)
exportfs -arv

# 原因 2：exportfs 未更新
exportfs -arv  # 重新导出
```

#### 错误 3：mount.nfs: Connection timed out

```bash
# 错误信息
mount.nfs: Connection timed out

# 排查步骤：

# 1. 检查网络连通性
ping 10.0.4.10

# 2. 检查端口是否开放
telnet 10.0.4.10 2049  # NFS 端口
telnet 10.0.4.10 111   # RPC 端口

# 3. 检查服务器防火墙
docker compose exec nfs-server iptables -L

# 4. 检查服务是否运行
docker compose exec nfs-server ps aux | grep rpc
docker compose exec nfs-server rpcinfo -p

# 5. 查看服务器日志
docker compose logs nfs-server
```

#### 错误 4：Permission denied（权限拒绝）

```bash
# 错误信息
echo "test" > /mnt/nfs/test.txt
-bash: /mnt/nfs/test.txt: Permission denied

# 原因 1：NFS 只读挂载
mount | grep nfs
# 10.0.4.10:/data/share on /mnt/nfs type nfs4 (ro,...)
#                                                  ↑ 只读

# 解决：重新挂载为 rw
umount /mnt/nfs
mount -t nfs -o rw 10.0.4.10:/data/share /mnt/nfs

# 原因 2：文件系统权限不足
ls -ld /data/share  # 在服务器上检查
# drwxr-xr-x 2 root root ...
#         ↑ 其他用户无写权限

# 解决：修改权限
chmod 777 /data/share  # 或 chmod o+w /data/share

# 原因 3：用户被映射为 nobody，但 nobody 无权限
# 解决：使用 no_root_squash 或修改目录所有者
chown nobody:nogroup /data/share
```

#### 错误 5：Stale file handle

```bash
# 错误信息
ls /mnt/nfs
ls: cannot access '/mnt/nfs': Stale file handle

# 原因：NFS 服务器重启或共享目录被删除

# 解决：
# 1. 卸载
umount -f /mnt/nfs  # 强制卸载
# 或
umount -l /mnt/nfs  # 懒卸载

# 2. 重新挂载
mount -t nfs 10.0.4.10:/data/share /mnt/nfs
```

### 7.2 调试命令

```bash
# 服务器端调试

# 1. 检查导出配置
cat /etc/exports
exportfs -v

# 2. 查看已连接的客户端
showmount -a

# 3. 检查 RPC 服务
rpcinfo -p
rpcinfo -p | grep -E 'nfs|mount'

# 4. 查看 NFS 统计信息
nfsstat -s  # 服务器统计
nfsstat -m  # 挂载点统计

# 5. 检查进程
ps aux | grep -E 'rpc|nfs'

# 6. 查看日志
dmesg | tail -20
journalctl -u nfs-server -n 50

# 客户端调试

# 1. 查看挂载详情
mount | grep nfs
df -h /mnt/nfs

# 2. 检查服务器共享
showmount -e 10.0.4.10

# 3. 检查 RPC 连接
rpcinfo -p 10.0.4.10

# 4. 调试挂载（显示详细信息）
mount -vvv -t nfs 10.0.4.10:/data/share /mnt/nfs

# 5. 查看内核日志
dmesg | grep -i nfs | tail -20

# 6. 网络抓包
tcpdump -i eth0 host 10.0.4.10 and port 2049 -nn
```

---

## 💾 第八部分：持久化挂载（/etc/fstab）

### 8.1 fstab 配置

```bash
# 编辑 /etc/fstab
vim /etc/fstab

# 添加以下行
10.0.4.10:/data/share  /mnt/nfs  nfs  defaults,_netdev  0  0
```

### 8.2 fstab 选项详解

```
10.0.4.10:/data/share  /mnt/nfs  nfs  defaults,_netdev,vers=4,rw,hard  0  0
      ↑                   ↑        ↑              ↑                    ↑  ↑
   远程路径            挂载点  文件系统类型      挂载选项              转储 检查
```

| 字段 | 说明 | 示例 |
|------|------|------|
| **设备** | NFS 服务器:共享路径 | `10.0.4.10:/data/share` |
| **挂载点** | 本地目录 | `/mnt/nfs` |
| **文件系统** | 固定为 `nfs` | `nfs` |
| **选项** | 挂载选项（逗号分隔） | `defaults,_netdev` |
| **转储** | 是否备份（0=否） | `0` |
| **检查** | 启动时检查顺序（0=不检查） | `0` |

### 8.3 重要选项

| 选项 | 说明 | 必需性 |
|------|------|--------|
| **_netdev** | 等待网络就绪后再挂载 | ✅ **必需** |
| **defaults** | rw,suid,dev,exec,auto,nouser,async | 推荐 |
| **auto** | 启动时自动挂载 | 推荐 |
| **noauto** | 不自动挂载（手动 mount -a） | 按需 |
| **x-systemd.automount** | 延迟挂载（访问时才挂载） | 可选 |

### 8.4 测试 fstab

```bash
# 1. 测试挂载（不实际挂载）
mount -fav

# 2. 卸载当前挂载
umount /mnt/nfs

# 3. 根据 fstab 挂载
mount -a

# 4. 验证
df -h /mnt/nfs
mount | grep nfs
```

### 8.5 高级 fstab 配置

```bash
# 生产环境配置（可靠性优先）
10.0.4.10:/data/share  /mnt/nfs  nfs  _netdev,vers=4,rw,hard,intr,timeo=600,retrans=3  0  0

# 开发环境配置（性能优先）
10.0.4.10:/data/share  /mnt/nfs  nfs  _netdev,vers=4,rw,async,rsize=1048576,wsize=1048576  0  0

# 延迟挂载配置（按需挂载）
10.0.4.10:/data/share  /mnt/nfs  nfs  _netdev,x-systemd.automount,x-systemd.idle-timeout=60  0  0
```

---

## 📋 第九部分：测试检查清单

### 9.1 基础知识

- [ ] 理解 NFS 的工作原理和架构
- [ ] 理解 Docker 环境中必须使用 Volume 的原因
- [ ] 掌握 NFS 主要进程（rpcbind, nfsd, mountd）的作用
- [ ] 理解 NFSv3 和 NFSv4 的区别

### 9.2 服务器配置

- [ ] 正确配置 `/etc/exports` 文件
- [ ] 理解导出选项（rw/ro, sync/async, root_squash 等）
- [ ] 使用 `exportfs -arv` 导出共享
- [ ] 使用 `showmount -e` 查看导出列表
- [ ] 验证 RPC 服务正常运行

### 9.3 客户端挂载

- [ ] 使用 `showmount -e` 查询服务器共享
- [ ] 使用 `mount -t nfs` 挂载共享
- [ ] 理解挂载选项（hard/soft, sync/async, rsize/wsize 等）
- [ ] 验证挂载成功（`df -h`, `mount` 命令）
- [ ] 测试读写操作

### 9.4 权限控制

- [ ] 理解用户身份映射机制（root_squash, all_squash）
- [ ] 测试 root 用户映射为 nobody
- [ ] 测试普通用户保持原身份
- [ ] 理解 NFS 权限与文件系统权限的关系
- [ ] 配置统一用户映射（anonuid/anongid）

### 9.5 故障排除

- [ ] 能够诊断 "does not support NFS export" 错误
- [ ] 能够诊断 "access denied" 错误
- [ ] 能够诊断 "Connection timed out" 错误
- [ ] 能够诊断 "Permission denied" 错误
- [ ] 使用 `rpcinfo`, `nfsstat` 等工具调试

### 9.6 高级功能

- [ ] 配置 `/etc/fstab` 实现持久化挂载
- [ ] 进行性能测试和优化
- [ ] 配置多客户端不同权限
- [ ] 理解性能优化选项（async, rsize/wsize）

---

## ❓ 第十部分：常见问题

### Q1: 为什么容器中必须使用 Volume？

**答**：Docker 容器默认使用 overlay2 文件系统，**NFS 内核模块无法导出 overlay 文件系统**。必须使用 Docker Volume 映射到真实的文件系统（如 ext4, xfs）才能导出。

验证方法：
```bash
df -T /data/share
# overlay    → ❌ 无法导出
# ext4       → ✅ 可以导出
```

---

### Q2: root_squash 和 all_squash 的区别？

**答**：

| 选项 | root 用户 | 普通用户 | 使用场景 |
|------|----------|---------|---------|
| **root_squash**（默认） | → nobody | 保持原身份 | 标准安全模式 |
| **no_root_squash** | 保持 root | 保持原身份 | 可信客户端 |
| **all_squash** | → nobody | → nobody | 匿名访问 |

---

### Q3: 如何实现多个 Web 服务器共享文件并保持权限一致？

**答**：使用 `all_squash` + `anonuid/anongid` 映射到 `www-data` 用户。

```bash
# 服务器配置
/data/share 10.0.4.0/24(rw,sync,all_squash,anonuid=33,anongid=33)

# 所有客户端创建相同的 www-data 用户（UID=33）
useradd -u 33 -M www-data

# 修改共享目录所有者
chown www-data:www-data /data/share
```

---

### Q4: NFS 性能慢怎么优化？

**答**：

1. **使用异步写入**：`async`（提升 50-300%）
2. **增大缓冲区**：`rsize=1048576,wsize=1048576`
3. **禁用文件锁**：`nolock`（如果不需要）
4. **升级到 NFSv4.1**：支持并行访问
5. **网络优化**：使用万兆网卡、启用 Jumbo Frame

---

### Q5: mount 时提示 "Stale file handle" 怎么办？

**答**：这是因为 NFS 服务器重启或共享目录被删除。

```bash
# 强制卸载
umount -f /mnt/nfs

# 或懒卸载
umount -l /mnt/nfs

# 重新挂载
mount -t nfs 10.0.4.10:/data/share /mnt/nfs
```

---

### Q6: 如何配置只读共享？

**答**：

```bash
# 服务器配置
/data/share 10.0.4.0/24(ro,sync)

exportfs -arv

# 客户端挂载
mount -t nfs -o ro 10.0.4.10:/data/share /mnt/nfs
```

---

### Q7: 如何配置不同客户端不同权限？

**答**：

```bash
# /etc/exports 配置
/data/share 10.0.4.11(rw,sync) 10.0.4.12(ro,sync) 10.0.4.13(ro)

exportfs -arv
```

---

## 🎓 第十一部分：学习总结

通过本环境的学习，你应该掌握：

### 核心概念

1. **NFS 工作原理**：客户端通过网络访问服务器共享目录
2. **Docker Volume 必要性**：overlay 文件系统不支持 NFS 导出
3. **关键进程**：rpcbind (111), nfsd (2049), mountd (20048)
4. **NFS 版本**：NFSv4 是现代推荐版本（TCP, 仅 2049 端口）

### 配置技能

1. **服务器配置**：编辑 `/etc/exports`，使用 `exportfs -arv` 导出
2. **客户端挂载**：使用 `mount -t nfs` 挂载，理解挂载选项
3. **权限控制**：理解 root_squash, all_squash, anonuid 等选项
4. **持久化**：配置 `/etc/fstab` 实现开机自动挂载

### 故障排除

1. **does not support NFS export** → 使用 Docker Volume
2. **access denied** → 检查 `/etc/exports` 客户端 IP 范围
3. **Permission denied** → 检查文件系统权限和 NFS 权限
4. **Connection timed out** → 检查网络和端口
5. **Stale file handle** → 强制卸载后重新挂载

### 实战应用

1. **Web 集群共享**：多个 Web 服务器共享静态文件
2. **容器持久化**：Kubernetes PV 使用 NFS 后端
3. **开发环境**：多个开发者共享代码目录
4. **备份系统**：集中存储备份数据

---

## 🧹 清理环境

```bash
# 1. 客户端卸载挂载
docker compose exec nfs-client umount /mnt/nfs

# 2. 停止所有容器
docker compose down

# 3. 删除 Volume（可选，会删除数据）
docker compose down --volumes

# 4. 完全清理（包括镜像）
docker compose down --volumes --rmi all
```

---

## 📖 参考资料

- **NFS 官方文档**: https://linux-nfs.org/
- **NFS man 手册**: `man nfs`, `man exports`, `man mount.nfs`
- **RFC 1813**: NFSv3 协议规范
- **RFC 7530**: NFSv4 协议规范
- **Docker Volume 文档**: https://docs.docker.com/storage/volumes/

---

## 🔗 相关项目

- **04.nfs/01.manual-nfs**: 本项目（手动配置 NFS）
- **03.rsyslog**: 日志管理实践
- **05.dns**: DNS 服务配置

---

**完成时间**: 2025-10-09
**文档版本**: v2.0（规范化版本）
**维护者**: docker-man 项目组
