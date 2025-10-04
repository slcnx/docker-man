$TTL 86400                                         ; 默认 TTL 86400秒(1天)
@ IN SOA @ admin.magedu.com (                     ; SOA 记录定义
    123                                            ; 序列号
    3H                                             ; 刷新时间 3小时
    15M                                            ; 重试时间 15分钟
    1D                                             ; 过期时间 1天
    1W                                             ; 最小 TTL 1周
)

       NS ns1                                      ; 权威 NS 记录
ns1 IN A 10.0.0.13                                ; NS 服务器 IP
www IN A 10.0.0.14                                ; www 主机记录
*   IN A 10.0.0.199                               ; 通配符记录，匹配所有未定义主机