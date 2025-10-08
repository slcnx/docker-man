# Docker Compose NFS 架构部署指导

## **架构说明**
- **NFS 服务器**：使用 Docker named volume (nfs-data) 挂载到 `/data/share`
- **容器环境限制**：Docker overlay 文件系统不支持 NFS 导出，必须使用 volume
- **权限模式**：privileged 模式以支持 NFS 内核模块和特权端口

## **网络架构概览**
```
10.0.4.0/24 网络拓扑
├── 10.0.4.1   - 网关
├── 10.0.4.10  - NFS 服务器 (nfs-server) + volume: nfs-data
└── 10.0.4.11  - NFS 客户端 (nfs-client)
```

## **服务启动**
```bash
# 1. 启动所有服务
docker compose up -d

# 2. 检查服务状态
docker compose ps

# 3. 查看网络配置
docker network inspect 01manual-nfs_nfs-net
```

## **NFS 服务器配置**
```bash
# 进入 NFS 服务器容器
docker compose exec -it nfs-server bash

# 1. 验证 volume 挂载（/data/share 已通过 volume 自动创建）
df -T /data/share
ls -ld /data/share

# 2. 创建测试文件
echo "NFS Server Share Data" > /data/share/test.txt

# 3. 配置 NFS 导出（注意：路径和IP之间有空格，IP和选项之间无空格！）
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(rw,sync,no_root_squash,no_all_squash)
EOF

# 4. 导出参数说明：
# rw              - 读写权限
# sync            - 同步写入磁盘
# no_root_squash  - 客户端 root 映射为服务器 root
# no_all_squash   - 保留客户端用户身份
# ro              - 只读权限（可选）
# async           - 异步写入（性能更好，可选）

# 5. 重新导出共享
exportfs -arv
# -a: 导出或取消所有目录
# -r: 重新导出所有目录
# -v: 显示详细信息

# 6. 查看已导出的共享
exportfs -v
showmount -e localhost

# 7. 检查 RPC 服务
rpcinfo -p
ps aux | grep rpc
```

## **NFS 客户端配置**
```bash
# 进入 NFS 客户端容器
docker compose exec -it nfs-client bash

# 1. 启动 RPC 服务（客户端也需要）
rpcbind
rpc.statd

# 2. 查看服务器共享列表
showmount -e 10.0.4.10
# -e: 显示 NFS 服务器的导出列表

# 3. 创建挂载点
mkdir -p /mnt/nfs

# 4. 挂载 NFS 共享
mount -t nfs 10.0.4.10:/data/share /mnt/nfs

# 5. 验证挂载
df -h | grep nfs
mount | grep nfs

# 6. 测试读写
ls -l /mnt/nfs
cat /mnt/nfs/test.txt
echo "Client Write Test" > /mnt/nfs/client-test.txt

# 7. 返回服务器验证
docker compose exec nfs-server ls -l /data/share
```

## **NFS 挂载选项**
```bash
# 常用挂载选项
mount -t nfs -o rw,sync,hard,intr 10.0.4.10:/data/share /mnt/nfs

# 挂载选项说明：
# rw/ro           - 读写/只读
# sync/async      - 同步/异步写入
# hard/soft       - 硬挂载/软挂载
# intr            - 允许中断挂载操作
# timeo=600       - 超时时间（十分之一秒）
# retrans=2       - 重传次数
# nolock          - 禁用文件锁定
# nfsvers=4       - 指定 NFS 版本（3 或 4）
```

## **性能测试**
```bash
# 在客户端测试写入性能
docker compose exec nfs-client bash

# 1. 测试写入速度
dd if=/dev/zero of=/mnt/nfs/testfile bs=1M count=100
# 测试 100MB 文件写入

# 2. 测试读取速度
dd if=/mnt/nfs/testfile of=/dev/null bs=1M

# 3. 清理测试文件
rm -f /mnt/nfs/testfile
```

## **故障排除**
```bash
# 1. 检查服务状态
docker compose ps -a

# 2. 查看服务日志
docker compose logs nfs-server
docker compose logs nfs-client

# 3. 服务器端检查
docker compose exec nfs-server bash
df -T /data/share                       # 验证 volume 挂载（应显示 ext4 等）
rpcinfo -p                              # 检查 RPC 服务
exportfs -v                             # 查看导出配置
cat /etc/exports                        # 查看配置文件
showmount -a                            # 查看挂载客户端

# 4. 客户端端检查
docker compose exec nfs-client bash
showmount -e 10.0.4.10                  # 检查服务器共享
rpcinfo -p 10.0.4.10                    # 检查服务器 RPC
mount | grep nfs                        # 查看已挂载

# 5. 网络连通性测试
docker compose exec nfs-client ping 10.0.4.10

# 6. 常见错误：does not support NFS export
# 原因：目录位于 overlay 文件系统
# 解决：使用 Docker volume（已配置）
docker volume ls
docker volume inspect 01manual-nfs_nfs-data

# 7. 卸载并重新挂载
umount /mnt/nfs
mount -t nfs 10.0.4.10:/data/share /mnt/nfs

# 8. 强制卸载
umount -f /mnt/nfs
umount -l /mnt/nfs                      # lazy unmount

# 9. 调试挂载
mount -vvv -t nfs 10.0.4.10:/data/share /mnt/nfs
dmesg | tail -20                        # 查看内核日志
```

## **服务管理**
```bash
# 重启所有服务
docker compose restart

# 停止服务
docker compose down

# 完全清理（包括删除 volume 数据）
docker compose down --volumes --rmi all

# 仅清理容器，保留 volume 数据
docker compose down --rmi all

# 查看实时日志
docker compose logs -f
```

## **验证完整流程**
```bash
# 1. 启动服务
docker compose up -d

# 2. 配置服务器（在 nfs-server 容器中）
docker compose exec nfs-server bash
# volume 已自动创建 /data/share，无需 mkdir
df -T /data/share                       # 验证 volume 挂载
echo "Test Data" > /data/share/test.txt

# 配置导出
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(rw,sync,no_root_squash,no_all_squash)
EOF
exportfs -arv
showmount -e localhost

# 3. 配置客户端（在 nfs-client 容器中）
docker compose exec nfs-client bash
rpcbind && rpc.statd
showmount -e 10.0.4.10
mkdir -p /mnt/nfs
mount -t nfs 10.0.4.10:/data/share /mnt/nfs
cat /mnt/nfs/test.txt

# 4. 验证成功标志
# - df -T 显示 /data/share 为真实文件系统（ext4 等）
# - showmount 显示共享列表
# - mount 成功无报错
# - 能读取服务器文件内容
# - 所有容器状态为 Up
```

## **常见配置场景**
```bash
# 场景1: 多个共享目录（需要在 compose.yml 中添加多个 volumes）
cat > /etc/exports <<'EOF'
/data/share1 10.0.4.0/24(rw,sync,no_root_squash)
/data/share2 10.0.4.0/24(ro,sync)
/data/public *(ro,sync,all_squash)
EOF

# 场景2: 指定用户映射
# anonuid/anongid - 匿名用户映射
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(rw,sync,all_squash,anonuid=1000,anongid=1000)
EOF

# 场景3: 只读共享 + 特定主机读写
cat > /etc/exports <<'EOF'
/data/share 10.0.4.0/24(ro,sync) 10.0.4.11(rw,sync)
EOF
```
