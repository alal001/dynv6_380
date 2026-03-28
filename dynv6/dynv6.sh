#!/bin/sh

#################################################
# dynv6 通用子域名更新脚本 (Merlin 双栈版)
# 支持 IPv4/IPv6 同时更新，按 JSON 分割精确匹配
# 适配 Web 界面状态显示
#################################################

# ====================================变量定义====================================
version="0.0.3"

# 导入 skipd 数据
eval `dbus export dynv6`

# 引用环境变量等
source /koolshare/scripts/base.sh
export PERP_BASE=/koolshare/perp

# 使用 Token 认证
arToken=$dynv6_config_token
# 主域名
mainDomain="$dynv6_config_domain"
# 子域名列表
subDomains='"router" "home" "cloud" "onedev"'

# 是否启用 IPv4 更新
ENABLE_IPV4=true

# ====================================函数定义====================================
# 写入状态信息到 Web 界面
write_status() {
    dbus set dynv6_run_status="$1"
    echo "$1"
}

# 从 wan 口获得 IPv4 地址
getLocalIPv4() {
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

# 查询本地网卡 IPv6（路由器自身）
getLocalIPv6() {
    ip -6 addr show br0 | grep 'global' | awk -F' ' '{print $2}' | cut -d'/' -f1 | head -1
}

# 获取 zone 信息
getZoneInfo() {
    curl --silent -H "Authorization: Bearer ${arToken}" -H "Accept: application/json" "https://dynv6.com/api/v2/zones/by-name/${mainDomain}"
}

# 获取 zone 的当前 IP 前缀
getZoneIPs() {
    curl --silent -H "Authorization: Bearer ${arToken}" -H "Accept: application/json" "https://dynv6.com/api/v2/zones/${zoneID}"
}

# 更新主域名的 IPv4 和 IPv6 前缀
updateZone() {
    local myIP4=$(getLocalIPv4)
    local myIP6=$(getLocalIPv6)
    local payload="{\"ipv4address\": \"${myIP4}\", \"ipv6prefix\": \"${myIP6}\"}"
    curl --silent -X PATCH -H "Authorization: Bearer ${arToken}" -H "Content-Type: application/json" -d "${payload}" "https://dynv6.com/api/v2/zones/${zoneID}"
}

# 获取所有记录
getRecords() {
    curl --silent -H "Authorization: Bearer ${arToken}" -H "Accept: application/json" "https://dynv6.com/api/v2/zones/${zoneID}/records"
}

# 更新单条记录
updateRecord() {
    local sub="$1"
    local type="$2"
    local data="$3"
    local recordID="$4"
    
    local name_field="\"${sub}\""
    local payload="{\"name\": ${name_field}, \"type\": \"${type}\", \"data\": \"${data}\"}"
    curl --silent -X PATCH -H "Authorization: Bearer ${arToken}" -H "Content-Type: application/json" -d "${payload}" "https://dynv6.com/api/v2/zones/${zoneID}/records/${recordID}"
}

# 将执行脚本写入 crontab 定时运行
add_dynv6_cru() {
    if [ -f /koolshare/dynv6/dynv6.sh ]; then
        chmod +x /koolshare/dynv6/dynv6.sh
        cru a dynv6 "0 */$dynv6_refresh_time * * * /koolshare/dynv6/dynv6.sh restart"
    fi
}

# 停止服务
stop_dynv6() {
    local dynv6cru=$(cru l | grep "dynv6")
    if [ -n "$dynv6cru" ]; then
        cru d dynv6
    fi
}

# 解析域名
parseDomain() {
    mainDomain=${dynv6_config_domain}
}

# 写入版本号
write_dynv6_version() {
    dbus set dynv6_version="$version"
}

# ====================================主逻辑====================================
case $ACTION in
start)
    if [ "$dynv6_enable" == "1" ] && [ "$dynv6_auto_start" == "1" ]; then
        parseDomain
        add_dynv6_cru
        sleep 5
        sleep $dynv6_delay_time
        /koolshare/dynv6/dynv6.sh restart
    fi
    ;;
stop | kill)
    stop_dynv6
    write_status "服务已停止"
    ;;
restart)
    stop_dynv6
    parseDomain
    add_dynv6_cru
    sleep 5
    sleep $dynv6_delay_time

    # ---------- 核心更新逻辑 ----------
    write_status "开始更新 dynv6 域名：${mainDomain}"

    # 获取当前 IP
    ipv4=$(getLocalIPv4)
    ipv6=$(getLocalIPv6)
    if [ -z "$ipv6" ]; then
        write_status "错误：无法获取 IPv6 地址"
        exit 1
    fi
    write_status "路由器 IPv4: ${ipv4:-无}"
    write_status "路由器 IPv6: ${ipv6}"

    # 获取 zone ID
    zoneResp=$(getZoneInfo)
    zoneID=$(echo "$zoneResp" | sed 's/.*"id":\([0-9]*\).*/\1/')
    if [ -z "$zoneID" ]; then
        write_status "错误：获取 zone ID 失败，API 响应：$zoneResp"
        exit 1
    fi
    write_status "zoneID: $zoneID"

    # 获取记录中保存的 IP 前缀
    zoneData=$(getZoneIPs)
    last_ipv4=$(echo "$zoneData" | sed 's/.*"ipv4address":"\([0-9\.]*\)".*/\1/')
    last_ipv6=$(echo "$zoneData" | sed 's/.*"ipv6prefix":"\([0-9a-f:]*\)".*/\1/')
    write_status "记录中 IPv4: ${last_ipv4:-无}"
    write_status "记录中 IPv6: ${last_ipv6}"

    # 判断是否需要更新主域名
    need_update=false
    if [ "$ENABLE_IPV4" = "true" ] && [ -n "$ipv4" ] && [ "$ipv4" != "$last_ipv4" ]; then
        need_update=true
    fi
    if [ -n "$ipv6" ] && [ "$ipv6" != "$last_ipv6" ]; then
        need_update=true
    fi

    if [ "$need_update" = "true" ]; then
        write_status "IP 地址已变化，更新主域名..."
        updateZone
        write_status "主域名 IP 前缀已更新"
    else
        write_status "IP 地址未变化，跳过主域名更新"
    fi

    # 获取所有记录
    records=$(getRecords)

    # 处理子域名（按 } 分割 JSON 记录，精确匹配）
    eval "set -- $subDomains"
    for sub in "$@"; do
        write_status "正在处理子域名: $sub"
        
        # 所有子域名都使用路由器地址（可根据需要修改）
        current_ipv4="$ipv4"
        current_ipv6="$ipv6"
        
        # 按 } 分割记录，逐条匹配
        echo "$records" | sed 's/}/}\n/g' | while read -r record; do
            # 检查是否是 A 记录且 name 匹配
            if echo "$record" | grep -q "\"type\":\"A\".*\"name\":\"$sub\""; then
                record_id_a=$(echo "$record" | sed 's/.*"id":\([0-9]*\).*/\1/')
                write_status "子域名 $sub 的 A 记录 ID: $record_id_a"
                updateRecord "$sub" "A" "$current_ipv4" "$record_id_a"
                write_status "已更新子域名: ${sub} (A) -> ${current_ipv4}"
            fi
            # 检查是否是 AAAA 记录且 name 匹配
            if echo "$record" | grep -q "\"type\":\"AAAA\".*\"name\":\"$sub\""; then
                record_id_aaaa=$(echo "$record" | sed 's/.*"id":\([0-9]*\).*/\1/')
                write_status "子域名 $sub 的 AAAA 记录 ID: $record_id_aaaa"
                updateRecord "$sub" "AAAA" "$current_ipv6" "$record_id_aaaa"
                write_status "已更新子域名: ${sub} (AAAA) -> ${current_ipv6}"
            fi
        done
    done

    write_status "所有更新完成"
    write_dynv6_version
    ;;
*)
    echo "Usage: $0 (start|stop|restart|kill)"
    exit 1
    ;;
esac