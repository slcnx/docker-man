# DNS服务命令分类总结

## **软件包管理**
```bash
yum repolist                      # 列出仓库
yum install bind                  # 安装DNS服务
yum install net-tools             # 安装网络工具
yum install psmisc                # 安装进程工具
yum install procps-ng             # 安装ps命令
yum install vim                   # 安装vim编辑器
yum install man                   # 安装手册页
yum install iproute               # 安装ip命令
yum install file                  # 安装file命令
yum install nscd                  # 安装名称服务缓存守护程序
yum whatprovides '*bin/ps'       # 查找提供特定文件的包
rpm -ql bind                      # 列出包文件
```

## **DNS服务管理**
```bash
/usr/sbin/named-checkconf -z /etc/named.conf   # 检查配置
/usr/sbin/named -u named -c /etc/named.conf    # 启动named
rndc reload                                     # 重新加载配置
rndc status                                     # 查看状态
rndc stop                                       # 停止服务
systemctl cat named                             # 查看服务单元文件
/usr/libexec/generate-rndc-key.sh              # 生成rndc密钥
bash -x /usr/libexec/generate-rndc-key.sh      # 调试生成密钥脚本
```

## **DNS查询测试**
```bash
dig www.magedu.com                # DNS查询
dig www.magedu.com @127.0.0.1     # 指定DNS服务器查询（本地）
dig www.magedu.com @10.10.0.2     # 指定IP查询
```

## **配置文件查看/编辑**
```bash
cat /etc/named.conf                           # 查看DNS主配置
cat /usr/lib/systemd/system/named.service     # 查看服务文件
cat /etc/sysconfig/named                      # 查看环境配置
cat /var/named/named.ca                       # 查看根服务器配置
cat /var/named/named.localhost                # 查看本地域配置
vim /etc/named.conf                           # 编辑DNS配置
vim /etc/resolv.conf                          # 编辑解析器配置
man named.conf                                # 查看配置文件手册
```

## **网络状态检查**
```bash
ss -tnl                  # 查看TCP监听端口
netstat -tnl             # 查看TCP监听端口（传统工具）
ss -tn                   # 查看TCP连接
ip a                     # 查看网络接口
ping www.baidu.com       # 测试网络连通性
```

## **进程管理**
```bash
ps -ef                   # 查看所有进程
ps -ef | grep named      # 查找named进程
kill -9 105              # 强制终止进程
```

## **日志和调试**
```bash
ls /var/log/named/                    # 查看日志目录
tail -f /var/log/named/query.log      # 实时查看查询日志
cat /var/named/data/named.run         # 查看运行时数据
ls /var/named/data/                   # 查看数据目录
```

## **目录和文件管理**
```bash
install -dv -o named -g named /var/log/named   # 创建日志目录并设置权限
ls -ld /var/log/named                          # 查看目录详细信息
file /var/named/data/named.run                 # 查看文件类型
```

## **名称服务缓存（nscd）**
```bash
nscd                     # 启动名称服务缓存守护程序
nscd -g                  # 查看缓存统计信息
```
 
## **其他命令**
```bash
history -w               # 保存命令历史
```
