# Sersync 实时同步完整实践指南

## 📚 第一部分：基础知识

### 1.1 什么是 Sersync

**Sersync** 是一个基于 **inotify + rsync** 的实时文件同步工具，由国内开发者开发。

#### 核心特性

| 特性 | 说明 |
|------|------|
| **实时监控** | 基于 Linux inotify 机制实时监控文件变化 |
| **自动同步** | 检测到变化后自动调用 rsync 进行同步 |
| **多线程** | 支持多线程同步，提高大量文件变化时的效率 |
| **配置简单** | 使用 XML 配置文件，结构清晰 |
| **灵活过滤** | 支持正则表达式过滤 |
| **失败重试** | 支持同步失败记录和定时重试 |

#### 与 rsync+inotify 脚本对比

| 对比项 | Sersync | rsync+inotify 脚本 |
|--------|---------|-------------------|
| **实现方式** | C++ 二进制程序 | Shell 脚本 |
| **配置方式** | XML 配置文件 | 脚本编程 |
| **多线程** | ✅ 内置支持 | ❌ 需要自行实现 |
| **性能** | 高（编译型） | 中（解释型） |
| **灵活性** | 中（配置文件） | 高（脚本定制） |
| **学习曲线** | 低 | 中 |
| **维护状态** | ⚠️ 停止维护（2011年） | ✅ 自行维护 |

---

### 1.2 Sersync 工作原理

#### 1.2.1 工作流程

```
1. Sersync 启动
   ↓
2. 读取 XML 配置文件
   ↓
3. 对监控目录注册 inotify 监听
   ↓
4. 检测到文件变化事件
   ↓
5. 将变化文件加入同步队列
   ↓
6. 多线程从队列取出文件
   ↓
7. 调用 rsync 命令同步
   ↓
8. 记录同步结果
   ↓
9. 失败的文件记录到失败日志
   ↓
10. 定时重试失败的文件（可选）
```

#### 1.2.2 inotify 监控事件

Sersync 监控以下文件系统事件：

| 事件 | 说明 | 触发同步 |
|------|------|---------|
| `IN_CREATE` | 文件/目录创建 | ✅ |
| `IN_DELETE` | 文件/目录删除 | ✅ |
| `IN_MODIFY` | 文件内容修改 | ✅ |
| `IN_MOVED_FROM` | 文件移出监控目录 | ✅ |
| `IN_MOVED_TO` | 文件移入监控目录 | ✅ |
| `IN_CLOSE_WRITE` | 可写文件关闭 | ✅ |
| `IN_ATTRIB` | 元数据变化 | ❌ 默认不触发 |

#### 1.2.3 同步模式支持

Sersync 支持两种 rsync 传输模式：

| 模式 | 配置 | 适用场景 |
|------|------|---------|
| **SSH 模式** | `<ssh start="true"/>` | 互联网、跨网段、高安全 |
| **Daemon 模式** | `<ssh start="false"/>` | 内网、高性能 |

---

### 1.3 XML 配置文件结构

#### 1.3.1 完整配置示例（官方模板）

```xml
<?xml version="1.0" encoding="ISO-8859-1"?>
<head version="2.5">
    <!-- HTTP 管理接口 -->
    <host hostip="localhost" port="8008"></host>

    <!-- 调试模式 -->
    <debug start="false"/>

    <!-- 文件系统类型 -->
    <fileSystem xfs="false"/>

    <!-- 全局文件过滤 -->
    <filter start="false">
        <exclude expression="(.*)\.svn"></exclude>
        <exclude expression="(.*)\.gz"></exclude>
        <exclude expression="^info/*"></exclude>
        <exclude expression="^static/*"></exclude>
    </filter>

    <!-- inotify 事件监控配置 -->
    <inotify>
        <delete start="true"/>
        <createFolder start="true"/>
        <createFile start="false"/>
        <closeWrite start="true"/>
        <moveFrom start="true"/>
        <moveTo start="true"/>
        <attrib start="false"/>
        <modify start="false"/>
    </inotify>

    <!-- ========== 核心配置区域 ========== -->
    <sersync>
        <!-- 监控路径配置 -->
        <localpath watch="/opt/tongbu">
            <remote ip="127.0.0.1" name="tongbu1"/>
            <!-- 【重要】name 字段含义：
                 SSH 模式：目标路径 /data/backup
                 Daemon 模式：模块名 backup -->
        </localpath>

        <!-- Rsync 配置 -->
        <rsync>
            <!-- rsync 参数 -->
            <commonParams params="-artuz"/>

            <!-- Daemon 模式认证 -->
            <auth start="false" users="root" passwordfile="/etc/rsync.pas"/>

            <!-- 自定义端口 -->
            <userDefinedPort start="false" port="874"/>

            <!-- 超时时间 -->
            <timeout start="false" time="100"/>

            <!-- SSH 模式开关 -->
            <ssh start="false"/>
        </rsync>

        <!-- 失败日志 -->
        <failLog path="/tmp/rsync_fail_log.sh" timeToExecute="60"/>

        <!-- 定时全量同步 -->
        <crontab start="false" schedule="600">
            <crontabfilter start="false">
                <exclude expression="*.php"></exclude>
                <exclude expression="info/*"></exclude>
            </crontabfilter>
        </crontab>

        <!-- 插件 -->
        <plugin start="false" name="command"/>
    </sersync>

    <!-- ========== 插件配置区域 ========== -->

    <!-- 命令插件 -->
    <plugin name="command">
        <param prefix="/bin/sh" suffix="" ignoreError="true"/>
        <filter start="false">
            <include expression="(.*)\.php"/>
            <include expression="(.*)\.sh"/>
        </filter>
    </plugin>

    <!-- Socket 插件 -->
    <plugin name="socket">
        <localpath watch="/opt/tongbu">
            <deshost ip="192.168.138.20" port="8009"/>
        </localpath>
    </plugin>

    <!-- CDN 刷新插件 -->
    <plugin name="refreshCDN">
        <localpath watch="/data0/htdocs/cms.xoyo.com/site/">
            <cdninfo domainname="ccms.chinacache.com" port="80" username="xxxx" passwd="xxxx"/>
            <sendurl base="http://pic.xoyo.com/cms"/>
            <regexurl regex="false" match="cms.xoyo.com/site([/a-zA-Z0-9]*).xoyo.com/images"/>
        </localpath>
    </plugin>
</head>
```

#### 1.3.2 配置项说明

**基础配置**：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `host hostip` | HTTP 管理接口 IP | localhost |
| `host port` | HTTP 管理接口端口 | 8008 |
| `debug start` | 是否启用调试模式 | false |
| `fileSystem xfs` | 文件系统是否为 XFS | false |

**inotify 事件监控**：

| 配置项 | 说明 | 推荐值 |
|--------|------|--------|
| `delete start` | 监控删除事件 | true |
| `createFolder start` | 监控目录创建 | true |
| `createFile start` | 监控文件创建 | true |
| `closeWrite start` | 监控文件写入完成 | true |
| `moveFrom start` | 监控文件移出 | true |
| `moveTo start` | 监控文件移入 | true |
| `attrib start` | 监控属性变化 | false |
| `modify start` | 监控修改事件 | false（用 closeWrite） |

**核心配置**（`<sersync>` 内）：

| 配置项 | 说明 | 备注 |
|--------|------|------|
| `localpath watch` | 监控的源目录 | 必填 |
| `remote ip` | 目标服务器 IP | 必填 |
| `remote name` | SSH模式：目标路径<br>Daemon模式：模块名 | 必填 |
| `commonParams` | rsync 参数 | `-artuz` 推荐 |
| `auth start` | 是否启用 Daemon 认证 | SSH=false, Daemon=true |
| `auth users` | Daemon 用户名 | Daemon 模式必填 |
| `auth passwordfile` | Daemon 密码文件 | Daemon 模式必填 |
| `userDefinedPort start` | 是否使用自定义端口 | SSH=true, Daemon=false |
| `userDefinedPort port` | 端口号 | SSH=22, Daemon=873 |
| `timeout start` | 是否启用超时 | true |
| `timeout time` | 超时时间（秒） | 100 |
| `ssh start` | 是否使用 SSH 模式 | SSH=true, Daemon=false |
| `failLog path` | 失败日志路径 | `/var/log/sersync/rsync_fail_log.sh` |
| `failLog timeToExecute` | 重试间隔（秒） | 60 |
| `crontab start` | 是否定时全量同步 | false（可选） |
| `crontab schedule` | 同步间隔（秒） | 600 |

---

## 🌐 第二部分：网络架构与环境说明

### 2.1 网络拓扑

```
Docker Bridge 网络：sersync-net (10.0.5.0/24)
├── 10.0.5.1   - 网关（Docker 网桥）
├── 10.0.5.40  - sersync-source（源端，运行 sersync）
│   ├── Volume: source-data → /data/source
│   └── 监控 /data/source 目录
└── 10.0.5.41  - sersync-backup（目标端，运行 rsync）
    ├── Volume: backup-data → /data/backup
    ├── 端口 873（Daemon 模式）
    └── 端口 22（SSH 模式）
```

### 2.2 Docker Compose 配置说明

```yaml
version: '3.8'

services:
  sersync-source:
    # 源端容器（运行 sersync）
    container_name: sersync-source
    hostname: sersync-source
    networks:
      sersync-net:
        ipv4_address: 10.0.5.40    # 固定 IP
    volumes:
      - source-data:/data/source    # 源数据卷

  sersync-backup:
    # 目标端容器（运行 rsync 服务）
    container_name: sersync-backup
    hostname: sersync-backup
    networks:
      sersync-net:
        ipv4_address: 10.0.5.41    # 固定 IP
    volumes:
      - backup-data:/data/backup    # 备份数据卷
    ports:
      - "873:873"                   # rsync daemon 端口
      - "8022:22"                   # SSH 端口

networks:
  sersync-net:
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.5.0/24
          gateway: 10.0.5.1

volumes:
  source-data:                      # 源数据卷
    driver: local
  backup-data:                      # 备份数据卷
    driver: local
```

---

## 🚀 第三部分：服务启动与配置

### 3.1 启动环境

```bash
# 1. 进入项目目录
cd /root/docker-man/05.realtime-sync/05.manual-sersync

# 2. 启动所有服务
docker compose up -d

# 3. 检查服务状态
docker compose ps

# 预期输出：
# NAME             IMAGE            STATUS
# sersync-source   sersync:latest   Up
# sersync-backup   sersync:latest   Up

# 4. 查看网络配置
docker network inspect 05manual-sersync_sersync-net

# 5. 验证 Volume 创建
docker volume ls | grep 05manual-sersync
```

---

## 📝 第四部分：配置方案选择

Sersync 支持两种传输模式，选择其一即可。

### 方案 A：SSH 模式（推荐学习）

- ✅ 数据加密传输
- ✅ 适合互联网和跨网段
- ✅ 配置相对简单（基于 SSH）
- ⚠️ 性能稍低（加密开销）

**跳转到**: [第五部分：SSH 模式配置](#-第五部分ssh-模式配置)

### 方案 B：Daemon 模式

- ✅ 高性能（无加密开销）
- ✅ 适合内网环境
- ⚠️ 明文传输（不加密）
- ⚠️ 配置稍复杂（需配置 rsyncd.conf）

**跳转到**: [第六部分：Daemon 模式配置](#-第六部分daemon-模式配置)

---

## 🔐 第五部分：SSH 模式配置

### 5.1 目标端（sersync-backup）配置

#### 5.1.1 进入容器

```bash
docker compose exec sersync-backup bash
```

#### 5.1.2 配置 SSH 服务

```bash
# 1. 生成 SSH 主机密钥
ssh-keygen -A

# 预期输出：
# ssh-keygen: generating new host keys: RSA DSA ECDSA ED25519

# 2. 设置 root 密码（用于 ssh-copy-id）
echo "root:root" | chpasswd

# 预期输出：（无输出表示成功）

# 3. 配置 SSH 允许 root 密码登录
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# 确保允许密码认证
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 4. 启动 SSH 服务
/usr/sbin/sshd

# 5. 验证 SSH 服务
ps aux | grep sshd
# 输出应包含：/usr/sbin/sshd

# 6. 验证配置
grep "PermitRootLogin" /etc/ssh/sshd_config
# 输出应包含：PermitRootLogin yes

grep "PasswordAuthentication" /etc/ssh/sshd_config
# 输出应包含：PasswordAuthentication yes
```

**⚠️ 重要说明**：
- 设置密码 `root:root` 仅用于学习环境
- 生产环境应使用强密码或禁用密码认证
- 本步骤是为了让 `ssh-copy-id` 能够工作

#### 5.1.3 创建测试数据

```bash
# 创建备份目录（Volume 已自动创建）
ls -ld /data/backup

# 创建测试文件（用于验证）
echo "Backup Server Ready" > /data/backup/test-backup.txt
```

---

### 5.2 源端（sersync-source）配置

#### 5.2.1 进入容器

```bash
# 新开终端
docker compose exec sersync-source bash
```

#### 5.2.2 配置 SSH 免密登录

```bash
# 1. 生成 SSH 密钥对
ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N ""

# 预期输出：
# Your identification has been saved in /root/.ssh/id_rsa
# Your public key has been saved in /root/.ssh/id_rsa.pub

# 2. 复制公钥到目标服务器
ssh-copy-id root@10.0.5.41

# 提示输入密码时，输入：root（默认密码）
# Are you sure you want to continue connecting (yes/no)? yes
# root@10.0.5.41's password: root

# 预期输出：
# Number of key(s) added: 1

# 3. 测试免密登录
ssh root@10.0.5.41 "echo 'SSH Connection Success'"

# 预期输出：
# SSH Connection Success
```

#### 5.2.3 创建源数据

```bash
# 创建测试文件
mkdir -p /data/source
echo "Source Test File 1" > /data/source/test1.txt
echo "Source Test File 2" > /data/source/test2.txt

# 创建子目录
mkdir -p /data/source/subdir
echo "Subdir File" > /data/source/subdir/test3.txt

# 查看目录结构
tree /data/source/ || find /data/source/ -type f
```

#### 5.2.4 编辑 Sersync 配置文件

```bash
# 备份原配置
cp /etc/sersync/confxml.xml /etc/sersync/confxml.xml.bak

# 编辑配置（基于官方模板，只修改必要参数）
cat > /etc/sersync/confxml.xml <<'EOF'
<?xml version="1.0" encoding="ISO-8859-1"?>
<head version="2.5">
    <!-- HTTP 管理接口（可选，学习环境禁用） -->
    <host hostip="localhost" port="8008"></host>

    <!-- 调试模式（生产环境建议关闭） -->
    <debug start="false"/>

    <!-- 文件系统类型（xfs 设为 true，ext4 设为 false） -->
    <fileSystem xfs="false"/>

    <!-- 全局文件过滤（在 rsync 同步前过滤） -->
    <filter start="true">
        <exclude expression="(.*)\.log"></exclude>
        <exclude expression="(.*)\.tmp"></exclude>
        <exclude expression="(.*)\.swp"></exclude>
    </filter>

    <!-- inotify 事件监控配置 -->
    <inotify>
        <delete start="true"/>          <!-- 监控删除事件 -->
        <createFolder start="true"/>    <!-- 监控目录创建 -->
        <createFile start="true"/>      <!-- 监控文件创建 -->
        <closeWrite start="true"/>      <!-- 监控文件写入完成 -->
        <moveFrom start="true"/>        <!-- 监控文件移出 -->
        <moveTo start="true"/>          <!-- 监控文件移入 -->
        <attrib start="false"/>         <!-- 不监控属性变化 -->
        <modify start="false"/>         <!-- 不监控修改（用 closeWrite 代替） -->
    </inotify>

    <!-- ==================== 核心配置区域 ==================== -->
    <sersync>
        <!-- 【修改 1】监控路径和目标服务器 -->
        <localpath watch="/data/source">
            <!-- SSH 模式：name 填写目标路径 -->
            <remote ip="sersync-backup" name="/data/backup"/>
        </localpath>

        <!-- 【修改 2】Rsync 参数配置 -->
        <rsync>
            <!-- rsync 参数：-a 归档 -r 递归 -t 保持时间 -z 压缩 -->
            <commonParams params="-artuz -e 'ssh -o StrictHostKeyChecking=no'"/>

            <!-- Daemon 模式认证（SSH 模式禁用） -->
            <auth start="false" users="root" passwordfile="/etc/rsync.pas"/>

            <!-- 自定义端口（SSH 使用 22） -->
            <userDefinedPort start="true" port="22"/>

            <!-- 超时设置 -->
            <timeout start="true" time="100"/>

            <!-- 【重要】启用 SSH 模式 -->
            <ssh start="true"/>
        </rsync>

        <!-- 失败日志（每 60 秒重试一次失败的同步） -->
        <failLog path="/var/log/sersync/rsync_fail_log.sh" timeToExecute="60"/>

        <!-- 定时全量同步（可选，每 600 秒一次） -->
        <crontab start="false" schedule="600">
            <crontabfilter start="false">
                <exclude expression="*.php"></exclude>
                <exclude expression="info/*"></exclude>
            </crontabfilter>
        </crontab>

        <!-- 插件（暂不启用） -->
        <plugin start="false" name="command"/>
    </sersync>

    <!-- ==================== 插件配置区域（可选） ==================== -->

    <!-- 命令插件：同步后执行自定义命令 -->
    <plugin name="command">
        <param prefix="/bin/sh" suffix="" ignoreError="true"/>
        <filter start="false">
            <include expression="(.*)\.php"/>
            <include expression="(.*)\.sh"/>
        </filter>
    </plugin>

    <!-- Socket 插件：通过 socket 通知其他服务 -->
    <plugin name="socket">
        <localpath watch="/opt/tongbu">
            <deshost ip="192.168.138.20" port="8009"/>
        </localpath>
    </plugin>

    <!-- CDN 刷新插件 -->
    <plugin name="refreshCDN">
        <localpath watch="/data0/htdocs/cms.xoyo.com/site/">
            <cdninfo domainname="ccms.chinacache.com" port="80" username="xxxx" passwd="xxxx"/>
            <sendurl base="http://pic.xoyo.com/cms"/>
            <regexurl regex="false" match="cms.xoyo.com/site([/a-zA-Z0-9]*).xoyo.com/images"/>
        </localpath>
    </plugin>
</head>
EOF

# 验证配置文件
cat /etc/sersync/confxml.xml
```

**⚠️ 配置说明**：
- ✅ 基于官方完整模板，保留所有配置项
- ✅ 【修改 1】：`localpath watch` 和 `remote ip/name`
- ✅ 【修改 2】：`<ssh start="true"/>` 启用 SSH 模式
- ✅ `<auth start="false"/>` SSH 模式不需要认证
- ✅ `<userDefinedPort>` 设置为 22
- ✅ 其他配置保持官方默认值

#### 5.2.5 创建日志目录

```bash
mkdir -p /var/log/sersync
```

#### 5.2.6 启动 Sersync

```bash
# 启动 sersync（前台运行，查看日志）
sersync -r -d -o /etc/sersync/confxml.xml

# 参数说明：
# -r : 在启动时先进行一次全量同步
# -d : 后台运行（daemon 模式）
# -o : 指定配置文件路径

# 预期输出：
# set the system param
# execute:echo 50000000 > /proc/sys/fs/inotify/max_user_watches
# execute:echo 327679 > /proc/sys/fs/inotify/max_queued_events
# parse the command param
# option: -r      rsync all the local files to the remote servers before the sersync work
# option: -d      run as a daemon
# option: -o      config xml name:  /etc/sersync/confxml.xml
# daemon thread num: 10
# parse xml config file
# host ip: 10.0.5.41  host port: 22
# start rsync...
# rsync working...
# please set right filter!
# please set right filter!
# please set right filter!
# please set right filter!
# daemon thread num: 10
# sersync: the inotify(or rotary) module has been finished
```

**⚠️ 如果输出 "please set right filter!" 是正常的**，表示过滤规则已启用。

#### 5.2.7 验证 Sersync 运行

```bash
# 查看 sersync 进程
ps aux | grep sersync

# 预期输出：
# root  123  0.0  0.1  sersync -r -d -o /etc/sersync/confxml.xml

# 查看同步日志
tail -f /var/log/sersync/rsync_fail_log.sh
# (如果没有失败，文件可能不存在，这是正常的)
```

---

### 5.3 测试实时同步（SSH 模式）

#### 5.3.1 测试文件创建

```bash
# 在源端容器中（sersync-source）

# 创建新文件
echo "New File $(date)" > /data/source/new-file.txt

# 等待 1-2 秒（sersync 自动同步）
sleep 2

# 在目标端验证
ssh root@10.0.5.41 "ls -l /data/backup/new-file.txt"

# 预期输出：
# -rw-r--r-- 1 root root 42 Oct  9 12:00 /data/backup/new-file.txt
```

#### 5.3.2 测试文件修改

```bash
# 修改文件
echo "Modified Content $(date)" >> /data/source/test1.txt

sleep 2

# 验证
ssh root@10.0.5.41 "cat /data/backup/test1.txt"
```

#### 5.3.3 测试文件删除

```bash
# 删除文件（需要配置 --delete）
rm /data/source/test2.txt

sleep 2

# 验证（如果配置了 --delete，文件应该被删除）
ssh root@10.0.5.41 "ls /data/backup/test2.txt"
# 输出：No such file or directory（如果配置了删除）
```

**⚠️ 注意**：Sersync 默认**不会删除目标端文件**。如果需要镜像同步（删除目标端多余文件），需要在 `<commonParams>` 中添加 `--delete` 参数：

```xml
<commonParams params="-az --delete"/>
```

#### 5.3.4 测试大量文件

```bash
# 创建 100 个文件
for i in {1..100}; do
    echo "Test File $i" > /data/source/batch-$i.txt
done

# 等待同步完成
sleep 5

# 统计目标端文件数
ssh root@10.0.5.41 "ls /data/backup/batch-*.txt | wc -l"

# 预期输出：
# 100
```

---

**SSH 模式配置完成！** 🎉

如需配置 Daemon 模式，请继续阅读 [第六部分](#6-daemon-模式配置)。

---

## 🏭 第六部分：Daemon 模式配置

### 6.1 目标端（sersync-backup）配置

#### 6.1.1 进入容器

```bash
docker compose exec sersync-backup bash
```

#### 6.1.2 创建 rsync daemon 配置

```bash
# 创建配置目录
mkdir -p /etc/rsync

# 创建主配置文件
cat > /etc/rsync/rsyncd.conf <<'EOF'
# Rsync Daemon 配置文件

# 全局配置
uid = root
gid = root
use chroot = no
port = 873
max connections = 10
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
lock file = /var/run/rsync.lock

# 欢迎信息（可选）
motd file = /etc/rsync/rsyncd.motd

# 模块定义
[backup]
    comment = Sersync Backup Module
    path = /data/backup
    read only = no
    list = yes
    auth users = rsyncuser
    secrets file = /etc/rsync/rsyncd.secrets
    hosts allow = 10.0.5.0/24
    hosts deny = *
EOF

# 查看配置
cat /etc/rsync/rsyncd.conf
```

#### 6.1.3 创建密码文件

```bash
# 创建密码文件
cat > /etc/rsync/rsyncd.secrets <<'EOF'
rsyncuser:rsyncpass123
EOF

# 设置正确权限（必须）
chmod 600 /etc/rsync/rsyncd.secrets

# 验证权限
ls -l /etc/rsync/rsyncd.secrets
# 输出：-rw------- 1 root root 23 ... rsyncd.secrets
```

#### 6.1.4 创建欢迎信息（可选）

```bash
cat > /etc/rsync/rsyncd.motd <<'EOF'
========================================
Sersync Backup Server
Contact: admin@example.com
========================================
EOF
```

#### 6.1.5 启动 rsync daemon

```bash
# 启动 daemon
rsync --daemon --no-detach --config=/etc/rsync/rsyncd.conf --log-file=/dev/stderr

# 预期输出：（服务启动，监听 873 端口，无错误信息）

# 验证服务
ps aux | grep rsync
# 输出应包含：rsync --daemon

# 检查监听端口
ss -tlnp | grep 873
# 输出应包含：LISTEN  0.0.0.0:873
```

---

### 6.2 源端（sersync-source）配置

#### 6.2.1 进入容器

```bash
# 新开终端
docker compose exec sersync-source bash
```

#### 6.2.2 创建客户端密码文件

```bash
# 创建密码文件（仅包含密码）
mkdir -p /etc/rsync
echo "rsyncpass123" > /etc/rsync/rsync.pass

# 设置权限
chmod 600 /etc/rsync/rsync.pass

# 验证
cat /etc/rsync/rsync.pass
```

#### 6.2.3 测试连接

```bash
# 列出服务器模块
rsync rsync://10.0.5.41/
rsync rsync://sersync-backup/
rsync sersync-backup::


# 预期输出：
# ========================================
# Sersync Backup Server
# Contact: admin@example.com
# ========================================
# backup         Sersync Backup Module

# 测试认证
rsync --password-file=/etc/rsync/rsync.pass rsync://rsyncuser@10.0.5.41/backup/
rsync --password-file=/etc/rsync/rsync.pass rsyncuser@sersync-backup::backup/

# 预期输出：（列出 backup 模块的内容，应为空或有之前的测试文件）
```

#### 6.2.4 编辑 Sersync 配置文件

```bash
# 备份原配置
cp /etc/sersync/confxml.xml /etc/sersync/confxml.xml.bak

# 创建 Daemon 模式配置（基于官方模板，只修改必要参数）
cat > /etc/sersync/confxml.xml <<'EOF'
<?xml version="1.0" encoding="ISO-8859-1"?>
<head version="2.5">
    <!-- HTTP 管理接口（可选，学习环境禁用） -->
    <host hostip="localhost" port="8008"></host>

    <!-- 调试模式（生产环境建议关闭） -->
    <debug start="false"/>

    <!-- 文件系统类型（xfs 设为 true，ext4 设为 false） -->
    <fileSystem xfs="false"/>

    <!-- 全局文件过滤（在 rsync 同步前过滤） -->
    <filter start="true">
        <exclude expression="(.*)\.log"></exclude>
        <exclude expression="(.*)\.tmp"></exclude>
        <exclude expression="(.*)\.swp"></exclude>
    </filter>

    <!-- inotify 事件监控配置 -->
    <inotify>
        <delete start="true"/>          <!-- 监控删除事件 -->
        <createFolder start="true"/>    <!-- 监控目录创建 -->
        <createFile start="true"/>      <!-- 监控文件创建 -->
        <closeWrite start="true"/>      <!-- 监控文件写入完成 -->
        <moveFrom start="true"/>        <!-- 监控文件移出 -->
        <moveTo start="true"/>          <!-- 监控文件移入 -->
        <attrib start="false"/>         <!-- 不监控属性变化 -->
        <modify start="false"/>         <!-- 不监控修改（用 closeWrite 代替） -->
    </inotify>

    <!-- ==================== 核心配置区域 ==================== -->
    <sersync>
        <!-- 【修改 1】监控路径和目标服务器 -->
        <localpath watch="/data/source">
            <!-- Daemon 模式：name 填写模块名（不是路径！） -->
            <remote ip="10.0.5.41" name="backup"/>
        </localpath>

        <!-- 【修改 2】Rsync 参数配置 -->
        <rsync>
            <!-- rsync 参数：-a 归档 -r 递归 -t 保持时间 -z 压缩  一定不能加 -e 'ssh -o StrictHostKeyChecking=no' 这个一加，就算下面配置了rsync service,也强制走了ssh-->
            <commonParams params="-artuz"/>

            <!-- 【重要】Daemon 模式认证（启用） -->
            <auth start="true" users="rsyncuser" passwordfile="/etc/rsync/rsync.pass"/>

            <!-- 自定义端口（Daemon 默认 873，可不设置） -->
            <userDefinedPort start="false" port="874"/>

            <!-- 超时设置 -->
            <timeout start="true" time="100"/>

            <!-- 【重要】关闭 SSH 模式 -->
            <ssh start="false"/>
        </rsync>

        <!-- 失败日志（每 60 秒重试一次失败的同步） -->
        <failLog path="/var/log/sersync/rsync_fail_log.sh" timeToExecute="60"/>

        <!-- 定时全量同步（可选，每 600 秒一次） -->
        <crontab start="false" schedule="600">
            <crontabfilter start="false">
                <exclude expression="*.php"></exclude>
                <exclude expression="info/*"></exclude>
            </crontabfilter>
        </crontab>

        <!-- 插件（暂不启用） -->
        <plugin start="false" name="command"/>
    </sersync>

    <!-- ==================== 插件配置区域（可选） ==================== -->

    <!-- 命令插件：同步后执行自定义命令 -->
    <plugin name="command">
        <param prefix="/bin/sh" suffix="" ignoreError="true"/>
        <filter start="false">
            <include expression="(.*)\.php"/>
            <include expression="(.*)\.sh"/>
        </filter>
    </plugin>

    <!-- Socket 插件：通过 socket 通知其他服务 -->
    <plugin name="socket">
        <localpath watch="/opt/tongbu">
            <deshost ip="192.168.138.20" port="8009"/>
        </localpath>
    </plugin>

    <!-- CDN 刷新插件 -->
    <plugin name="refreshCDN">
        <localpath watch="/data0/htdocs/cms.xoyo.com/site/">
            <cdninfo domainname="ccms.chinacache.com" port="80" username="xxxx" passwd="xxxx"/>
            <sendurl base="http://pic.xoyo.com/cms"/>
            <regexurl regex="false" match="cms.xoyo.com/site([/a-zA-Z0-9]*).xoyo.com/images"/>
        </localpath>
    </plugin>
</head>
EOF

# 验证配置
cat /etc/sersync/confxml.xml
```

**⚠️ 配置说明**：
- ✅ 基于官方完整模板，保留所有配置项
- ✅ 【修改 1】：`remote name="backup"` 使用模块名（非路径）
- ✅ 【修改 2】：`<ssh start="false"/>` 关闭 SSH 模式
- ✅ `<auth start="true"/>` 启用 Daemon 认证
- ✅ `passwordfile="/etc/rsync/rsync.pass"` 密码文件路径
- ✅ 其他配置保持官方默认值

#### 6.2.5 创建源数据

```bash
# 如果还没有，创建测试文件
mkdir -p /data/source
echo "Daemon Mode Test 1" > /data/source/daemon-test1.txt
echo "Daemon Mode Test 2" > /data/source/daemon-test2.txt
```

#### 6.2.6 启动 Sersync

```bash
# 创建日志目录
mkdir -p /var/log/sersync

# 启动 sersync
sersync -r -d -o /etc/sersync/confxml.xml

# 预期输出：
# set the system param
# ...
# host ip: 10.0.5.41  host port: 874
# start rsync...
# rsync working...
# daemon thread num: 10
# sersync: the inotify(or rotary) module has been finished

# 验证进程
ps aux | grep sersync
```

---

### 6.3 测试实时同步（Daemon 模式）

#### 6.3.1 测试文件创建

```bash
# 在源端（sersync-source）

# 创建新文件
echo "Daemon Sync Test $(date)" > /data/source/daemon-sync.txt

sleep 2

# 在目标端验证
rsync --password-file=/etc/rsync/rsync.pass rsync://rsyncuser@10.0.5.41/backup/ | grep daemon-sync.txt

# 或直接登录目标端查看
# docker compose exec sersync-backup ls -l /data/backup/daemon-sync.txt
```

#### 6.3.2 测试批量同步

```bash
# 创建 50 个文件
for i in {1..50}; do
    echo "Daemon Batch $i" > /data/source/daemon-batch-$i.txt
done

sleep 5

# 验证
rsync --password-file=/etc/rsync/rsync.pass rsync://rsyncuser@10.0.5.41/backup/ | grep daemon-batch | wc -l

# 预期输出：
# 50
```

---

**Daemon 模式配置完成！** 🎉

---

## 📊 第七部分：配置选项详解

### 7.1 核心配置项

#### 7.1.1 localpath 配置

```xml
<localpath watch="/data/source">
    <remote ip="10.0.5.41" name="/data/backup"/>
</localpath>
```

| 属性 | 说明 | 示例 |
|------|------|------|
| `watch` | 监控的本地目录 | `/data/source` |
| `ip` | 目标服务器 IP | `10.0.5.41` |
| `name` | SSH模式：目标路径<br>Daemon模式：模块名 | `/data/backup`<br>`backup` |

#### 7.1.2 rsync 配置

```xml
<rsync>
    <commonParams params="-az"/>
    <auth start="true" users="rsyncuser" passwordfile="/etc/rsync/rsync.pass"/>
    <userDefinedPort start="true" port="22"/>
    <timeout start="true" time="100"/>
    <ssh start="true"/>
</rsync>
```

| 选项 | 说明 | SSH模式 | Daemon模式 |
|------|------|---------|-----------|
| `commonParams` | rsync 参数 | `-az` | `-az` |
| `auth start` | Daemon 认证 | `false` | `true` |
| `auth users` | Daemon 用户名 | - | `rsyncuser` |
| `auth passwordfile` | 密码文件路径 | - | `/etc/rsync/rsync.pass` |
| `userDefinedPort` | 目标端口 | `22` | `874`（默认873） |
| `timeout` | 超时时间（秒） | `100` | `100` |
| `ssh start` | SSH 模式开关 | `true` | `false` |

#### 7.1.3 filter 配置

```xml
<filter start="true">
    <exclude expression="(.*)\.log"/>
    <exclude expression="(.*)\.tmp"/>
    <exclude expression="(.*)\.swp"/>
</filter>
```

| 属性 | 说明 | 示例 |
|------|------|------|
| `start` | 是否启用过滤 | `true` / `false` |
| `expression` | 正则表达式 | `(.*)\.log` 排除所有 .log 文件 |

**常用过滤规则**：

```xml
<!-- 排除日志文件 -->
<exclude expression="(.*)\.log"/>

<!-- 排除临时文件 -->
<exclude expression="(.*)\.tmp"/>
<exclude expression="(.*)\.swp"/>

<!-- 排除隐藏文件 -->
<exclude expression="^\..*"/>

<!-- 排除特定目录 -->
<exclude expression="cache/.*"/>
<exclude expression="tmp/.*"/>

<!-- 排除特定文件名 -->
<exclude expression=".*test.*"/>
```

#### 7.1.4 failLog 配置

```xml
<failLog path="/var/log/sersync/rsync_fail_log.sh" timeToExecute="60"/>
```

| 属性 | 说明 | 推荐值 |
|------|------|--------|
| `path` | 失败日志脚本路径 | `/var/log/sersync/rsync_fail_log.sh` |
| `timeToExecute` | 重试间隔（秒） | `60` |

**工作原理**：
- 同步失败的文件会记录到此脚本
- Sersync 会定期执行此脚本重试同步
- 脚本格式：`rsync 命令`

#### 7.1.5 crontab 配置

```xml
<crontab start="false" schedule="600">
    <crontabfilter start="false">
        <exclude expression="*.log"/>
    </crontabfilter>
</crontab>
```

| 属性 | 说明 | 推荐值 |
|------|------|--------|
| `start` | 是否启用定时全量同步 | `false`（默认） |
| `schedule` | 同步间隔（秒） | `600`（10分钟） |

**用途**：定期执行全量同步，防止遗漏。

---

### 7.2 Sersync 命令选项

```bash
sersync [options]

常用选项：
  -r          启动时先进行一次全量同步（推荐）
  -d          后台运行（daemon 模式）
  -o FILE     指定配置文件路径
  -n NUM      设置守护线程数（默认 10）
  -m          不监控修改事件（仅监控创建和删除）
  -h          显示帮助信息
```

**示例**：

```bash
# 前台运行（调试）
sersync -r -o /etc/sersync/confxml.xml

# 后台运行（生产）
sersync -r -d -o /etc/sersync/confxml.xml

# 设置线程数
sersync -r -d -n 20 -o /etc/sersync/confxml.xml

# 不监控修改事件
sersync -r -d -m -o /etc/sersync/confxml.xml
```

---

## 🔧 第八部分：故障排除

### 8.1 常见问题

#### 问题 1：Sersync 启动失败

**现象**：
```
execute error
```

**排查**：
```bash
# 检查配置文件语法
cat /etc/sersync/confxml.xml

# 检查 XML 格式是否正确
# 1. 所有标签是否闭合
# 2. 属性值是否使用引号
# 3. 编码是否正确（ISO-8859-1）

# 手动测试 rsync 命令
rsync -az /data/source/ root@10.0.5.41:/data/backup/  # SSH 模式
rsync -az /data/source/ rsync://rsyncuser@10.0.5.41/backup/  # Daemon 模式
```

#### 问题 2：文件不同步

**现象**：创建文件后，目标端没有文件

**排查**：
```bash
# 1. 检查 sersync 进程是否运行
ps aux | grep sersync

# 2. 查看 sersync 是否监控到事件
# （前台运行 sersync 查看日志）
sersync -r -o /etc/sersync/confxml.xml

# 3. 手动测试 rsync
rsync -az /data/source/ root@10.0.5.41:/data/backup/

# 4. 检查 inotify 监听
# 安装 inotify-tools
ls -l /proc/sys/fs/inotify/

# 查看监听数量
cat /proc/sys/fs/inotify/max_user_watches
```

#### 问题 3：SSH 模式认证失败

##### 3.1 SSH 服务未启动

**现象**：
```
ssh: connect to host 10.0.5.41 port 22: Connection refused
```

**排查**：
```bash
# 1. 检查目标端 SSH 服务
docker compose exec sersync-backup ps aux | grep sshd

# 2. 如果没有输出，启动 SSH 服务
docker compose exec sersync-backup ssh-keygen -A
docker compose exec sersync-backup /usr/sbin/sshd

# 3. 验证
docker compose exec sersync-backup ss -tlnp | grep 22
```

##### 3.2 ssh-copy-id 失败（⚠️ 容器环境常见问题）

**现象**：
```
Permission denied (publickey,gssapi-keyex,gssapi-with-mic)
```
或
```
Permission denied (publickey)
```
或
```
root@10.0.5.41's password: <输入密码无效>
```

**原因**：
1. **容器默认没有设置 root 密码**
2. **SSH 配置默认禁止 root 密码登录**（PermitRootLogin）
3. **SSH 配置默认可能禁止密码认证**（PasswordAuthentication）

**完整解决方案**（在目标端 sersync-backup 容器执行）：

```bash
# 1. 设置 root 密码
echo "root:root" | chpasswd

# 2. 配置允许 root 登录
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# 3. 配置允许密码认证
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 4. 重启 SSH 服务
pkill sshd
/usr/sbin/sshd

# 5. 验证配置
grep "PermitRootLogin" /etc/ssh/sshd_config  # 应输出：PermitRootLogin yes
grep "PasswordAuthentication" /etc/ssh/sshd_config  # 应输出：PasswordAuthentication yes

# 6. 现在从源端重新执行 ssh-copy-id
# 在 sersync-source 容器：
ssh-copy-id root@10.0.5.41
# 输入密码：root
```

**⚠️ 重要提示**：
- 这是学习环境配置，生产环境应使用强密码
- 生产环境建议禁用密码认证，仅使用密钥认证

##### 3.3 SSH 密钥未配置

**现象**：免密登录不工作

**排查**：
```bash
# 1. 检查源端 SSH 密钥
ls -l /root/.ssh/id_rsa*

# 2. 测试 SSH 连接
ssh root@10.0.5.41 "echo test"

# 3. 检查目标端 authorized_keys
docker compose exec sersync-backup cat /root/.ssh/authorized_keys

# 4. 检查目标端 SSH 配置
docker compose exec sersync-backup grep "PubkeyAuthentication" /etc/ssh/sshd_config
```

#### 问题 4：Daemon 模式认证失败

**现象**：
```
@ERROR: auth failed on module backup
```

**排查**：
```bash
# 1. 检查密码文件
cat /etc/rsync/rsync.pass

# 2. 检查密码文件权限
ls -l /etc/rsync/rsync.pass
# 必须是 -rw-------（600）

# 3. 检查服务端密码文件
docker compose exec sersync-backup cat /etc/rsync/rsyncd.secrets

# 4. 手动测试
rsync --password-file=/etc/rsync/rsync.pass rsync://rsyncuser@10.0.5.41/backup/
```

#### 问题 5：Permission denied

**现象**：
```
rsync: [receiver] mkstemp failed: Permission denied (13)
```

**原因**：Daemon 模式缺少 uid/gid 配置

**解决**：
```bash
# 编辑 rsyncd.conf，添加：
uid = root
gid = root

# 重启 rsync daemon
pkill rsync
rsync --daemon --config=/etc/rsync/rsyncd.conf
```

---

### 8.2 调试技巧

#### 8.2.1 前台运行 Sersync

```bash
# 不使用 -d 参数，前台运行查看日志
sersync -r -o /etc/sersync/confxml.xml

# 创建文件测试
echo "test" > /data/source/debug-test.txt

# 观察 sersync 输出
```

#### 8.2.2 查看 rsync 详细日志

修改配置文件，添加 `-vv` 参数：

```xml
<commonParams params="-azvv"/>
```

#### 8.2.3 查看失败日志

```bash
# 查看失败日志脚本
cat /var/log/sersync/rsync_fail_log.sh

# 手动执行重试
bash /var/log/sersync/rsync_fail_log.sh
```

#### 8.2.4 inotify 限制调整

```bash
# 查看当前限制
cat /proc/sys/fs/inotify/max_user_watches
cat /proc/sys/fs/inotify/max_queued_events

# 临时调整（重启失效）
echo 50000000 > /proc/sys/fs/inotify/max_user_watches
echo 327679 > /proc/sys/fs/inotify/max_queued_events

# 永久调整（宿主机）
# /etc/sysctl.conf 添加：
# fs.inotify.max_user_watches=50000000
# fs.inotify.max_queued_events=327679
```

---

## 🎓 第九部分：学习总结

### 9.1 核心知识点

1. **Sersync 工作原理**：
   - 基于 inotify 监控文件系统事件
   - 使用队列管理变化的文件
   - 多线程调用 rsync 同步
   - 支持失败重试机制

2. **配置文件结构**：
   - XML 格式配置
   - localpath 监控路径
   - remote 目标配置
   - rsync 参数配置
   - filter 过滤规则

3. **两种传输模式**：
   - SSH 模式：加密、需要 SSH 密钥
   - Daemon 模式：高性能、需要 rsyncd.conf

4. **关键命令**：
   ```bash
   # 启动 sersync
   sersync -r -d -o /etc/sersync/confxml.xml

   # SSH 模式测试
   ssh root@10.0.5.41 "echo test"

   # Daemon 模式测试
   rsync rsync://10.0.5.41/
   ```

### 9.2 最佳实践

- ✅ 启动时使用 `-r` 进行初始全量同步
- ✅ 使用 `-d` 后台运行
- ✅ 配置合理的过滤规则
- ✅ 监控失败日志
- ✅ 定期检查同步状态
- ⚠️ 大规模文件同步考虑使用 lsyncd
- ⚠️ 生产环境充分测试

### 9.3 常见问题解决

| 问题 | 原因 | 解决方法 |
|------|------|----------|
| 启动失败 | XML 语法错误 | 检查配置文件格式 |
| 不同步 | sersync 未运行 | 检查进程，重启 |
| ssh-copy-id 失败 | root 无密码/SSH 配置 | chpasswd + 修改 sshd_config |
| SSH 免密失败 | 密钥未配置 | 配置 SSH 免密 |
| Daemon 认证失败 | 密码文件权限 | chmod 600 |
| Permission denied | uid/gid 未配置 | 配置 uid=root |

---

## 🧹 第十部分：清理环境

```bash
# 1. 停止 sersync
docker compose exec sersync-source pkill sersync

# 2. 停止所有容器
docker compose down

# 3. 删除 Volume（会删除数据）
docker compose down --volumes

# 4. 完全清理（包括镜像）
docker compose down --volumes --rmi all
```

---

**完成时间**: 2024-10-09
**文档版本**: v1.0
**适用环境**: 05.manual-sersync
**维护者**: docker-man 项目组
