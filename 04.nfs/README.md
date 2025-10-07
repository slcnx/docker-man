# NFS 服务器和客户端测试环境

## 🚀 快速开始

### 1. 启动环境

```bash
cd /root/docker-man/04.nfs
docker compose up -d
```

### 2. 验证 NFS 服务器

```bash
# 进入服务器容器
docker exec -it nfs-server bash

# 检查 rpcbind 服务
ss -tnl | grep 111

# 检查 NFS 服务
rpcinfo -p

# 查看导出的共享
exportfs -v

# 创建测试文件
echo "Hello from NFS server" > /data/share/test.txt
```

### 3. 测试 NFS 客户端挂载

```bash
# 进入客户端容器
docker exec -it nfs-client bash

# 查看服务器可用共享
showmount -e nfs-server

# 创建挂载点
mkdir -p /mnt/nfs

# 挂载 NFS 共享
mount -t nfs nfs-server:/data/share /mnt/nfs

# 验证挂载
df -h | grep nfs

# 读取服务器文件
cat /mnt/nfs/test.txt

# 在客户端写入文件
echo "Hello from NFS client" > /mnt/nfs/client.txt

# 返回服务器验证
exit
docker exec -it nfs-server cat /data/share/client.txt
```

### 4. 停止环境

```bash
docker compose down
```

---

## 📋 NFS 安装说明

根据 image.png 中的说明：

### Rocky Linux (CentOS/RHEL)

```bash
# 服务端和客户端都需要安装
yum install rpcbind nfs-utils
```

### Ubuntu

```bash
# 服务端
apt install nfs-kernel-server

# 客户端
apt install nfs-common
```

---

## 🔧 配置说明

### NFS 服务器配置

**exports 文件格式**：

```
<导出目录> <客户端>(选项)
```

**示例**：

```bash
# 导出给所有客户端（读写，不检查root）
/data/share *(rw,sync,no_subtree_check,no_root_squash)

# 导出给指定网段（只读）
/data/public 192.168.1.0/24(ro,sync,no_subtree_check)

# 导出给指定主机（读写）
/data/private client1.example.com(rw,sync,no_subtree_check,root_squash)
```

**常用选项**：

| 选项 | 说明 |
|------|------|
| `rw` | 读写权限 |
| `ro` | 只读权限 |
| `sync` | 同步写入（安全，慢） |
| `async` | 异步写入（快，可能丢数据） |
| `no_root_squash` | 客户端 root = 服务端 root |
| `root_squash` | 客户端 root 映射为 nobody |
| `all_squash` | 所有用户映射为 nobody |
| `no_subtree_check` | 不检查子目录（提升性能） |

---

## 🐛 故障排查

### 问题 1：rpc.nfsd 报错

```
rpc.nfsd: Unable to access /proc/fs/nfsd errno 2
```

**解决**：容器需要 `privileged: true` 模式

### 问题 2：mount 权限被拒绝

```
mount: /proc/fs/nfsd: permission denied
```

**解决**：在 compose.yaml 中添加 `privileged: true`

### 问题 3：rpc.statd is not running

```
mount.nfs: rpc.statd is not running but is required for remote locking.
```

**解决**：
- 服务端和客户端都需要启动 `rpc.statd` 服务
- 或使用 `-o nolock` 选项挂载（不推荐生产环境）

```bash
# 方式 1：启动 rpc.statd（已在 compose.yaml 中配置）
rpcbind && rpc.statd

# 方式 2：使用 nolock 选项挂载
mount -t nfs -o nolock nfs-server:/data/share /mnt/nfs
```

### 问题 4：No such file or directory

```
mount.nfs: mounting nfs-server:/data/share failed, reason given by server: No such file or directory
```

**解决**：
```bash
# 在服务器端检查目录是否存在
docker exec -it nfs-server ls -la /data/share

# 检查是否正确导出
docker exec -it nfs-server exportfs -v

# 如果目录不存在，创建并重新导出
docker exec -it nfs-server bash -c "mkdir -p /data/share && exportfs -arv"
```

### 问题 5：客户端无法挂载（网络问题）

```bash
# 检查网络连通性
docker exec -it nfs-client ping nfs-server

# 检查服务器导出是否可见
docker exec -it nfs-client showmount -e nfs-server

# 检查服务器端口
docker exec -it nfs-server rpcinfo -p
```

### 问题 6：Permission denied 读写文件

**原因**：客户端和服务端的 UID/GID 不匹配

**解决**：
- 使用 `no_root_squash` 选项
- 或在两端创建相同 UID/GID 的用户

---

## 🔄 NFS 服务启动顺序

### 服务器端启动顺序

```bash
1. rpcbind          # RPC 端口映射服务
2. rpc.statd        # 文件锁定服务（NSM）
3. mount nfsd       # 挂载 NFS 内核文件系统
4. rpc.nfsd         # NFS 服务守护进程
5. rpc.mountd       # 挂载守护进程
6. exportfs -arv    # 导出共享目录
```

### 客户端启动顺序

```bash
1. rpcbind          # RPC 端口映射服务
2. rpc.statd        # 文件锁定服务（NSM）
3. mount NFS        # 挂载远程共享
```

**rpc.statd 作用**：
- 提供网络状态监控 (Network Status Monitor)
- 处理 NFS 文件锁定功能
- 服务端和客户端都必须运行

---

## 📊 常用命令

### 服务器端

```bash
# 查看导出配置
cat /etc/exports

# 重新导出所有共享
exportfs -ra

# 查看当前导出
exportfs -v

# 查看连接的客户端
showmount -a
```

### 客户端

```bash
# 查看服务器可用共享
showmount -e <server>

# 挂载 NFS
mount -t nfs <server>:/path /mnt/point

# 查看挂载
df -h
mount | grep nfs

# 卸载
umount /mnt/point
```

---

## 🔗 参考资料

- **man 手册**: `man exports`, `man nfs`, `man mount.nfs`
- **配置文件**: `/etc/exports`
- **日志**: `journalctl -u nfs-server`
