#!/bin/bash
# rsyslog 设施（Facility）和优先级（Priority）测试脚本

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   rsyslog 设施（Facility）和优先级（Priority）测试  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo

# 等待 rsyslog 启动
sleep 2

# ============================================================
# 测试 1: 不同设施的日志
# ============================================================
echo -e "${CYAN}[测试 1] 测试不同设施（Facility）的日志${NC}"
echo "------------------------------------------------------"

echo "发送日志到不同设施..."
logger -p auth.info "AUTH: User login attempt"
logger -p authpriv.notice "AUTHPRIV: Password changed successfully"
logger -p cron.info "CRON: Job started - backup.sh"
logger -p daemon.info "DAEMON: Service started"
logger -p kern.warning "KERN: Kernel warning message"
logger -p mail.info "MAIL: Email sent successfully"
logger -p user.info "USER: User application log"
logger -p local0.info "LOCAL0: Custom application log"
logger -p local1.info "LOCAL1: Web server log"
logger -p local2.info "LOCAL2: Database log"
logger -p syslog.info "SYSLOG: Rsyslog internal message"

sleep 1
echo -e "${GREEN}✓${NC} 日志已发送"
echo

# ============================================================
# 测试 2: 不同优先级的日志
# ============================================================
echo -e "${CYAN}[测试 2] 测试不同优先级（Priority）的日志${NC}"
echo "------------------------------------------------------"

echo "发送不同优先级的日志到 user 设施..."
logger -p user.emerg "EMERG (0): System is unusable"
logger -p user.alert "ALERT (1): Action must be taken immediately"
logger -p user.crit "CRIT (2): Critical conditions"
logger -p user.err "ERR (3): Error conditions"
logger -p user.warning "WARNING (4): Warning conditions"
logger -p user.notice "NOTICE (5): Normal but significant"
logger -p user.info "INFO (6): Informational messages"
logger -p user.debug "DEBUG (7): Debug-level messages"

sleep 1
echo -e "${GREEN}✓${NC} 日志已发送"
echo

# ============================================================
# 测试 3: 模拟 SSH 日志（authpriv 设施）
# ============================================================
echo -e "${CYAN}[测试 3] 模拟 SSH 日志（authpriv 设施）${NC}"
echo "------------------------------------------------------"

echo "模拟 sshd 日志..."
logger -t "sshd[12345]" -p authpriv.info "Accepted password for root from 192.168.1.100 port 22 ssh2"
logger -t "sshd[12346]" -p authpriv.notice "pam_unix(sshd:session): session opened for user root"
logger -t "sshd[12347]" -p authpriv.warning "Failed password for invalid user admin from 192.168.1.200"
logger -t "sshd[12348]" -p authpriv.err "error: PAM: Authentication failure for illegal user test"

sleep 1
echo -e "${GREEN}✓${NC} SSH 日志已发送"
echo

# ============================================================
# 测试 4: 模拟 Cron 日志（cron 设施）
# ============================================================
echo -e "${CYAN}[测试 4] 模拟 Cron 日志（cron 设施）${NC}"
echo "------------------------------------------------------"

echo "模拟 cron 日志..."
logger -t "CRON[23456]" -p cron.info "(root) CMD (/usr/local/bin/backup.sh)"
logger -t "CRON[23457]" -p cron.notice "(apache) CMD (/usr/local/bin/log-rotate.sh)"
logger -t "CRON[23458]" -p cron.warning "Job took 5 minutes (expected < 2)"
logger -t "CRON[23459]" -p cron.err "Job failed: exit code 1"

sleep 1
echo -e "${GREEN}✓${NC} Cron 日志已发送"
echo

# ============================================================
# 测试 5: 自定义应用使用 local 设施
# ============================================================
echo -e "${CYAN}[测试 5] 自定义应用使用 local 设施${NC}"
echo "------------------------------------------------------"

echo "模拟不同应用使用 local 设施..."
logger -t "nginx" -p local0.info "Nginx started on port 80"
logger -t "nginx" -p local0.err "Failed to bind port 443: Address already in use"

logger -t "mysql" -p local1.info "MySQL server started"
logger -t "mysql" -p local1.warning "Slow query detected: 5.2 seconds"

logger -t "webapp" -p local2.info "User registration: user@example.com"
logger -t "webapp" -p local2.err "Database connection timeout"

logger -t "monitoring" -p local3.info "CPU usage: 45%"
logger -t "monitoring" -p local3.warning "Memory usage: 85%"

sleep 1
echo -e "${GREEN}✓${NC} 自定义应用日志已发送"
echo

# ============================================================
# 查看日志结果
# ============================================================
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   日志查看                                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo

echo -e "${CYAN}[1] authpriv 设施（SSH 等认证日志）${NC}"
echo "文件: /var/log/auth.log"
tail -5 /var/log/auth.log 2>/dev/null || echo "文件不存在"
echo

echo -e "${CYAN}[2] cron 设施（计划任务日志）${NC}"
echo "文件: /var/log/cron.log"
tail -5 /var/log/cron.log 2>/dev/null || echo "文件不存在"
echo

echo -e "${CYAN}[3] user 设施（用户应用日志，包含所有优先级）${NC}"
echo "文件: /var/log/user.log"
tail -10 /var/log/user.log 2>/dev/null || echo "文件不存在"
echo

echo -e "${CYAN}[4] local0 设施（Nginx 日志）${NC}"
echo "文件: /var/log/local0.log"
cat /var/log/local0.log 2>/dev/null || echo "文件不存在"
echo

echo -e "${CYAN}[5] local1 设施（MySQL 日志）${NC}"
echo "文件: /var/log/local1.log"
cat /var/log/local1.log 2>/dev/null || echo "文件不存在"
echo

echo -e "${CYAN}[6] local2 设施（Web 应用日志）${NC}"
echo "文件: /var/log/local2.log"
cat /var/log/local2.log 2>/dev/null || echo "文件不存在"
echo

echo -e "${CYAN}[7] 所有日志汇总（messages）${NC}"
echo "文件: /var/log/messages"
tail -10 /var/log/messages 2>/dev/null || echo "文件不存在"
echo

# ============================================================
# journalctl 查看
# ============================================================
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   journalctl 查看（带元数据）                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo

echo -e "${CYAN}[1] 按设施过滤（SYSLOG_FACILITY）${NC}"
echo "查看 authpriv (10) 设施的日志:"
journalctl SYSLOG_FACILITY=10 --since "1 minute ago" --no-pager | tail -5
echo

echo -e "${CYAN}[2] 按优先级过滤（PRIORITY）${NC}"
echo "查看 error (3) 及以上优先级的日志:"
journalctl PRIORITY=0..3 --since "1 minute ago" --no-pager | tail -5
echo

echo -e "${CYAN}[3] 组合过滤（设施 + 优先级）${NC}"
echo "查看 cron 设施的错误日志:"
journalctl SYSLOG_FACILITY=9 PRIORITY=3 --since "1 minute ago" --no-pager
echo

# ============================================================
# 统计信息
# ============================================================
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   统计信息                                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo

echo -e "${CYAN}各设施的日志数量（journalctl）：${NC}"
journalctl --since "1 minute ago" -o json --no-pager 2>/dev/null | \
  jq -r '.SYSLOG_FACILITY' | sort | uniq -c | sort -rn || echo "jq 未安装"
echo

echo -e "${CYAN}各优先级的日志数量（journalctl）：${NC}"
journalctl --since "1 minute ago" -o json --no-pager 2>/dev/null | \
  jq -r '.PRIORITY' | sort | uniq -c | sort -n || echo "jq 未安装"
echo

echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   测试完成！                                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
