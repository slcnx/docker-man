$TTL 86400
@ IN SOA ns1.bj.magedu.com. admin.bj.magedu.com. (
	128
	3H
	15M
	1D
	1W
)

	NS ns1.bj.magedu.com.

ns1	IN A	10.0.0.14
@	IN A	10.0.0.14
www	IN A	10.0.0.24
