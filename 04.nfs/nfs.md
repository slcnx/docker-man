# NFS 常用操作指南

## **一、服务器端操作**

### **1.1 安装与启动**
```bash
# 安装 NFS 服务（Rocky Linux / CentOS）
yum install -y nfs-utils rpcbind

# 启动服务
systemctl start rpcbind
systemctl start nfs-server
systemctl enable rpcbind
systemctl enable nfs-server

# 检查服务状态
systemctl status rpcbind
systemctl status nfs-server
```

### **1.2 配置共享目录**
```bash
# 创建共享目录
mkdir -p /data/share
chmod 755 /data/share

# 编辑导出配置
vim /etc/exports

# 配置示例
/data/share 192.168.1.0/24(rw,sync,no_root_squash)
/data/public *(ro,sync,all_squash)
/data/backup 192.168.1.100(rw,async,no_all_squash)
```

### **1.3 导出选项详解**
```bash
# 访问权限
rw              # 读写权限
ro              # 只读权限

# 用户映射
root_squash     # 将 root 映射为 nfsnobody（默认，安全）
no_root_squash  # 保留 root 权限（危险，需谨慎）
all_squash      # 映射所有用户为匿名用户
no_all_squash   # 保留用户 UID/GID（默认）
anonuid=1000    # 指定匿名用户 UID
anongid=1000    # 指定匿名用户 GID

# 同步选项
sync            # 同步写入磁盘（数据安全，性能较低）
async           # 异步写入（性能高，可能丢数据）

# 其他选项
secure          # 限制客户端端口 < 1024（默认）
insecure        # 允许任意端口
subtree_check   # 检查子目录权限（默认）
no_subtree_check # 不检查子目录（性能更好）
```

### **1.4 导出管理**
```bash
# 重新导出所有目录
exportfs -arv
# -a: 导出或取消所有目录
# -r: 重新导出
# -v: 显示详细信息

# 导出指定目录
exportfs -o rw,sync,no_root_squash 192.168.1.0/24:/data/share

# 取消导出
exportfs -u 192.168.1.100:/data/share   # 取消指定客户端
exportfs -au                             # 取消所有导出

# 查看当前导出
exportfs -v                              # 详细列表
showmount -e localhost                   # 简洁列表
showmount -a                             # 显示已挂载的客户端
```

### **1.5 服务管理**
```bash
# 重启 NFS 服务
systemctl restart nfs-server

# 重新加载配置（不中断连接）
exportfs -ra

# 检查 RPC 服务
rpcinfo -p
rpcinfo -p | grep nfs

# 查看 NFS 统计
nfsstat -s          # 服务器统计
nfsstat -c          # 客户端统计
```

---

## **二、客户端操作**

### **2.1 查看服务器共享**
```bash
# 安装客户端工具
yum install -y nfs-utils

# 查看服务器导出列表
showmount -e 192.168.1.10
showmount -e nfs-server.example.com

# 显示已挂载的客户端（在服务器上执行）
showmount -a
```

### **2.2 挂载 NFS 共享**
```bash
# 创建挂载点
mkdir -p /mnt/nfs

# 基本挂载
mount -t nfs 192.168.1.10:/data/share /mnt/nfs

# 带选项挂载
mount -t nfs -o rw,sync,hard,intr,timeo=600 \
    192.168.1.10:/data/share /mnt/nfs

# 指定 NFS 版本
mount -t nfs -o nfsvers=4 192.168.1.10:/data/share /mnt/nfs
mount -t nfs -o nfsvers=3 192.168.1.10:/data/share /mnt/nfs
```

### **2.3 挂载选项详解**
```bash
# 读写模式
rw              # 读写挂载
ro              # 只读挂载

# 挂载类型
hard            # 硬挂载（推荐）- 无限重试，程序会挂起等待
soft            # 软挂载 - 超时后返回错误

# 中断与超时
intr            # 允许中断挂载操作（推荐）
timeo=600       # RPC 超时（单位：0.1秒，默认 600 = 60秒）
retrans=3       # 重传次数（默认 3）

# 缓存与锁定
nolock          # 禁用文件锁（某些应用需要）
lock            # 启用文件锁（默认）
noac            # 禁用属性缓存
actimeo=30      # 属性缓存时间（秒）

# 读写参数
rsize=8192      # 读取缓冲区大小（字节）
wsize=8192      # 写入缓冲区大小（字节）

# 其他
bg              # 后台挂载（失败时后台重试）
fg              # 前台挂载（默认）
_netdev         # 网络设备（等待网络就绪）
```

### **2.4 永久挂载（/etc/fstab）**
```bash
# 编辑 fstab
vim /etc/fstab

# 添加挂载条目
192.168.1.10:/data/share  /mnt/nfs  nfs  defaults,_netdev  0  0

# 推荐配置
192.168.1.10:/data/share  /mnt/nfs  nfs  rw,hard,intr,timeo=600,_netdev  0  0

# 测试 fstab 配置
mount -a

# 重新挂载所有
mount -a -o remount
```

### **2.5 卸载操作**
```bash
# 正常卸载
umount /mnt/nfs

# 强制卸载（服务器不可达时）
umount -f /mnt/nfs

# 延迟卸载（等待进程释放）
umount -l /mnt/nfs

# 查看占用进程
lsof /mnt/nfs
fuser -m /mnt/nfs

# 终止占用进程
fuser -km /mnt/nfs
```

---

## **三、监控与调试**

### **3.1 挂载状态检查**
```bash
# 查看已挂载的 NFS
mount | grep nfs
df -h -t nfs

# 详细挂载信息
cat /proc/mounts | grep nfs
findmnt -t nfs
```

### **3.2 性能测试**
```bash
# 写入测试
dd if=/dev/zero of=/mnt/nfs/testfile bs=1M count=1000

# 读取测试
dd if=/mnt/nfs/testfile of=/dev/null bs=1M

# 同步写入测试
dd if=/dev/zero of=/mnt/nfs/testfile bs=1M count=1000 oflag=sync

# 清理测试文件
rm -f /mnt/nfs/testfile
```

### **3.3 网络诊断**
```bash
# 测试网络连通性
ping 192.168.1.10

# 检查 RPC 端口
rpcinfo -p 192.168.1.10
rpcinfo -t 192.168.1.10 nfs

# 检查防火墙
telnet 192.168.1.10 2049
nc -zv 192.168.1.10 2049

# 抓包分析
tcpdump -i eth0 port 2049 -w nfs.pcap
```

### **3.4 日志查看**
```bash
# 系统日志
journalctl -u nfs-server -f
journalctl -u rpcbind -f

# 内核日志
dmesg | grep nfs
dmesg | grep -i rpc

# NFS 统计
nfsstat
nfsstat -m          # 挂载点统计
```

---

## **四、安全配置**

### **4.1 防火墙配置**
```bash
# firewalld 配置
firewall-cmd --permanent --add-service=nfs
firewall-cmd --permanent --add-service=rpc-bind
firewall-cmd --permanent --add-service=mountd
firewall-cmd --reload

# 手动开放端口
firewall-cmd --permanent --add-port=2049/tcp
firewall-cmd --permanent --add-port=2049/udp
firewall-cmd --permanent --add-port=111/tcp
firewall-cmd --permanent --add-port=111/udp
firewall-cmd --permanent --add-port=20048/tcp
firewall-cmd --reload

# iptables 配置
iptables -A INPUT -p tcp --dport 2049 -j ACCEPT
iptables -A INPUT -p tcp --dport 111 -j ACCEPT
iptables -A INPUT -p tcp --dport 20048 -j ACCEPT
```

### **4.2 访问控制**
```bash
# /etc/exports 访问控制示例
/data/share 192.168.1.0/24(rw)                    # 网段访问
/data/backup 192.168.1.100(rw) 192.168.1.101(rw)  # 指定主机
/data/public *.example.com(ro)                     # 域名通配
/data/test @trusted_hosts(rw)                      # 使用 netgroup

# /etc/hosts.allow 和 /etc/hosts.deny
# /etc/hosts.allow
rpcbind: 192.168.1.0/24
nfsd: 192.168.1.0/24

# /etc/hosts.deny
rpcbind: ALL
nfsd: ALL
```

### **4.3 SELinux 配置**
```bash
# 查看 SELinux 状态
getenforce

# 设置 NFS 相关布尔值
setsebool -P nfs_export_all_rw on
setsebool -P nfs_export_all_ro on

# 设置文件上下文
semanage fcontext -a -t public_content_rw_t "/data/share(/.*)?"
restorecon -Rv /data/share

# 查看布尔值
getsebool -a | grep nfs
```

---

## **五、故障排除**

### **5.1 常见错误**
```bash
# 错误1: mount.nfs: access denied
# 原因：服务器未导出或权限问题
# 解决：检查 /etc/exports，执行 exportfs -ra

# 错误2: mount.nfs: Connection timed out
# 原因：防火墙阻止或网络不通
# 解决：检查防火墙、网络连通性

# 错误3: Stale file handle
# 原因：服务器重启或导出配置变更
# 解决：umount 后重新 mount

# 错误4: Permission denied
# 原因：文件权限或用户映射问题
# 解决：检查文件权限、all_squash 配置
```

### **5.2 调试技巧**
```bash
# 启用 NFS 调试
rpcdebug -m nfs -s all
rpcdebug -m nfsd -s all

# 关闭调试
rpcdebug -m nfs -c all

# 查看调试信息
dmesg | tail -50
```

---

## **六、最佳实践**

### **6.1 推荐配置**
```bash
# 服务器 /etc/exports 推荐
/data/share 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)

# 客户端挂载推荐
mount -t nfs -o rw,hard,intr,timeo=600,retrans=3 \
    192.168.1.10:/data/share /mnt/nfs

# fstab 推荐
192.168.1.10:/data/share  /mnt/nfs  nfs  hard,intr,timeo=600,_netdev  0  0
```

### **6.2 性能优化**
```bash
# 增大读写缓冲区
mount -t nfs -o rsize=32768,wsize=32768 192.168.1.10:/data/share /mnt/nfs

# 使用异步模式（注意数据安全风险）
/data/share 192.168.1.0/24(rw,async,no_subtree_check)

# 使用 NFSv4（性能更好）
mount -t nfs -o nfsvers=4 192.168.1.10:/data/share /mnt/nfs
```

### **6.3 高可用配置**
```bash
# 使用 autofs 自动挂载
yum install -y autofs

# /etc/auto.master
/mnt/nfs  /etc/auto.nfs  --timeout=300

# /etc/auto.nfs
share  -rw,hard,intr  192.168.1.10:/data/share

# 启动 autofs
systemctl start autofs
systemctl enable autofs
```
