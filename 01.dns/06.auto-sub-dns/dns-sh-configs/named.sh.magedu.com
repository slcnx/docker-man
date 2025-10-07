$TTL 86400
@ IN SOA ns1.sh.magedu.com. admin.sh.magedu.com. (
	128
	3H
	15M
	1D
	1W
)

	NS ns1.sh.magedu.com.

ns1	IN A	10.0.0.16
@	IN A	10.0.0.16
www	IN A	10.0.0.26
