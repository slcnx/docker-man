$TTL 86400
@ IN SOA ns1.magedu.com. admin.magedu.com. (
	2024100401	; 序列号 (格式: YYYYMMDDNN)
	3H		; 刷新时间
	15M		; 重试时间
	1W		; 过期时间
	1D		; 最小TTL
)

	NS ns1.magedu.com.
	NS ns2.magedu.com.

ns1	IN A	10.0.0.13
ns2	IN A	10.0.0.15
www	IN A	10.0.0.14
*	IN A	10.0.0.199
