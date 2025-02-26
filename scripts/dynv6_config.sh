#!/bin/sh


eval `dbus export dynv6`

if [ "$dynv6_enable" == "1" ];then
	/koolshare/dynv6/dynv6.sh restart
else
	/koolshare/dynv6/dynv6.sh stop
fi 
