# NFS 权限验证实战指南

## 📚 第一部分：Squash 机制详解

### 1.1 什么是 Squash

**Squash**（压缩/映射）是 NFS 的一种**用户身份映射机制**，用于控制访问挂载目录的用户是否被映射为其他用户。

### 1.2 Squash 映射规则

```
客户端用户 → NFS 导出选项 → 服务器端显示的用户
     ↓              ↓                  ↓
  身份映射      映射规则          最终身份
```

### 1.3 核心映射选项

| 导出选项 | 客户端 root | 客户端普通用户 | 说明 | 默认值 |
|---------|-----------|--------------|------|--------|
| **root_squash** | root (0) → nobody (65534) | 保持原 UID/GID | root 被映射为 nobody | ✅ 是 |
| **no_root_squash** | 保持 root (0) | 保持原 UID/GID | root 保持 root 身份 | ❌ 否 |
| **all_squash** | → nobody (65534) | → nobody (65534) | 所有用户都映射为 nobody | ❌ 否 |
| **no_all_squash** | 根据 root_squash 决定 | 保持原 UID/GID | 普通用户保持原身份 | ✅ 是 |

### 1.4 映射逻辑详解

#### 场景 1：默认配置（root_squash + no_all_squash）
┌─────────────────┐
│  客户端 root    │ ──root_squash──→ nobody (65534)
└─────────────────┘

┌─────────────────┐
│ 客户端普通用户   │ ──no_all_squash──→ 保持原 UID/GID（如 user1, UID=1001）
└─────────────────┘
```bash
# 服务器导出配置
/data/share 10.0.4.0/24(rw,sync,root_squash,no_all_squash)

# 映射规则：
客户端 root 用户     → nobody (UID=65534, GID=65534)
客户端普通用户 user1 → user1 (保持原 UID/GID)
客户端普通用户 user2 → user2 (保持原 UID/GID)
```

**逻辑**：
- `root_squash`：root 被映射为 nobody（安全考虑，防止 root 权限滥用）
- `no_all_squash`：普通用户**不映射**，保持原身份

---

#### 场景 2：可信客户端（no_root_squash + no_all_squash）

```bash
# 服务器导出配置
/data/share 10.0.4.0/24(rw,sync,no_root_squash,no_all_squash)

# 映射规则：
客户端 root 用户     → root (UID=0, GID=0)
客户端普通用户 user1 → user1 (保持原 UID/GID)
客户端普通用户 user2 → user2 (保持原 UID/GID)
```

**逻辑**：
- `no_root_squash`：root **不映射**，保持 root 身份（危险！）
- `no_all_squash`：普通用户**不映射**，保持原身份

---

#### 场景 3：匿名访问（all_squash）

no_root_squash,all_squash（冲突配置）
┌─────────────────┐
│  客户端 root    │ ──all_squash（覆盖）──→ nobody (65534)
└─────────────────┘
       ↑
   no_root_squash 被覆盖！

┌─────────────────┐
│ 客户端普通用户   │ ──all_squash──→ nobody (65534)
└─────────────────┘
```bash
# 服务器导出配置
/data/share 10.0.4.0/24(rw,sync,all_squash)

# 映射规则：
客户端 root 用户     → nobody (UID=65534, GID=65534)
客户端普通用户 user1 → nobody (UID=65534, GID=65534)
客户端普通用户 user2 → nobody (UID=65534, GID=65534)
```

**逻辑**：
- `all_squash`：**所有用户**都映射为 nobody（包括 root）
- 此选项会**覆盖** `no_root_squash`

---

#### 场景 4：统一用户（all_squash + anonuid/anongid）

```bash
# 服务器导出配置
/data/share 10.0.4.0/24(rw,sync,all_squash,anonuid=33,anongid=33)

# 映射规则：
客户端 root 用户     → www-data (UID=33, GID=33)
客户端普通用户 user1 → www-data (UID=33, GID=33)
客户端普通用户 user2 → www-data (UID=33, GID=33)
```

**逻辑**：
- `all_squash`：所有用户都映射
- `anonuid=33,anongid=33`：映射到指定的 UID/GID（www-data）

---

### 1.5 nobody 用户说明

```bash
# 查看 nobody 用户信息
id nobody

# 输出：
uid=65534(nobody) gid=65534(nogroup) groups=65534(nogroup)
```

**特点**：
- **UID/GID**: 65534（系统保留的最小权限用户）
- **用途**: 用于匿名访问、权限最小化
- **安全性**: 通常只有其他用户（other）的权限

---

## 🔬 第二部分：权限验证实战

### 2.1 实验环境

```
Docker Compose 环境：
├── NFS 服务器: 10.0.4.10 (nfs-server)
│   └── 共享目录: /data/share
└── NFS 客户端: 10.0.4.11 (nfs-client)
    └── 挂载点: /mnt/nfs
```

### 2.2 导出配置说明

**当前服务器导出配置**：

```bash
/data/share 10.0.4.0/24(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
```

**配置项解析**：

| 选项 | 含义 | 影响 |
|------|------|------|
| `sync` | 同步写入磁盘 | 数据安全，性能较慢 |
| `wdelay` | 延迟写入（多个写操作批量处理） | 性能优化 |
| `hide` | 不共享子目录 | 仅共享当前目录 |
| `no_subtree_check` | 不检查父目录权限 | 性能优化 |
| `sec=sys` | 使用系统安全认证 | 基于 UID/GID |
| `rw` | 读写权限 | 允许读写 |
| `secure` | 使用 < 1024 端口 | 安全性 |
| **`root_squash`** | **root → nobody** | **root 被映射** |
| **`no_all_squash`** | **普通用户保持原身份** | **普通用户不映射** |

---

## 🧪 第三部分：测试步骤

### 3.1 启动环境

```bash
# 1. 进入项目目录
cd /root/docker-man/04.nfs/01.manual-nfs

# 2. 启动服务
docker compose up -d

# 3. 检查服务状态
docker compose ps
```

---

### 3.2 服务器端配置

#### 步骤 1：进入服务器容器

```bash
docker compose exec -it nfs-server bash
```

#### 步骤 2：配置 NFS 导出

```bash
# 配置 /etc/exports
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(rw,sync,no_subtree_check,root_squash,no_all_squash)
EOF

# 重新导出
exportfs -arv

# 查看导出配置（验证）
exportfs -v
```

**预期输出**：
```
/data/share  10.0.4.0/24(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
```

#### 步骤 3：修改共享目录权限（允许 nobody 写入）

```bash
# 进入共享目录父目录
cd /data

# 查看当前权限
ls -ld share/

# 输出：
# drwxr-xr-x 2 root root 4096 Oct 18 10:00 share/
#          ↑ 其他用户（other）无写权限

# 为其他用户添加写权限（关键步骤！）
chmod o+w share/

# 验证权限修改
ls -ld share/

# 输出：
# drwxr-xrwx 2 root root 4096 Oct 18 10:00 share/
#          ↑ 其他用户现在有写权限了
```

**为什么需要 `chmod o+w`？**

```
客户端 root 用户 → root_squash → 服务器端 nobody 用户
                                        ↓
                          需要共享目录对 nobody 有写权限
                                        ↓
                              chmod o+w share/
                         （other 用户获得写权限）
```

#### 步骤 4：创建测试文件（服务器端）

```bash
# 在共享目录创建测试文件
echo "Server Test" > /data/share/server-test.txt

# 查看文件权限
ls -l /data/share/

# 输出：
# -rw-r--r-- 1 root root 12 Oct 18 10:05 server-test.txt
```

---

### 3.3 客户端配置

#### 步骤 1：进入客户端容器

```bash
# 在宿主机新开终端执行
docker compose exec -it nfs-client bash
```

#### 步骤 2：启动 RPC 服务

```bash
# 启动 RPC 端口映射
rpcbind

# 启动文件锁定服务（可选）
rpc.statd

# 验证服务
ps aux | grep rpc
```

#### 步骤 3：查看服务器共享

```bash
# 查看 NFS 服务器的导出列表
showmount -e 10.0.4.10

# 预期输出：
# Export list for 10.0.4.10:
# /data/share 10.0.4.0/24
```

#### 步骤 4：挂载 NFS 共享

```bash
# 创建挂载点
mkdir -p /mnt/nfs

# 挂载共享目录
mount -t nfs 10.0.4.10:/data/share /mnt/nfs

# 验证挂载
df -h | grep nfs

# 预期输出：
# 10.0.4.10:/data/share   XX.XG  X.XG  XX.XG  XX% /mnt/nfs

# 查看挂载详情
mount | grep nfs

# 预期输出：
# 10.0.4.10:/data/share on /mnt/nfs type nfs4
# (rw,relatime,vers=4.2,rsize=262144,wsize=262144,namlen=255,hard,proto=tcp,...)
```

---

### 3.4 权限验证测试

#### 测试 1：客户端 root 用户创建文件

```bash
# 确认当前是 root 用户
whoami
# 输出：root

id
# 输出：uid=0(root) gid=0(root) groups=0(root)

# 创建测试文件
echo "Client Root Test" > /mnt/nfs/test.root

# 验证文件创建成功
ls -l /mnt/nfs/test.root

# 输出（客户端视角）：
# -rw-r--r-- 1 root root 17 Oct 18 10:10 test.root
```

**关键观察**：
- 客户端看到的文件属于 `root:root`（客户端的视角）
- 实际在服务器端会被映射为 `nobody:nogroup`

---

### 3.5 服务器端验证

#### 步骤 1：切换到服务器终端

```bash
# 在服务器容器中执行
cd /data/share

# 查看文件列表和权限
ls -l
```

**预期输出**：
```
-rw-r--r-- 1 root   root     12 Oct 18 10:05 server-test.txt
-rw-r--r-- 1 nobody nogroup  17 Oct 18 10:10 test.root
              ↑       ↑
        客户端 root 被映射为 nobody
```

**验证结果**：
- ✅ 服务器端文件 `server-test.txt` 属于 `root:root`
- ✅ 客户端 root 创建的 `test.root` 被映射为 `nobody:nogroup`
- ✅ **证明 `root_squash` 生效**

#### 步骤 2：查看 nobody 用户信息

```bash
# 查看 nobody 用户
id nobody

# 输出：
# uid=65534(nobody) gid=65534(nogroup) groups=65534(nogroup)

# 查看文件的数字 UID/GID
stat /data/share/test.root

# 输出应包含：
# Uid: (65534/ nobody)   Gid: (65534/nogroup)
```

---

## 📊 第四部分：映射对比测试

### 4.1 测试矩阵

| 测试场景 | 客户端用户 | 导出选项 | 服务器端显示 | 文件所有者 |
|---------|----------|---------|------------|-----------|
| **测试 1** | root | `root_squash` | nobody:nogroup | nobody (65534) |
| **测试 2** | 普通用户 user1 | `no_all_squash` | user1:user1 | user1 (原 UID) |
| **测试 3** | root | `no_root_squash` | root:root | root (0) |
| **测试 4** | 任意用户 | `all_squash` | nobody:nogroup | nobody (65534) |

### 4.2 测试 1：root_squash（已完成）

**配置**：
```bash
/data/share 10.0.4.0/24(rw,sync,root_squash,no_all_squash)
```

**结果**：
```bash
# 客户端（root 用户）
echo "test" > /mnt/nfs/test.root

# 服务器端
ls -l /data/share/test.root
# -rw-r--r-- 1 nobody nogroup 5 Oct 18 10:10 test.root
```

✅ **root → nobody 映射成功**

---

### 4.3 测试 2：普通用户不映射

**客户端操作**：

```bash
# 创建普通用户
useradd -m -s /bin/bash testuser

# 切换到普通用户
su - testuser

# 创建文件
echo "User Test" > /mnt/nfs/test.user

# 查看文件（客户端视角）
ls -l /mnt/nfs/test.user
# -rw-r--r-- 1 testuser testuser 10 Oct 18 10:15 test.user

# 退出普通用户
exit
```

**服务器端验证**：

```bash
# 查看文件
ls -l /data/share/test.user
```

**可能的输出**：

**情况 A**（服务器有相同 UID 的用户）：
```bash
# 如果服务器也有 testuser（UID 相同）
-rw-r--r-- 1 testuser testuser 10 Oct 18 10:15 test.user
```

**情况 B**（服务器无相同 UID 的用户）：
```bash
# 显示数字 UID
-rw-r--r-- 1 1001 1001 10 Oct 18 10:15 test.user
```

✅ **普通用户保持原 UID/GID，不被映射**

---

### 4.4 测试 3：no_root_squash（允许 root）

**修改服务器配置**：

```bash
# 修改 /etc/exports
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(rw,sync,no_root_squash,no_all_squash)
EOF

# 重新导出
exportfs -arv

# 验证
exportfs -v | grep no_root_squash
```

**客户端测试**：

```bash
# 在客户端（root 用户）
echo "No Root Squash Test" > /mnt/nfs/test.no-squash

# 查看文件
ls -l /mnt/nfs/test.no-squash
# -rw-r--r-- 1 root root 21 Oct 18 10:20 test.no-squash
```

**服务器端验证**：

```bash
# 查看文件
ls -l /data/share/test.no-squash

# 输出：
# -rw-r--r-- 1 root root 21 Oct 18 10:20 test.no-squash
#              ↑    ↑
#         root 身份被保留！
```

✅ **root 身份保留，未被映射为 nobody**

⚠️ **安全警告**：
- 客户端 root 可以在服务器端创建 root 拥有的文件
- 可能导致安全风险，仅用于完全可信的客户端

---

### 4.5 测试 4：all_squash（所有用户匿名）

**修改服务器配置**：

```bash
# 修改 /etc/exports
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(rw,sync,all_squash)
EOF

# 重新导出
exportfs -arv

# 验证
exportfs -v | grep all_squash
```

**客户端测试（root 用户）**：

```bash
# root 用户创建文件
echo "Root All Squash" > /mnt/nfs/test.all-squash-root
```

**客户端测试（普通用户）**：

```bash
# 切换到普通用户
su - testuser

# 普通用户创建文件
echo "User All Squash" > /mnt/nfs/test.all-squash-user

# 退出
exit
```

**服务器端验证**：

```bash
# 查看文件
ls -l /data/share/test.all-squash-*

# 输出：
# -rw-r--r-- 1 nobody nogroup 16 Oct 18 10:25 test.all-squash-root
# -rw-r--r-- 1 nobody nogroup 16 Oct 18 10:26 test.all-squash-user
#              ↑       ↑
#    所有用户（root + 普通用户）都被映射为 nobody
```

✅ **所有用户都被映射为 nobody**

---

## 🔑 第五部分：权限故障排除

### 5.1 常见错误：Permission denied

#### 错误现象

```bash
# 客户端执行
echo "test" > /mnt/nfs/test.txt

# 错误输出
-bash: /mnt/nfs/test.txt: Permission denied
```

#### 排查步骤

**步骤 1：检查 NFS 挂载权限**

```bash
# 查看挂载选项
mount | grep nfs

# 检查是否为只读（ro）
# 10.0.4.10:/data/share on /mnt/nfs type nfs4 (ro,...)
#                                                 ↑ 如果是 ro，需要改为 rw
```

**解决**：
```bash
# 重新挂载为读写
umount /mnt/nfs
mount -t nfs -o rw 10.0.4.10:/data/share /mnt/nfs
```

---

**步骤 2：检查服务器端目录权限**

```bash
# 在服务器端检查
ls -ld /data/share

# 如果输出：
# drwxr-xr-x 2 root root 4096 Oct 18 10:00 /data/share
#          ↑ other 用户无写权限

# 解决：添加写权限
chmod o+w /data/share

# 验证
ls -ld /data/share
# drwxr-xrwx 2 root root 4096 Oct 18 10:00 /data/share
```

---

**步骤 3：检查用户映射**

```bash
# 在服务器端查看配置
exportfs -v

# 如果配置了 root_squash，客户端 root 会被映射为 nobody
# 需要确保 nobody 对共享目录有写权限

# 查看 nobody 权限
su - nobody -s /bin/bash -c "touch /data/share/test-nobody"

# 如果失败，说明权限不足
```

**解决**：
```bash
# 方法 1：修改目录权限
chmod 777 /data/share

# 方法 2：修改目录所有者为 nobody
chown nobody:nogroup /data/share

# 方法 3：使用 no_root_squash
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(rw,sync,no_root_squash)
EOF
exportfs -arv
```

---

### 5.2 常见错误：文件所有者显示为数字

#### 错误现象

```bash
# 服务器端查看文件
ls -l /data/share/

# 输出：
# -rw-r--r-- 1 1001 1001 10 Oct 18 10:30 test.user
#              ↑    ↑
#        显示为数字 UID/GID，而非用户名
```

#### 原因

- 服务器端没有对应 UID 的用户
- 普通用户使用 `no_all_squash` 时保持原 UID/GID

#### 解决方法

**方法 1：在服务器创建相同 UID 的用户**

```bash
# 查看文件的 UID
stat /data/share/test.user | grep Uid

# 输出：
# Uid: ( 1001/  UNKNOWN)   Gid: ( 1001/ UNKNOWN)

# 在服务器创建相同 UID 的用户
useradd -u 1001 -m testuser

# 再次查看文件
ls -l /data/share/test.user
# -rw-r--r-- 1 testuser testuser 10 Oct 18 10:30 test.user
#              ↑ 现在显示用户名了
```

**方法 2：使用 all_squash 统一映射**

```bash
# 修改 /etc/exports
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(rw,sync,all_squash,anonuid=65534,anongid=65534)
EOF

exportfs -arv

# 所有用户都映射为 nobody
```

---

## 📋 第六部分：测试检查清单

### 6.1 基础知识验证

- [ ] 理解 `root_squash` 的作用（root → nobody）
- [ ] 理解 `no_root_squash` 的作用（root 保持 root）
- [ ] 理解 `all_squash` 的作用（所有用户 → nobody）
- [ ] 理解 `no_all_squash` 的作用（普通用户保持原身份）
- [ ] 理解 nobody 用户（UID=65534, GID=65534）

### 6.2 服务器端配置

- [ ] 正确配置 `/etc/exports` 文件
- [ ] 使用 `exportfs -arv` 重新导出
- [ ] 使用 `exportfs -v` 验证配置
- [ ] 修改共享目录权限 `chmod o+w /data/share`
- [ ] 验证 nobody 用户对共享目录有写权限

### 6.3 客户端测试

- [ ] 使用 root 用户创建文件
- [ ] 使用普通用户创建文件
- [ ] 在服务器端验证文件所有者
- [ ] 测试不同导出选项的效果

### 6.4 映射验证

- [ ] 验证 `root_squash`: root → nobody
- [ ] 验证 `no_root_squash`: root → root
- [ ] 验证 `no_all_squash`: 普通用户保持原身份
- [ ] 验证 `all_squash`: 所有用户 → nobody

### 6.5 故障排除

- [ ] 能够诊断 "Permission denied" 错误
- [ ] 能够检查目录权限
- [ ] 能够检查用户映射
- [ ] 能够解决文件所有者显示为数字的问题

---

## 🎓 第七部分：学习总结

### 7.1 核心知识点

1. **Squash 机制**：用户身份映射的核心机制
   - `root_squash`：root → nobody（默认，安全）
   - `no_root_squash`：root → root（危险，仅可信客户端）
   - `all_squash`：所有用户 → nobody（匿名访问）
   - `no_all_squash`：普通用户保持原身份（默认）

2. **权限层级**：
   - **NFS 导出权限**：`rw/ro`（第一层）
   - **用户映射**：`root_squash/all_squash`（第二层）
   - **文件系统权限**：`chmod/chown`（第三层）

3. **关键命令**：
   - `exportfs -arv`：重新导出
   - `exportfs -v`：查看导出配置
   - `showmount -e`：查看服务器共享
   - `chmod o+w`：添加 other 用户写权限
   - `ls -l`：查看文件所有者
   - `stat`：查看文件详细信息

### 7.2 最佳实践

| 场景 | 推荐配置 | 原因 |
|------|---------|------|
| **生产环境** | `root_squash,no_all_squash` | 安全性高，限制 root 权限 |
| **开发环境（可信）** | `no_root_squash,no_all_squash` | 方便开发，保留权限 |
| **Web 服务器集群** | `all_squash,anonuid=33,anongid=33` | 统一用户（www-data） |
| **匿名访问** | `all_squash` | 所有用户匿名，安全性高 |

### 7.3 安全建议

⚠️ **警告**：
- **不要**在不可信的网络上使用 `no_root_squash`
- **不要**将敏感数据共享给不可信的客户端
- **始终**使用 `root_squash`（除非明确需要 root 权限）
- **定期**检查共享目录的权限和所有者

✅ **推荐**：
- 使用 `root_squash`（默认）
- 使用 `chmod o+w` 而非 `chmod 777`
- 使用 IP 地址范围限制客户端访问
- 定期审计 NFS 导出配置

---

## 📖 第八部分：快速参考

### 8.1 映射速查表

| 客户端用户 | root_squash | no_root_squash | all_squash | 服务器端显示 |
|----------|------------|---------------|-----------|------------|
| root | ✅ | ❌ | - | nobody |
| root | ❌ | ✅ | - | root |
| root | - | - | ✅ | nobody |
| 普通用户 | - | - | ❌ (no_all_squash) | 原 UID/GID |
| 普通用户 | - | - | ✅ | nobody |

### 8.2 常用命令

```bash
# 服务器端
exportfs -arv              # 重新导出
exportfs -v                # 查看导出配置
showmount -a               # 查看已挂载的客户端
chmod o+w /data/share      # 添加 other 写权限
ls -l /data/share          # 查看文件所有者

# 客户端
showmount -e 10.0.4.10     # 查看服务器共享
mount -t nfs 10.0.4.10:/data/share /mnt/nfs  # 挂载
df -h /mnt/nfs             # 查看挂载状态
ls -l /mnt/nfs             # 查看文件

# 调试
id                         # 查看当前用户
id nobody                  # 查看 nobody 用户
stat file                  # 查看文件详细信息
mount | grep nfs           # 查看挂载选项
```

---

**完成时间**: 2025-10-09
**文档版本**: v1.0
**适用环境**: 04.nfs/01.manual-nfs
**维护者**: docker-man 项目组
