# DNS 指定域转发 + 主从复制 - 自动化部署

## 概述
这是一个完全自动化的 DNS 指定域转发 + 主从复制部署方案，演示了更加灵活的企业级 DNS 架构：
- **指定域转发**：只转发 magedu.com 域到 DNS Server 2
- **直接递归解析**：其他域名在 DNS Server 1 直接递归解析，不经过转发
- **主从复制**：每个 DNS 服务器都有对应的从服务器，提供高可用性
- **混合架构**：结合转发和递归的优势，灵活路由不同域名

用户只需执行 `docker compose up -d` 即可完成整个环境的部署和自动测试。

## 目录结构
```
12.auto-domain-forward/
├── compose.yml                      # Docker Compose 配置文件
├── README.md                        # 说明文档
├── dns-server-1-configs/            # DNS Server 1 (主指定域转发服务器) 配置
│   ├── named.conf
│   └── named.rfc1912.zones          # 包含 magedu.com 的指定域转发配置
├── dns-server-1-slave-configs/      # DNS Server 1 Slave (从指定域转发服务器) 配置
│   ├── named.conf
│   └── named.rfc1912.zones
├── dns-server-2-configs/            # DNS Server 2 (主权威服务器) 配置
│   ├── named.conf
│   ├── named.rfc1912.zones
│   └── magedu.com.zone              # magedu.com 区域文件
├── dns-server-2-slave-configs/      # DNS Server 2 Slave (从权威服务器) 配置
│   ├── named.conf
│   └── named.rfc1912.zones
└── html/                            # Web 服务器内容
    └── index.html
```

## 网络架构
```
10.0.0.0/24 网络拓扑（指定域转发 + 主从复制架构）
├── 10.0.0.1   - 网关
├── 10.0.0.12  - 客户端 (auto-dns-client)
├── 10.0.0.13  - DNS Server 1 主 (auto-dns-server-1) [指定域转发服务器-Master]
├── 10.0.0.16  - DNS Server 1 从 (auto-dns-server-1-slave) [指定域转发服务器-Slave]
├── 10.0.0.14  - Web 服务器 (auto-web-server / www.magedu.com)
├── 10.0.0.15  - DNS Server 2 主 (auto-dns-server-2) [权威服务器-Master]
└── 10.0.0.17  - DNS Server 2 从 (auto-dns-server-2-slave) [权威服务器-Slave]

DNS 转发流程（指定域）：
- magedu.com 域：client → dns-server-1 (指定域转发) → dns-server-2 (权威解析)
- 其他域名：client → dns-server-1 (直接递归解析) → Internet

主从复制流程：
dns-server-1 (Master) ⇄ dns-server-1-slave (Slave) [转发配置相同]
dns-server-2 (Master) ⇄ dns-server-2-slave (Slave) [区域同步]
```

## 快速启动

### 一键启动
```bash
# 进入目录
cd /root/docker-man/dns/12.auto-domain-forward

# 启动所有服务（自动部署 + 自动测试）
docker compose up -d

# 查看服务状态
docker compose ps

# 查看自动测试结果
docker logs auto-dns-client
```

### 查看测试输出
启动后，客户端会自动执行以下测试并输出结果：
```bash
docker logs -f auto-dns-client
```

预期输出：
```
===== DNS 指定域转发 + 主从复制自动化测试开始 =====

========== 1. 测试指定域转发 (magedu.com) ==========
1.1 通过主转发服务器 (server-1) 查询 magedu.com:
10.0.0.14
1.2 通过从转发服务器 (server-1-slave) 查询 magedu.com:
10.0.0.14
1.3 通过主权威服务器 (server-2) 查询 magedu.com:
10.0.0.14
1.4 通过从权威服务器 (server-2-slave) 查询 magedu.com:
10.0.0.14

========== 2. 测试非指定域（直接递归解析） ==========
2.1 通过 server-1 查询 www.baidu.com（直接递归，不转发）:
www.a.shifen.com.
39.156.70.239
2.2 通过 server-1-slave 查询 www.qq.com（直接递归，不转发）:
https.wshifen.com.
211.161.244.70

========== 3. 验证主从 NS 记录 ==========
dns-server-2-slave.magedu.com.
dns-server-2.magedu.com.

========== 4. 测试 Web 访问 ==========
<!DOCTYPE html>
<html lang="zh-CN">
<head>

========== 5. 验证转发行为差异 ==========
说明：magedu.com 通过指定域转发到 server-2
      其他域名在 server-1 直接递归解析，不经过转发

===== 测试完成，容器保持运行 =====
```

## 自动化特性

### 1. 配置文件自动挂载
- 所有 DNS 配置文件预先准备好
- 自动挂载到对应容器
- 无需手动进入容器配置

### 2. 指定域转发配置
- DNS Server 1 配置了 `zone "magedu.com" { type forward; }`
- 只有 magedu.com 域的查询转发到 DNS Server 2
- 其他域名在 DNS Server 1 直接递归解析

### 3. 主从自动同步
- DNS Server 2 Slave 自动从主服务器同步 magedu.com 区域
- 使用 Docker volume 持久化从服务器数据
- 自动 NOTIFY 和 AXFR 区域传输

### 4. 健康检查
- DNS Server 1/1-Slave：`dig @127.0.0.1 www.magedu.com`（验证指定域转发）
- DNS Server 2/2-Slave：`dig @127.0.0.1 www.magedu.com`（验证权威解析）
- Web Server：`wget --spider http://localhost`

### 5. 依赖管理
- 客户端等待所有 DNS 服务器和 Web 服务器健康后才启动
- 从服务器等待主服务器健康后启动
- 确保服务按正确顺序启动

### 6. 自动测试
客户端启动后自动执行全面测试：
- 指定域 (magedu.com) 转发测试
- 非指定域直接递归解析测试
- 主从 NS 记录验证
- Web 访问测试
- 转发行为差异说明

## 验证测试

### 测试指定域转发
```bash
# 进入客户端容器
docker exec -it auto-dns-client bash

# 测试指定域（magedu.com）- 通过转发
dig @10.0.0.13 www.magedu.com              # 主转发服务器
dig @10.0.0.16 www.magedu.com              # 从转发服务器
dig @10.0.0.15 www.magedu.com              # 主权威服务器
dig @10.0.0.17 www.magedu.com              # 从权威服务器

# 查看转发路径
dig @10.0.0.13 www.magedu.com +trace       # 查看解析路径
```

### 测试非指定域（直接递归）
```bash
# 测试其他域名 - 不通过转发，直接递归
dig @10.0.0.13 www.baidu.com               # 直接递归解析
dig @10.0.0.16 www.google.com              # 直接递归解析
dig @10.0.0.13 www.qq.com                  # 直接递归解析

# 查看递归解析路径
dig @10.0.0.13 www.baidu.com +trace        # 查看解析路径（不经过 server-2）
```

### 对比转发与递归
```bash
# 对比：指定域转发 vs 非指定域递归
echo "=== 指定域转发（magedu.com）==="
dig @10.0.0.13 www.magedu.com +trace

echo "=== 非指定域递归（baidu.com）==="
dig @10.0.0.13 www.baidu.com +trace

# 观察区别：
# - magedu.com：client → server-1 → server-2（转发）
# - baidu.com：client → server-1 → Internet（递归，不经过 server-2）
```

### 验证主从同步
```bash
# 查看主服务器区域文件
docker exec auto-dns-server-2 cat /var/named/magedu.com.zone

# 查看从服务器同步的区域文件
docker exec auto-dns-server-2-slave cat /var/named/slaves/magedu.com.zone

# 验证区域状态
docker exec auto-dns-server-2 rndc zonestatus magedu.com
docker exec auto-dns-server-2-slave rndc zonestatus magedu.com
```

### 查看转发配置
```bash
# 查看 server-1 的指定域转发配置
docker exec auto-dns-server-1 grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones

# 查看 server-1-slave 的指定域转发配置
docker exec auto-dns-server-1-slave grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones

# 应该看到：
# zone "magedu.com" IN {
#     type forward;
#     forwarders { 10.0.0.15; };
#     forward only;
# };
```

### 测试故障转移
```bash
# 停止主转发服务器
docker compose stop dns-server-1

# 测试从转发服务器是否仍能提供服务
docker exec auto-dns-client dig @10.0.0.16 www.magedu.com

# 停止主权威服务器
docker compose stop dns-server-2

# 测试从权威服务器是否仍能提供服务
docker exec auto-dns-client dig @10.0.0.17 www.magedu.com

# 恢复服务
docker compose start dns-server-1 dns-server-2
```

### 测试 Web 访问
```bash
# 从客户端访问
docker exec auto-dns-client curl http://www.magedu.com
docker exec auto-dns-client ping -c 3 www.magedu.com
```

## 从宿主机测试
```bash
# 查看自动测试结果
docker logs auto-dns-client

# 测试指定域转发
docker exec auto-dns-client dig @10.0.0.13 www.magedu.com

# 测试非指定域递归
docker exec auto-dns-client dig @10.0.0.13 www.baidu.com

# 验证主从同步
docker exec auto-dns-server-2-slave ls -l /var/named/slaves/

# 对比转发行为
docker exec auto-dns-client dig @10.0.0.13 www.magedu.com +trace
docker exec auto-dns-client dig @10.0.0.13 www.baidu.com +trace
```

## 服务管理

### 查看日志
```bash
# 查看所有服务日志
docker compose logs -f

# 查看特定服务日志
docker compose logs -f dns-server-1
docker compose logs -f dns-server-2-slave
docker compose logs -f client

# 同时查看主从服务器日志
docker compose logs -f dns-server-2 dns-server-2-slave
```

### 重启服务
```bash
# 重启所有服务
docker compose restart

# 重启特定服务
docker compose restart dns-server-1
docker compose restart dns-server-2-slave

# 重启所有 DNS 服务器
docker compose restart dns-server-1 dns-server-1-slave dns-server-2 dns-server-2-slave
```

### 停止服务
```bash
# 停止所有服务
docker compose down

# 停止特定服务
docker compose stop dns-server-1
```

### 完全清理
```bash
# 清理所有容器、网络和卷
docker compose down --volumes

# 清理并删除镜像
docker compose down --volumes --rmi all
```

## 故障排除

### 常见问题

#### 1. 服务启动失败
```bash
# 检查服务状态
docker compose ps -a

# 查看错误日志
docker compose logs dns-server-1
docker compose logs dns-server-2-slave

# 检查配置语法
docker exec auto-dns-server-1 named-checkconf
docker exec auto-dns-server-2 named-checkconf
```

#### 2. 指定域转发不生效
```bash
# 检查转发配置
docker exec auto-dns-server-1 grep -A 3 'zone "magedu.com"' /etc/named.rfc1912.zones

# 查看查询日志
docker exec auto-dns-server-1 tail -f /var/log/named/query.log
docker exec auto-dns-server-2 tail -f /var/log/named/query.log

# 测试转发路径
docker exec auto-dns-client dig @10.0.0.13 www.magedu.com +trace
```

#### 3. 主从同步问题
```bash
# 检查从服务器区域文件
docker exec auto-dns-server-2-slave ls -l /var/named/slaves/

# 查看区域状态
docker exec auto-dns-server-2 rndc zonestatus magedu.com
docker exec auto-dns-server-2-slave rndc zonestatus magedu.com

# 手动触发区域传输
docker exec auto-dns-server-2-slave rndc retransfer magedu.com
```

#### 4. 网络连通性问题
```bash
# 检查网络
docker network inspect 12auto-domain-forward_dns-net

# 测试连通性
docker exec auto-dns-client ping -c 2 10.0.0.13
docker exec auto-dns-client ping -c 2 10.0.0.15
```

## 配置说明

### 指定域转发配置
在 `named.rfc1912.zones` 中配置：
```conf
zone "magedu.com" IN {
    type forward;                  // 转发类型
    forwarders { 10.0.0.15; };    // 转发目标服务器
    forward only;                  // 仅转发，不递归
};
```

### 主从配置
- **主服务器**：`type master`，配置 `allow-transfer` 和 `also-notify`
- **从服务器**：`type slave`，配置 `masters` 指向主服务器

### 区域管理
- **magedu.com** 由 DNS Server 2 主服务器管理
- 从服务器自动同步到 `/var/named/slaves/magedu.com.zone`

## 指定域转发 vs 全局转发

| 特性 | 全局转发 | 指定域转发 |
|------|---------|-----------|
| 配置位置 | `options { forwarders }` | `zone { type forward }` |
| 作用范围 | 所有域名 | 指定域名 |
| 转发行为 | 全部转发 | 按域选择性转发 |
| 递归解析 | 转发失败才递归 | 非指定域直接递归 |
| 灵活性 | 低 | 高 |
| 性能 | 统一出口 | 优化路由 |
| 适用场景 | 简单网络 | 混合架构、多数据中心 |

## 与其他版本的区别

| 特性 | 10.auto-global-forward | 12.auto-domain-forward |
|------|----------------------|----------------------|
| 转发方式 | 全局转发 | 指定域转发 |
| 配置复杂度 | 低 | 中 |
| magedu.com | 转发到 server-2 | 转发到 server-2 |
| 其他域名 | 转发到 server-2 | 直接递归解析 |
| 灵活性 | 低 | 高 |
| 适用场景 | 统一出口 | 混合架构 |

## 架构优势

1. **更灵活的路由**
   - 不同域名可以有不同的解析策略
   - 内部域名转发，外部域名直接递归

2. **性能优化**
   - 非指定域不经过转发，减少网络跳数
   - 减少 DNS Server 2 的负载

3. **故障隔离**
   - 转发目标故障不影响其他域名解析
   - 更好的容错能力

4. **易于扩展**
   - 可以添加更多指定域转发配置
   - 每个域可以有不同的转发目标

## 应用场景

1. **混合云架构**
   - 企业内部域名转发到内部 DNS
   - 公网域名直接递归解析

2. **多数据中心**
   - 不同数据中心的域名转发到对应 DNS
   - 其他域名统一递归解析

3. **合作伙伴集成**
   - 合作伙伴域名转发到指定服务器
   - 自有域名和公网域名正常解析

4. **分层DNS架构**
   - 特定域名转发到专用 DNS
   - 通用查询分布到多个递归服务器

## 扩展建议

1. **添加更多指定域转发**
```conf
zone "partner.com" IN {
    type forward;
    forwarders { 192.168.1.10; };
    forward only;
};

zone "internal.com" IN {
    type forward;
    forwarders { 172.16.0.10; };
    forward only;
};
```

2. **启用查询日志**
- 已配置查询日志到 `/var/log/named/query.log`
- 可分析转发和递归查询的比例

3. **监控和告警**
- 监控指定域转发的成功率
- 监控不同域名的查询量分布

4. **性能优化**
- 根据查询统计调整转发策略
- 考虑添加更多递归服务器
