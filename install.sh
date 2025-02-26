#!/bin/sh

if [ ! -d /koolshare/dynv6 ]; then
   mkdir -p /koolshare/dynv6
fi

cp -rf /tmp/dynv6/scripts/* /koolshare/scripts/
cp -rf /tmp/dynv6/webs/* /koolshare/webs/
cp -rf /tmp/dynv6/res/* /koolshare/res/
cp -rf /tmp/dynv6/init.d/* /koolshare/init.d/
cp -rf /tmp/dynv6/dynv6/dynv6.sh /koolshare/dynv6/
rm -rf /tmp/dynv6* >/dev/null 2>&1

if [ ! -L /koolshare/init.d/S99dynv6.sh ]; then
    ln -sf /koolshare/dynv6/dynv6.sh /koolshare/init.d/S99dynv6.sh
fi

chmod a+x /koolshare/scripts/dynv6_config.sh
chmod a+x /koolshare/dynv6/dynv6.sh
chmod a+x /koolshare/init.d/S99dynv6.sh
