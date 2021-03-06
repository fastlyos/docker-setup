#!/bin/bash


# nftables
# Quick: https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT)
# Quick(CN): https://wiki.archlinux.org/index.php/Nftables_(%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87)#Masquerading
# List all tables/chains/rules/matches/statements: https://wiki.nftables.org/wiki-nftables/index.php/Quick_reference-nftables_in_10_minutes#Rules
# man 8 nft: 
#    https://www.netfilter.org/projects/nftables/manpage.html
#    https://www.mankier.com/8/nft
# IP http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest
#    ipv4 <start> <count> => ipv4 58.42.0.0 65536
#    ipv6 <prefix> <bits> => ipv6 2407:c380:: 32
# Netfilter: https://en.wikipedia.org/wiki/Netfilter
#            http://inai.de/images/nf-packet-flow.svg

if [ -e "/opt/nftables/sbin" ]; then
    export PATH=/opt/nftables/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

### ==================================== v2ray nftables rules begin ====================================
### ----------------------------------- /home/router/v2ray/setup-tproxy.sh -----------------------------------

### Setup v2ray xtable rule and policy routing
### ip rule { add | del } SELECTOR ACTION
### default table/rule-> local(ID: 255)/Priority: 0 , main(ID: 254)/Priority: 32766 , default(ID: 253)/Priority: 32766
### 策略路由，所有 fwmark = 1 的包走 table:100

if [ "x" == "x$V2RAY_HOST_IPV4" ]; then
    V2RAY_HOST_IPV4=
fi

if [ "x" == "x$V2RAY_PORT" ]; then
    V2RAY_PORT=3371
fi

if [ "x" == "x$SETUP_WITH_INTERNAL_SERVICE_PORT" ]; then
    SETUP_WITH_INTERNAL_SERVICE_PORT="{22, 53, 6881, 6882, 6883, 8371, 8372, 36000}"
fi

if [ "x" == "x$SETUP_WITH_DEBUG_LOG" ]; then
    SETUP_WITH_DEBUG_LOG=0
fi

ip -4 route add local 0.0.0.0/0 dev lo table 100
ip -6 route add local ::/0 dev lo table 100
FWMARK_LOOPUP_TABLE_100=$(ip -4 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
while [ 0 -ne $FWMARK_LOOPUP_TABLE_100 ] ; do
    ip -4 rule delete fwmark 1 lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -4 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
done

FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
while [ 0 -ne $FWMARK_LOOPUP_TABLE_100 ] ; do
    ip -6 rule delete fwmark 1 lookup 100
    FWMARK_LOOPUP_TABLE_100=$(ip -6 rule show fwmark 1 lookup 100 | awk 'END {print NF}')
done
ip -4 rule add fwmark 1 lookup 100
ip -6 rule add fwmark 1 lookup 100
# ip route show table 100

nft list table ip v2ray > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add table ip v2ray
fi

nft list table ip6 v2ray > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add table ip6 v2ray
fi

nft list table bridge v2ray > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add table bridge v2ray
fi

### See https://toutyrater.github.io/app/tproxy.html

### Setup - ipv4
nft list set ip v2ray BLACKLIST > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add set ip v2ray BLACKLIST { type ipv4_addr\; }
fi
nft list set ip v2ray GEOIP_CN > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add set ip v2ray GEOIP_CN { type ipv4_addr\; flags interval\; }
fi

nft list chain ip v2ray PREROUTING > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip v2ray PREROUTING { type filter hook prerouting priority filter + 1 \; }
fi
nft flush chain ip v2ray PREROUTING

### ipv4 - skip internal services
nft add rule ip v2ray PREROUTING tcp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
nft add rule ip v2ray PREROUTING udp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule ip v2ray PREROUTING tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###TCP4#PREROU:"' level debug flags all
    nft add rule ip v2ray PREROUTING udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###UDP4#PREROU:"' level debug flags all
fi

### ipv4 - skip link-local and broadcast address
nft add rule ip v2ray PREROUTING ip daddr {127.0.0.1/32, 224.0.0.0/4, 255.255.255.255/32} return
nft add rule ip v2ray PREROUTING mark 255 return
### ipv4 - skip private network and UDP of DNS
nft add rule ip v2ray PREROUTING ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} return
# if dns service and V2RAY are on different server, use rules below
# nft add rule ip v2ray PREROUTING meta l4proto tcp ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} return
# nft add rule ip v2ray PREROUTING ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} udp dport != 53 return
# nft add rule ip v2ray PREROUTING ip daddr {GATEWAY_ADDRESSES} return

# ipv4 skip package from outside
nft add rule ip v2ray PREROUTING ip daddr @BLACKLIST return
# GEOIP_CN
nft add rule ip v2ray PREROUTING ip daddr @GEOIP_CN return
## TODO DNSMASQ_GFW_IPV4

### ipv4 - forward to v2ray's listen address if not marked by v2ray
# tproxy ip to $V2RAY_HOST_IPV4:$V2RAY_PORT
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule ip v2ray PREROUTING tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT meta nftrace set 1
    nft add rule ip v2ray PREROUTING tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '">>>TCP4>tproxy:"' level debug flags all
    nft add rule ip v2ray PREROUTING udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '">>>UDP4>tproxy:"' level debug flags all
fi

nft add rule ip v2ray PREROUTING meta l4proto tcp tproxy to :$V2RAY_PORT accept # -j TPROXY --on-port $V2RAY_PORT  # mark tcp package with 1 and forward to $V2RAY_PORT
nft add rule ip v2ray PREROUTING meta l4proto udp tproxy to :$V2RAY_PORT accept # -j TPROXY --on-port $V2RAY_PORT  # mark tcp package with 1 and forward to $V2RAY_PORT

# Setup - ipv4 local
nft list chain ip v2ray OUTPUT > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip v2ray OUTPUT { type route hook output priority filter + 1 \; }
fi
nft flush chain ip v2ray OUTPUT

### ipv4 - skip internal services
nft add rule ip v2ray OUTPUT tcp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
nft add rule ip v2ray OUTPUT udp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule ip v2ray OUTPUT tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###TCP4#OUTPUT:"' level debug flags all
    nft add rule ip v2ray OUTPUT udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###UDP4#OUTPUT:"' level debug flags all
fi

nft add rule ip v2ray OUTPUT ip daddr {127.0.0.1/32, 224.0.0.0/4, 255.255.255.255/32} return
nft add rule ip v2ray OUTPUT ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} return
# if dns service and v2ray are on different server, use rules below
# nft add rule ip v2ray OUTPUT meta l4proto tcp ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} return
# nft add rule ip v2ray OUTPUT ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} udp dport != 53 return
# nft add rule ip v2ray OUTPUT ip daddr {GATEWAY_ADDRESSES} return
nft add rule ip v2ray OUTPUT mark 255 return
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule ip v2ray OUTPUT tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT meta nftrace set 1
    nft add rule ip v2ray OUTPUT tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"+++TCP4+mark 1:"' level debug flags all
    nft add rule ip v2ray OUTPUT udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"+++UDP4+mark 1:"' level debug flags all
fi
nft add rule ip v2ray OUTPUT mark != 1 meta l4proto {tcp, udp} mark set 1 accept

## Setup - ipv6
nft list set ip6 v2ray BLACKLIST > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add set ip6 v2ray BLACKLIST { type ipv6_addr\; }
fi
nft list set ip6 v2ray GEOIP_CN > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add set ip6 v2ray GEOIP_CN { type ipv6_addr\; flags interval\; }
fi

nft list chain ip6 v2ray PREROUTING > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip6 v2ray PREROUTING { type filter hook prerouting priority filter + 1 \; }
fi
nft flush chain ip6 v2ray PREROUTING

### ipv6 - skip internal services
nft add rule ip6 v2ray PREROUTING tcp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
nft add rule ip6 v2ray PREROUTING udp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
nft add rule ip6 v2ray PREROUTING mark 255 return
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule ip6 v2ray PREROUTING tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###TCP6#PREROU:"' level debug flags all
    nft add rule ip6 v2ray PREROUTING udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###UDP6#PREROU:"' level debug flags all
fi

### ipv6 - skip link-locak and multicast
nft add rule ip6 v2ray PREROUTING ip6 daddr {::1/128, fc00::/7, fe80::/10, ff00::/8} return

### ipv6 - skip private network and UDP of DNS
# if dns service and v2ray are on different server, use rules below
# nft add rule ip6 v2ray PREROUTING meta l4proto tcp ip6 daddr fd00::/8 return
# nft add rule ip6 v2ray PREROUTING ip6 daddr fd00::/8 udp dport != 53 return
# nft add rule ip6 v2ray PREROUTING ip6 daddr {GATEWAY_ADDRESSES} return

# ipv6 skip package from outside
nft add rule ip6 v2ray PREROUTING ip6 daddr @BLACKLIST return
# GEOIP_CN
nft add rule ip v2ray PREROUTING ip daddr @GEOIP_CN return
## TODO DNSMASQ_GFW_IPV6

### ipv6 - forward to v2ray's listen address if not marked by v2ray
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule ip6 v2ray PREROUTING tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT meta nftrace set 1
    nft add rule ip6 v2ray PREROUTING tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '">>>TCP6>tproxy:"' level debug flags all
    nft add rule ip6 v2ray PREROUTING udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '">>>UDP6>tproxy:"' level debug flags all
fi
# tproxy ip6 to $V2RAY_HOST_IPV6:$V2RAY_PORT
nft add rule ip6 v2ray PREROUTING meta l4proto tcp tproxy to :$V2RAY_PORT accept # -j TPROXY --on-port $V2RAY_PORT  # mark tcp package with 1 and forward to $V2RAY_PORT
nft add rule ip6 v2ray PREROUTING meta l4proto udp tproxy to :$V2RAY_PORT accept # -j TPROXY --on-port $V2RAY_PORT  # mark tcp package with 1 and forward to $V2RAY_PORT

# Setup - ipv6 local
nft list chain ip6 v2ray OUTPUT > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain ip6 v2ray OUTPUT { type route hook output priority filter + 1 \; }
fi
nft flush chain ip6 v2ray OUTPUT

### ipv6 - skip internal services
nft add rule ip6 v2ray OUTPUT tcp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
nft add rule ip6 v2ray OUTPUT udp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule ip6 v2ray OUTPUT tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###TCP6#OUTPUT:"' level debug flags all
    nft add rule ip6 v2ray OUTPUT udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###UDP6#OUTPUT:"' level debug flags all
fi

nft add rule ip6 v2ray OUTPUT ip6 daddr {::1/128, fc00::/7, fe80::/10, ff00::/8} return
nft add rule ip6 v2ray OUTPUT ip6 daddr fd00::/8 return
# if dns service and v2ray are on different server, use rules below
# nft add rule ip6 v2ray OUTPUT meta l4proto tcp ip6 daddr fd00::/8 return
# nft add rule ip6 v2ray OUTPUT ip6 daddr fd00::/8 udp dport != 53 return
# nft add rule ip6 v2ray OUTPUT ip6 daddr {GATEWAY_ADDRESSES} return
nft add rule ip6 v2ray OUTPUT mark 255 return # make sure v2ray's outbounds.*.streamSettings.sockopt.mark = 255
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule ip6 v2ray OUTPUT tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT meta nftrace set 1
    nft add rule ip6 v2ray OUTPUT tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"+++TCP6+mark 1:"' level debug flags all
    nft add rule ip6 v2ray OUTPUT udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"+++UDP6+mark 1:"' level debug flags all
fi
nft add rule ip6 v2ray OUTPUT mark != 1 meta l4proto {tcp, udp} mark set 1 accept


### Setup - bridge
# nft list set bridge v2ray BLACKLIST > /dev/null 2>&1 ;
# if [ $? -ne 0 ]; then
#     nft add set bridge v2ray BLACKLIST { type ipv4_addr\; }
# fi

nft list chain bridge v2ray PREROUTING > /dev/null 2>&1 ;
if [ $? -ne 0 ]; then
    nft add chain bridge v2ray PREROUTING { type filter hook prerouting priority -299 \; }
fi
nft flush chain bridge v2ray PREROUTING

### bridge - skip internal services
nft add rule bridge v2ray PREROUTING tcp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
nft add rule bridge v2ray PREROUTING udp sport $SETUP_WITH_INTERNAL_SERVICE_PORT return
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule bridge v2ray PREROUTING tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###BRIDGE#PREROU:"' level debug flags all
    nft add rule bridge v2ray PREROUTING udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '"###BRIDGE#PREROU:"' level debug flags all
fi

### bridge - skip link-local and broadcast address
nft add rule bridge v2ray PREROUTING mark 255 return

nft add rule bridge v2ray PREROUTING ip daddr {127.0.0.1/32, 224.0.0.0/4, 255.255.255.255/32} return
### bridge - skip private network and UDP of DNS
nft add rule bridge v2ray PREROUTING ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} return
# if dns service and V2RAY are on different server, use rules below
# nft add rule bridge v2ray PREROUTING meta l4proto tcp ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} return
# nft add rule bridge v2ray PREROUTING ip daddr {192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8} udp dport != 53 return
# nft add rule bridge v2ray PREROUTING ip daddr {GATEWAY_ADDRESSES} return

### ipv6 - skip link-locak and multicast
nft add rule bridge v2ray PREROUTING ip6 daddr {::1/128, fc00::/7, fe80::/10, ff00::/8} return

### ipv6 - skip private network and UDP of DNS
# if dns service and v2ray are on different server, use rules below
# nft add rule bridge v2ray PREROUTING meta l4proto tcp ip6 daddr fd00::/8 return
# nft add rule bridge v2ray PREROUTING ip6 daddr fd00::/8 udp dport != 53 return
# nft add rule bridge v2ray PREROUTING ip6 daddr {GATEWAY_ADDRESSES} return


# bridge skip package from outside
# nft add rule bridge v2ray PREROUTING ip daddr @BLACKLIST return
# nft add rule bridge v2ray PREROUTING ip6 daddr @BLACKLIST return

### bridge - meta pkttype set unicast
if [ $SETUP_WITH_DEBUG_LOG -ne 0 ]; then
    nft add rule bridge v2ray PREROUTING tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT meta nftrace set 1
    nft add rule bridge v2ray PREROUTING tcp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '">>>BR TCP>pkttype:"' level debug flags all
    nft add rule bridge v2ray PREROUTING udp dport != $SETUP_WITH_INTERNAL_SERVICE_PORT log prefix '">>>BR UDP>pkttype:"' level debug flags all
fi

# https://www.mankier.com/8/ebtables-legacy#Description-Tables
# https://www.mankier.com/8/ebtables-nft
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto tcp -j redirect --redirect-target DROP
# ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto tcp -j redirect --redirect-target DROP
nft add rule bridge v2ray PREROUTING meta l4proto tcp meta pkttype set unicast # ether daddr set 00:00:00:00:00:00
# ebtables -t broute -A V2RAY_BRIDGE -p ipv4 --ip-proto udp -j redirect --redirect-target DROP
# ebtables -t broute -A V2RAY_BRIDGE -p ipv6 --ip6-proto udp -j redirect --redirect-target DROP
nft add rule bridge v2ray PREROUTING meta l4proto udp meta pkttype set unicast # ether daddr set 00:00:00:00:00:00
