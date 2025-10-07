$TTL 86400
@ IN SOA magedu-dns.magedu.com. admin.magedu.com. (
	128		; 序列号
	3H		; 刷新
	15M		; 重试
	1D		; 过期
	1W		; 最小TTL
)

	NS dns1

; 子域委派
bj	NS bj-dns
sh	NS sh-dns

; 主域记录
dns1	IN A	10.0.0.13
www	IN A	10.0.0.14
blog	IN A	10.0.0.12

; 胶水记录(Glue Records)
bj-dns	IN A	10.0.0.14
sh-dns	IN A	10.0.0.16
