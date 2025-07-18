#!/bin/sh
set -e
# 设置调试陷阱（即使 ERR 不工作，EXIT 通常可用）
trap 'exit_handler' EXIT

# 退出处理函数
exit_handler() {
    local exit_code=$?
    [ $exit_code -eq 0 ] && return 0
    
    # 获取最后执行的命令
    local last_cmd=$(fc -l -1 -1 | sed 's/^[ \t]*[0-9]\+[ \t]*//')
    
    # 获取调用堆栈
    local stack=""
    local i=0
    while caller $i; do
        i=$((i+1))
    done > /tmp/side-route-callstack
    
    log "error" "Script exited with code $exit_code"
    log "error" "Last command: $last_cmd"
    log "error" "Call stack:"
    cat /tmp/side-route-callstack | logger -t "$LOG_TAG" -p user.error
    rm -f /tmp/side-route-callstack
    
    exit $exit_code
}

#引入
FW_SCRIPT="/usr/sbin/side-route-firewall.sh"
#if [ -f "$FW_SCRIPT" ]; then
#    . "$FW_SCRIPT"
#else
#    log "error" "Firewall script not found: $FW_SCRIPT"
#fi



# 配置路径
CONFIG_FILE="/etc/config/side-route"
CONFIG_FILE_TMP="/tmp/side-route"
PID_FILE="/var/run/side-route.pid"
STATUS_FILE="/tmp/side-route.state"

LOG_TAG="SIDE_ROUTE_DAEMON"

# 全局配置变量
ROUTE_SIDE_IP=""
ROUTE_INTERFACE=""
ROUTE_TABLE_NUM=""
ROUTE_FWMARK=""
CHECK_TIMEOUT="30"
#临时变量
ROUTE_TABLE_NUM_OLD=""
ROUTE_SITE_IP_OLD=""
ROUTE_INTERFACE_OLD=""
ROUTE_FWMARK_OLD=""

RELOAD_FIRST=""

PING=0

# 日志记录函数
log() {
    local level="$1"
    local message="$2"
    logger -t "$LOG_TAG" -p "user.$level" "$message"
}

# 守护进程化
daemonize() {
    # 创建PID文件
    echo $$ > "$PID_FILE"
    
    # 重定向标准流
    #exec >/dev/null 2>&1
    exec >/dev/null 
}


# 配置重载函数
reload_config() {
    PING=0
    
    # 检查配置有效性
    if ! uci -q show side-route >/dev/null; then
        log "error" "Invalid configuration"
        return 1
    fi
    
    # 实际配置处理逻辑
    ROUTE_TABLE_NUM=$(uci -q get $CONFIG_FILE.global.route_table_num)
    ROUTE_SIDE_IP=$(uci -q get $CONFIG_FILE.global.route_side_ip)
    ROUTE_INTERFACE=$(uci -q get $CONFIG_FILE.global.route_interface)
    ROUTE_FWMARK=$(uci -q get $CONFIG_FILE.global.route_mark)
    CHECK_TIMEOUT=$(uci -q get $CONFIG_FILE.global.check_timeout || echo 30)  # 默认30秒
   
    # 检查必要参数
    if [ -z "$ROUTE_TABLE_NUM" ] || [ -z "$ROUTE_FWMARK" ] || \
       [ -z "$ROUTE_SIDE_IP" ] || [ -z "$ROUTE_INTERFACE" ]; then
        log "error" "Missing required global parameters"
        log "error" "$ROUTE_TABLE_NUM, $ROUTE_FWMARK, $ROUTE_SIDE_IP, $ROUTE_INTERFACE"
        return 1
    fi

    ROUTE_TABLE_NUM_OLD=$(uci -q get $CONFIG_FILE_TMP.global.route_table_num)
    ROUTE_SITE_IP_OLD=$(uci -q get $CONFIG_FILE_TMP.global.route_side_ip)
    ROUTE_INTERFACE_OLD=$(uci -q get $CONFIG_FILE_TMP.global.route_interface)
    ROUTE_FWMARK_OLD=$(uci -q get $CONFIG_FILE_TMP.global.route_mark)
    
    if [ "$ROUTE_TABLE_NUM" != "$ROUTE_TABLE_NUM_OLD" ] || [ "$ROUTE_SIDE_IP" != "$ROUTE_SITE_IP_OLD" ] || \
       [ "$ROUTE_INTERFACE" != "$ROUTE_INTERFACE_OLD" ] || [ "$ROUTE_FWMARK" != "$ROUTE_FWMARK_OLD" ]; then
        log "info" "Global config changed - updating routing"
        update_routing_table
    else
        RELOAD_FIRST=$(grep "^reload_first=" "$STATUS_FILE" 2>/dev/null | cut -d'=' -f2)
        log "debug" "$STATUS_FILE: Check RELOAD_FIRST: $RELOAD_FIRST"
        if [ -z "$RELOAD_FIRST" ]; then
            log "info" "first reload config.."
            update_routing_table
            echo "reload_first=1" > "$STATUS_FILE"
        else
            log "debug" "Global config unchanged - skipping routing update"
        fi

    fi

    #log "debug" "fwmark: $ROUTE_FWMARK ,  fwmark_old: $ROUTE_FWMARK_OLD"
    # update_nft_rules "$ROUTE_FWMARK" "$ROUTE_FWMARK_OLD"
    #if "$FW_SCRIPT" "$ROUTE_FWMARK" "$ROUTE_FWMARK_OLD"; then
    #    log "info" "Reloaded configuration Successfully"

    #    PING=1
        # 完成后更新临时文件
   #     cp "$CONFIG_FILE" "$CONFIG_FILE_TMP"
   # else
        #log "error" "Failed to update nft rules"
    #fi
    PING=1
    # 完成后更新临时文件
    cp "$CONFIG_FILE" "$CONFIG_FILE_TMP"
}

update_routing_table() {
    # 1. 确保路由表存在（仅当表名或编号变更时）
    if ! grep -qE "^$ROUTE_TABLE_NUM $ROUTE_TABLE_NUM" /etc/iproute2/rt_tables; then
        echo "$ROUTE_TABLE_NUM $ROUTE_TABLE_NUM" >> /etc/iproute2/rt_tables
        log "info" "create route table id: $ROUTE_TABLE_NUM"
        
        # 如果旧表存在且不同，删除旧表
        if [ -n "$ROUTE_TABLE_NUM_OLD" ] && [ "$ROUTE_TABLE_NUM_OLD" != "$ROUTE_TABLE_NUM" ] && \
            grep -q "^$ROUTE_TABLE_NUM_OLD\s" /etc/iproute2/rt_tables; then
            sed -i "/^$ROUTE_TABLE_NUM_OLD\s/d" /etc/iproute2/rt_tables
            log "info" "delete old route table $ROUTE_TABLE_NUM_OLD"
        fi
    fi
    
    # 2. 删除旧规则（基于旧配置）
    if [ -n "$ROUTE_FWMARK_OLD" ]; then
        while ip rule delete fwmark $ROUTE_FWMARK_OLD 2>/dev/null; do
            log "info" "delete old rule: fwmark $ROUTE_FWMARK_OLD"
        done
    fi
    
    # 3. 清空旧路由表（基于旧配置）
    if [ -n "$ROUTE_TABLE_NUM_OLD" ] && [ "$ROUTE_TABLE_NUM_OLD" != "$ROUTE_TABLE_NUM" ]; then
        ip route flush table $ROUTE_TABLE_NUM_OLD 2>/dev/null && \
            log "info" "clear old route table: $ROUTE_TABLE_NUM_OLD"
    fi
    
    # 4. 清空新路由表（确保干净状态）
    ip route flush table $ROUTE_TABLE_NUM 2>/dev/null && \
        log "info" "clear new route table: $ROUTE_TABLE_NUM"
    
    # 5. 添加新规则
    if ip rule add fwmark $ROUTE_FWMARK lookup $ROUTE_TABLE_NUM; then
        log "info" "create new rule: fwmark $ROUTE_FWMARK lookup $ROUTE_TABLE_NUM"
    else
        log "error" "create new rule failed"
        return 1
    fi
    
    # 6. 添加默认路由
    if ip route replace default via $ROUTE_SIDE_IP dev $ROUTE_INTERFACE table $ROUTE_TABLE_NUM; then
        log "info" "create new route: default via $ROUTE_SIDE_IP dev $ROUTE_INTERFACE table $ROUTE_TABLE_NUM"
        return 0
    else
        log "error" "create new route failed"
        return 1
    fi
}

# 清理函数
cleanup() {
    log "info" "cleanup"
    # rm -f "$PID_FILE"
    # 在这里添加任何必要的资源清理代码
}

# 信号处理函数. procd用不到因为它会重启daemon
handle_signal() {
    case $1 in
        HUP)
            log "info" "Received SIGHUP, Reloading configuration"
            reload_config
            ;;
        TERM)
            log "info" "Shutting down"
            cleanup
            exit 0
            ;;
    esac
}

# 主函数
main() {
    daemonize
    trap 'handle_signal HUP' HUP
    trap 'handle_signal TERM' TERM
    
    log "debug" "Starting Daemon, Reloading configuration"
    # 初始加载配置
    reload_config || {
        log "error" "Initial config load failed"
        exit 1
    }
    
    log "info" "Daemon started (PID: $$)"

    # 主循环
    while true; do

        log "debug" "Checking for IP changes ,timeout: $CHECK_TIMEOUT"

        # reload config时不进行ping检测,防止ip命令执行重复\冲突
        if [ $PING -eq 1 ]; then 

            if [ -z "$ROUTE_SIDE_IP" ] || [ -z "$ROUTE_INTERFACE" ] || [ -z "$ROUTE_TABLE_NUM" ]; then
                log "error" "config error"
                sleep $CHECK_TIMEOUT
                continue
            fi

            # log "info" "Checking side route... IP:$ROUTE_SIDE_IP"

            # 检测旁路由是否在线
            if ping -c 2 "$ROUTE_SIDE_IP" > /dev/null; then
                # 如果在线，确保路由存在
                ip route show table "$ROUTE_TABLE_NUM" | grep -q "default" || {
                    ip route replace default via "$ROUTE_SIDE_IP" dev "$ROUTE_INTERFACE" table "$ROUTE_TABLE_NUM"
                    log "info" "side-route online, restore table $ROUTE_TABLE_NUM default route"
                }
            else
                # 如果离线，删除路由
                ip route del default via "$ROUTE_SIDE_IP" dev "$ROUTE_INTERFACE" table "$ROUTE_TABLE_NUM" 2>/dev/null
                log "info" "siede-route offline, remove table $ROUTE_TABLE_NUM default route"
            fi
        fi
        
        sleep $CHECK_TIMEOUT &  # 后台睡眠
        wait $!     # 等待睡眠结束或被信号中断
    done
} 

# 启动主函数
main