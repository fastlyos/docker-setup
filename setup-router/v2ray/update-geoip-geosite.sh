#!/bin/bash

# /home/router/etc/v2ray/update-geoip-geosite.sh

if [ -e "/opt/podman" ]; then
    export PATH=/opt/podman/bin:/opt/podman/libexec:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
else
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl
fi

mkdir -p /home/router/etc/v2ray ;
cd /home/router/etc/v2ray ;


# patch for podman 1.6.3 restart BUG
#   @see https://bbs.archlinux.org/viewtopic.php?id=251410
#   @see https://github.com/containers/libpod/issues/4522


/home/router/v2ray/create-v2ray-pod.sh

exit $? # patch for podman 1.6.3

podman container inspect v2ray > /dev/null 2>&1
if [ $? -eq 0 ]; then

    if [ -e "geoip.dat" ]; then
        rm -f "geoip.dat";
    fi
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geoip.dat" -o geoip.dat ;
    if [ $? -eq 0 ]; then
        podman cp geoip.dat v2ray:/usr/bin/v2ray/geoip.dat ;
    fi

    if [ -e "geosite.dat" ]; then
        rm -f "geosite.dat";
    fi
    curl -k -qL "https://github.com/owent/update-geoip-geosite/releases/download/latest/geosite.dat" -o geosite.dat ;
    if [ $? -eq 0 ]; then
        podman cp geosite.dat v2ray:/usr/bin/v2ray/geosite.dat ;
    fi

    systemctl disable v2ray ;
    systemctl stop v2ray ;
    systemctl enable v2ray ;
    systemctl start v2ray ;
else
    chmod +x /home/router/v2ray/create-v2ray-pod.sh;
    /home/router/v2ray/create-v2ray-pod.sh ;
fi
