#!/bin/sh

#################################################
# 
#################################################
# 
#################################################

# ====================================变量定义====================================
# 版本号定义
version="0.0.1"

# 导入skipd数据
eval `dbus export dynv6`

# 引用环境变量等
source /koolshare/scripts/base.sh
export PERP_BASE=/koolshare/perp


# 使用Token认证(推荐) 请去 https://https://dynv6.com/zones 获取
url="https://dynv6.com/api/v2/zones"
arToken=$dynv6_config_token
# 域名
mainDomain=""
# 本版默认subDomain="@"和"*"
subDomain1="@"
subDomain2="*"
# ====================================函数定义====================================
# 从wan口获得外网地址
arIpAdress() {
    #双WAN判断
    local wans_mode=$(nvram get wans_mode)
    local inter
    if [ "$dynv6_config_wan" == "1" ] && [ "$wans_mode" == "lb" ]; then
        inter=$(nvram get wan0_ipaddr)
    elif [ "$dynv6_config_wan" == "2" ] && [ "$wans_mode" == "lb" ]; then
        inter=$(nvram get wan1_ipaddr)
    else
        inter=$(nvram get wan0_ipaddr)
    fi
    echo $inter
}

# 查询本地网卡IP
# 参数: 待查询域名type: A/AAAA
getLocalIP() {
    addr4=$(ip addr show ppp0|grep 'global ppp0'| awk -F' ' '{print $2}')
    prefix=$(ip -6 addr show br0 |grep 'global'|awk -F' ' '{print $2}')
    addr6=$(echo $prefix |awk -F'/' '{print $1}')
    if [ "$1" == "A" ]; then
        echo $addr4
    elif [ "$1" == "AAAA" ]; then
        echo $addr6
    else
        echo "error"
    fi
}

# 查询DNS域名IPv4地址
# 参数: 待查询域名
arNslookup() {
    local inter="http://119.29.29.29/d?dn="
    wget --quiet --output-document=- $inter$1
}

# 读取域数据
# 参数:
arApiPostZone() {
    curl --silent -H "Authorization: Bearer ${arToken}" -H "Accept: application/json" $url/"by-name"/"$mainDomain"
}

# 读取记录数据
# 参数:payload zoneID recordID
arApiPost() {
    curl --silent -X PATCH -H "Authorization: Bearer ${arToken}" -H "Content-Type: application/json" -d "${1}" "${url}/${2}/records/${3}"
}

# 更新记录信息
# 参数: 主域名 子域名
arDdnsUpdate() {
    local zoneID rs idA idAX id4A id4AX payload recordRS recordCD myIP4 myIP6 errMsg
    # 获得域名ID
    zoneID=$(arApiPostZone)
    zoneID=$(echo $zoneID | sed 's/.*"id":\([0-9]*\).*/\1/')
    # 获得记录ID
    rs=$(curl --silent -H "Authorization: Bearer ${arToken}" -H "Content-Type: application/json" "${url}/${zoneID}/records")
    rs=$(echo $rs | sed 's/},{/}\n{/g')
    idA=$(echo $rs | awk '/"type":"A","name":""/' | sed 's/.*"id":\([0-9]*\).*/\1/')
    idAX=$(echo $rs | awk '/"type":"A","name":"\*"/' | sed 's/.*"id":\([0-9]*\).*/\1/')
    id4A=$(echo $rs | awk '/"type":"AAAA","name":""/' | sed 's/.*"id":\([0-9]*\).*/\1/')
    id4AX=$(echo $rs | awk '/"type":"AAAA","name":"\*"/' | sed 's/.*"id":\([0-9]*\).*/\1/')
    # 更新域IP
    myIP4=$(getLocalIP "A")
    myIP6=$(getLocalIP "AAAA")
    payload='{"ipv4address": "'"${myIP4}"'", "ipv6prefix": "'"$myIP6"'"}' 
    recordRS=$(curl --silent -X PATCH -H "Authorization: Bearer ${arToken}" -H "Content-Type: application/json" -d "${payload}"  "${url}/${zoneID}")
    recordCD=$(echo $recordRS | sed 's/.*"ipv4address":"\([0-9\.]*\)".*/\1/')
    # 更新记录IP
    payload='{"name": "'"${mainDomain}"'", "zoneID": "'"${zoneID}"'", "type": "A", "data": "'"${myIP4}"'", "id": "'"${idA}"'"}'
    arApiPost $payload $zoneID $idA
    payload='{"name": "'"${subDomain2}.${mainDomain}"'", "zoneID": "'"${zoneID}"'", "type": "A", "data": "'"${myIP4}"'", "id": "'"${idAX}"'"}'
    arApiPost $payload $zoneID $idAX
    payload='{"name": "'"${mainDomain}"'", "zoneID": "'"${zoneID}"'", "type": "AAAA", "data": "'"${myIP6}"'", "id": "'"${id4A}"'"}'
    arApiPost $payload $zoneID $id4A
    payload='{"name": "'"${subDomain2}.${mainDomain}"'", "zoneID": "'"${zoneID}"'", "type": "AAAA", "data": "'"${myIP6}"'", "id": "'"${id4AX}"'"}'
    arApiPost $payload $zoneID $id4AX
    # 输出记录IP
    if [ "$recordCD" == "$myIP4" ]; then
        dbus set dynv6_run_status="更新成功, ipv4: ${myIP4}, ipv6: ${myIP6}"
        return 1
    fi
    # 输出错误信息
    errMsg=$(echo $recordRS | sed 's/.*,"message":"\([^"]*\)".*/\1/')
    dbus set dynv6_run_status="$errMsg"
    echo $errMsg
}

# 动态检查更新
# 参数: 主域名 子域名
arDdnsCheck() {
    local postRS domain hostIP lastIP
    hostIP=$(arIpAdress)
    if [ "$2" == "@" ]; then
        domain="${1}"
    else
        domain="${2}.${1}"
    fi
    lastIP=$(arNslookup "${domain}")
    lastIP=$(echo $lastIP | awk -F ';' '{print $1}')
    echo "hostIP: ${hostIP}"
    echo "lastIP: ${lastIP}"
    if [ "$lastIP" != "$hostIP" ]; then
        dbus set dynv6_run_status="更新中。。。"
        postRS=$(arDdnsUpdate $1 $2)
        echo "postRS: ${postRS}"
        if [ $? -ne 1 ]; then
            return 1
        fi
    else
        dbus set dynv6_run_status="wan ip未改变，无需更新"
    fi
    return 0
}

parseDomain() {
    mainDomain=${dynv6_config_domain#*.}
    local tmp=${dynv6_config_domain%$mainDomain}
    subDomain=${tmp%.}
}

#将执行脚本写入crontab定时运行
add_dynv6_cru(){
	if [ -f /koolshare/dynv6/dynv6.sh ]; then
		#确保有执行权限
		chmod +x /koolshare/dynv6/dynv6.sh
		cru a dynv6 "0 */$dynv6_refresh_time * * * /koolshare/dynv6/dynv6.sh restart"
	fi
}

#停止服务
stop_dynv6(){
	#停掉cru里的任务
    local dynv6cru=$(cru l | grep "dynv6")
	if [ ! -z "$dynv6cru" ]; then
		cru d dynv6
	fi
}

# 写入版本号
write_dynv6_version(){
	dbus set dynv6_version="$version"
}

# ====================================主逻辑====================================

case $ACTION in
start)
	#此处为开机自启动设计
	if [ "$dynv6_enable" == "1" ] && [ "$dynv6_auto_start" == "1" ];then
    parseDomain
    add_dynv6_cru
    sleep $dynv6_delay_time
    arDdnsCheck $mainDomain $subDomain
	fi
	;;
stop | kill )
    stop_dynv6
	;;
restart)
    stop_dynv6
    parseDomain
    add_dynv6_cru
    sleep $dynv6_delay_time
    arDdnsCheck $mainDomain $subDomain
	write_dynv6_version
	;;
*)
	echo "Usage: $0 (start|stop|restart|kill)"
	exit 1
	;;
esac

