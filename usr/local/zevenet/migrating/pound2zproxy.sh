#!/bin/bash

# Migrate pound config file to l7 proxy config file
for i in $(find /usr/local/zevenet/config/ -name "*pound.cfg");
do
	echo "Migrating config file $i from pound to l7 proxy"

	REWRITE=`grep "RewriteLocation" $i`
	WAF=`grep WafRules $i | sed -E "s/^/\t/g"`
	sed -i -e '/^[\s#]*WafRules\s/d' $i
	sed "/$REWRITE/r"<(
		echo "$WAF"
	) -i -- $i

	sed -i -e 's/pound.socket/proxy.socket/' $i
	sed -i -e 's/(pound\/etc/zproxy\/etc/' $i
	mv "$i" "$(echo "$i" | sed s/pound.cfg/proxy.cfg/)"
done

# Migrate zhttp config file to l7 proxy config file
for i in $(find /usr/local/zevenet/config/ -name "*_proxy.cfg");
do
	if grep -q 'app\/zhttp\/etc' $i; then
		echo "Migrating config file $i from pound to l7 proxy"
		sed -i -e 's/app\/zhttp\/etc/app\/zproxy\/etc/' $i
	fi
done
