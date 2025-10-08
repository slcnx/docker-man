# NFS 自动化测试环境

## **项目概述**
自动化配置和测试 NFS 服务器与客户端，无需手动进入容器配置。

## **架构说明**
- **自动配置**：服务器启动时自动配置 NFS 导出，客户端自动挂载并测试
- **健康检查**：使用 healthcheck 确保服务器就绪后再启动客户端
- **测试自动化**：客户端自动执行读写测试和性能测试

## **网络架构**
```
10.0.4.0/24 网络拓扑
├── 10.0.4.1   - 网关
├── 10.0.4.10  - NFS 服务器 (auto-nfs-server) + volume: nfs-data
└── 10.0.4.11  - NFS 客户端 (auto-nfs-client)
```

## **快速开始**

### **1. 启动服务**
```bash
docker compose up -d
```

### **2. 查看自动化测试日志**
```bash
# 查看服务器配置日志
docker compose logs nfs-server

# 查看客户端测试日志
docker compose logs nfs-client

# 实时跟踪日志
docker compose logs -f
```

### **3. 验证 NFS 功能**
```bash
# 检查服务状态
docker compose ps

# 进入服务器查看
docker compose exec nfs-server bash
ls -lh /data/share/
exportfs -v
showmount -a

# 进入客户端查看
docker compose exec nfs-client bash
mount | grep nfs
ls -lh /mnt/nfs/
```

## **配置文件说明**

### **configs/exports**
NFS 导出配置文件，自动挂载到服务器的 `/etc/exports`：
```
/data/share 10.0.4.0/24(rw,sync,no_root_squash,no_all_squash)
```

**导出选项：**
- `rw` - 读写权限
- `sync` - 同步写入磁盘
- `no_root_squash` - 保留客户端 root 权限
- `no_all_squash` - 保留客户端用户身份

## **自动化测试流程**

### **服务器自动化步骤**
1. 启动 RPC 服务 (rpcbind, rpc.statd)
2. 挂载 nfsd 到 `/proc/fs/nfsd`
3. 启动 NFS 服务 (rpc.nfsd, rpc.mountd)
4. 创建测试文件
5. 导出 NFS 共享
6. 验证导出状态

### **客户端自动化测试**
1. 启动 RPC 服务
2. 查看服务器共享列表
3. 创建挂载点
4. 挂载 NFS 共享
5. 验证挂载状态
6. 读取服务器文件
7. 测试写入功能
8. 性能测试（写入 10MB）
9. 性能测试（读取 10MB）
10. 显示 NFS 统计信息

## **测试验证**

### **验证测试成功**
```bash
# 查看客户端日志，应该包含：
docker compose logs nfs-client | grep -E "测试完成|Client write test"

# 检查挂载状态
docker compose exec nfs-client mount | grep nfs
# 输出应包含: 10.0.4.10:/data/share on /mnt/nfs type nfs
```

### **手动额外测试**
```bash
# 进入客户端
docker compose exec nfs-client bash

# 测试读写
echo "Manual test - $(date)" > /mnt/nfs/manual-test.txt
cat /mnt/nfs/manual-test.txt

# 在服务器端验证
docker compose exec nfs-server cat /data/share/manual-test.txt
```

## **故障排除**

### **查看容器状态**
```bash
docker compose ps -a
```

### **查看详细日志**
```bash
# 服务器日志
docker compose logs nfs-server

# 客户端日志
docker compose logs nfs-client

# 持续查看
docker compose logs -f
```

### **常见问题**

#### **1. 客户端无法挂载**
**症状：** 客户端日志显示 "mount.nfs: access denied"
```bash
# 检查服务器导出状态
docker compose exec nfs-server exportfs -v

# 检查网络连通性
docker compose exec nfs-client ping 10.0.4.10

# 重启服务
docker compose restart
```

#### **2. 服务器导出失败**
**症状：** "does not support NFS export"
```bash
# 验证 volume 挂载
docker compose exec nfs-server df -T /data/share

# 应该显示真实文件系统（ext4 等），不是 overlay
```

#### **3. 健康检查失败**
```bash
# 查看健康状态
docker compose ps

# 手动测试健康检查命令
docker compose exec nfs-server showmount -e localhost
```

## **性能优化**

### **调整导出选项**
修改 `configs/exports`：
```bash
# 异步模式（性能更好，风险略高）
/data/share 10.0.4.0/24(rw,async,no_root_squash,no_all_squash)

# 增加缓冲区
# 客户端挂载时添加：-o rsize=32768,wsize=32768
```

### **禁用同步检查**
```bash
# 修改 configs/exports
/data/share 10.0.4.0/24(rw,async,no_subtree_check,no_root_squash)
```

## **服务管理**

```bash
# 重启服务
docker compose restart

# 停止服务
docker compose down

# 完全清理（包括 volume 数据）
docker compose down --volumes --rmi all

# 仅清理容器，保留数据
docker compose down --rmi all

# 查看资源使用
docker stats auto-nfs-server auto-nfs-client
```

## **扩展配置**

### **添加多个共享目录**
1. 在 `compose.yml` 中添加更多 volumes
2. 修改 `configs/exports`：
```
/data/share1 10.0.4.0/24(rw,sync,no_root_squash)
/data/share2 10.0.4.0/24(ro,sync)
```

### **只读共享**
修改 `configs/exports`：
```
/data/share 10.0.4.0/24(ro,sync,no_all_squash)
```

### **限制特定主机**
```
/data/share 10.0.4.11(rw,sync,no_root_squash) 10.0.4.12(ro,sync)
```

## **技术细节**

### **privileged 模式**
- 容器需要 `privileged: true` 以支持 NFS 内核模块和特权端口
- 服务器需要挂载 `/proc/fs/nfsd`
- 客户端需要执行 mount 操作

### **Docker Volume**
- 使用 named volume (nfs-data) 提供真实文件系统
- overlay 文件系统不支持 NFS 导出
- volume 数据持久化，重启容器不丢失

### **健康检查**
- 使用 `showmount -e localhost` 检查服务器就绪
- 客户端通过 `depends_on` 等待服务器健康
- 防止客户端过早尝试挂载

## **注意事项**

1. **privileged 模式**：容器拥有主机级权限，仅用于测试环境
2. **端口冲突**：确保主机端口 111, 2049, 20048 未被占用
3. **数据持久化**：volume 数据在 `docker compose down` 后保留，使用 `--volumes` 删除
4. **网络隔离**：容器使用独立网络，与主机网络隔离

## **参考资料**

- [NFS 常用操作指南](../nfs.md)
- [手动配置版本](../01.manual-nfs/)
- Docker NFS 最佳实践
