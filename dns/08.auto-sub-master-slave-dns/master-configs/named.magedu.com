$TTL 86400
@ IN SOA magedu-dns.magedu.com. admin.magedu.com. (
	128		; 序列号
	3H		; 刷新
	15M		; 重试
	1D		; 过期
	1W		; 最小TTL
)

	NS dns1
	NS dns2

; 主域记录
dns1	IN A	10.0.0.13
dns2	IN A	10.0.0.15
www	IN A	10.0.0.14
blog	IN A	10.0.0.12

; 子域DNS服务器的胶水记录(Glue Records)
bj-dns1	IN A	10.0.0.14
bj-dns2	IN A	10.0.0.17
sh-dns1	IN A	10.0.0.16
sh-dns2	IN A	10.0.0.18

; 子域委派（NS记录）
bj	IN NS	bj-dns1.magedu.com.
bj	IN NS	bj-dns2.magedu.com.
sh	IN NS	sh-dns1.magedu.com.
sh	IN NS	sh-dns2.magedu.com.
