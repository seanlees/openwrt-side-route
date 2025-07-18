#!/bin/sh

# 配置路径
CONFIG_FILE="/etc/config/side-route"
TMP_CONFIG="/tmp/side-route"
PID_FILE="/var/run/side-route.pid"

LOG_TAG="SIDE_ROUTE"

# 全局配置变量
ROUTE_SIDE_IP=""
ROUTE_INTERFACE=""
ROUTE_TABLE_NUM=""
CHECK_TIMEOUT="15"

# 守护进程化
daemonize() {
    # 创建PID文件
    echo $$ > "$PID_FILE"
    
    # 重定向标准流
    #exec >/dev/null 2>&1
    exec >/dev/null 
}

# 日志记录函数
log() {
    local level="$1"
    local message="$2"
    logger -t "$LOG_TAG" -p "user.$level" "$message"
}

# 配置重载函数
reload_config() {
    log "info" "Start Reloading configuration"
    
    # 检查配置有效性
    if ! uci -q show side-route >/dev/null; then
        logger -t side-route "ERROR: Invalid configuration"
        return 1
    fi
    
    # 实际配置处理逻辑
    ROUTE_TABLE_NUM=$(uci -q get $CONFIG_NAME.global.route_table_num)
    ROUTE_SIDE_IP=$(uci -q get $CONFIG_NAME.global.route_side_ip)
    ROUTE_INTERFACE=$(uci -q get $CONFIG_NAME.global.route_interface)
    CHECK_TIMEOUT=$(uci -q get $CONFIG_NAME.global.check_timeout || echo 15)  # 默认10秒
    local route_mark=$(uci -q get $CONFIG_NAME.global.route_mark)

    # 检查必要参数
    if [ -z "$ROUTE_TABLE_NUM" ] || [ -z "$route_mark" ] || \
       [ -z "$ROUTE_SIDE_IP" ] || [ -z "$route_interface" ]; then
        log "error" "Missing required global parameters"
        return 1
    fi

    declare -A route_config=(
        [table_num]="$route_table_num"
        [fwmark]="$route_mark"
        [gateway]="$route_side_ip"
        [interface]="$route_interface"
    )

    local route_table_num_tmp=$(uci -q get $TMP_CONFIG.global.route_table_num_tmp)
    local route_side_ip_tmp=$(uci -q get $TMP_CONFIG.global.route_side_ip_tmp)
    local route_interface_tmp=$(uci -q get $TMP_CONFIG.global.route_interface_tmp)
    local route_mark_tmp=$(uci -q get $TMP_CONFIG.global.route_mark_tmp)
    local check_timeout_tmp=$(uci -q get $TMP_CONFIG.global.check_timeout_tmp)
    
    declare -A route_config_old=(
        [table_num]="$route_table_num_tmp"
        [fwmark]="$route_mark_tmp"
        [gateway]="$route_side_ip_tmp"
        [interface]="$route_interface_tmp"
    )
    
    if [ "$ROUTE_TABLE_NUM" != "$route_table_num_tmp" ] || [ "$ROUTE_SIDE_IP" != "$route_side_ip_tmp" ] || [ "$ROUTE_INTERFACE" != "$route_interface_tmp" ] || [ "$route_mark" != "$route_mark_tmp" ] ]; then
        log "info" "Global config changed - updating routing"
        update_routing_table route_config route_config_old
    else
        update_routing_table route_config_old
    fi
    
    log "info" "Reloaded configuration Successfully"
}

update_routing_table() {
    local -n config=$1  # 新配置引用
    local -n old_config=${2:-config}  # 旧配置引用（默认为新配置）
    
    # 从新配置中提取参数
    local table_num="${config[table_num]}"
    local fwmark="${config[fwmark]}"
    local gateway="${config[gateway]}"
    local interface="${config[interface]}"
    
    # 从旧配置中提取参数（如果存在）
    local old_table_num="${old_config[table_num]}"
    local old_fwmark="${old_config[fwmark]}"
    local old_gateway="${old_config[gateway]}"
    local old_interface="${old_config[interface]}"

    # 1. 确保路由表存在（仅当表名或编号变更时）
    if ! grep -qE "^$table_num $table_num" /etc/iproute2/rt_tables; then
        echo "$table_num $table_num" >> /etc/iproute2/rt_tables
        log "info" "create route table $table_num"
        
        # 如果旧表存在且不同，删除旧表
        if [ -n "$old_table_num" ] && [ "$old_table_num" != "$table_num" ] && grep -q "^$old_table_num\s" /etc/iproute2/rt_tables; then
            sed -i "/^$old_table_num\s/d" /etc/iproute2/rt_tables
            log "info" "delete old route table $old_table_num"
        fi
    fi
    
    # 2. 删除旧规则（基于旧配置）
    if [ -n "$old_fwmark" ]; then
        while ip rule delete fwmark $old_fwmark 2>/dev/null; do
            log "info" "delete old rule: fwmark $old_fwmark"
        done
    fi
    
    # 3. 清空旧路由表（基于旧配置）
    if [ -n "$old_table_num" ] && [ "$old_table_num" != "$table_num" ]; then
        ip route flush table $old_table_num 2>/dev/null && \
            log "info" "clear old route table: $old_table_num"
    fi
    
    # 4. 清空新路由表（确保干净状态）
    ip route flush table $table_num 2>/dev/null && \
        log "info" "clear new route table: $table_num"
    
    # 5. 添加新规则
    if ip rule add fwmark $fwmark lookup $table_num; then
        log "info" "create new rule: fwmark $fwmark lookup $table_num"
    else
        log "error" "create new rule failed"
        return 1
    fi
    
    # 6. 添加默认路由
    if ip route add default via $gateway dev $interface table $table_num; then
        log "info" "create new route: default via $gateway dev $interface table $table_num"
        return 0
    else
        log "error" "create new route failed"
        return 1
    fi
}

# 清理函数
cleanup() {
    rm -f "$PID_FILE"
    # 在这里添加任何必要的资源清理代码
}

# 信号处理函数
handle_signal() {
    case $1 in
        HUP)
            log "info" "Reloading configuration"
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
    
    # 初始加载配置
    reload_config || {
        log "error" "Initial config load failed"
        exit 1
    }
    
    log "info" "Daemon started (PID: $$)"


    
    # 主循环
    while true; do

        if [ -z "$ROUTE_SIDE_IP" ] || [ -z "$ROUTE_INTERFACE" ] || [ -z "$ROUTE_TABLE_NUM" ]; then
            log "error" "config error"
            sleep $CHECK_TIMEOUT
            continue
        fi

        log "info" "Checking side route... IP:$ROUTE_SIDE_IP"

        # 检测旁路由是否在线
        if ping -c 2 "$ROUTE_SIDE_IP" > /dev/null; then
            # 如果在线，确保路由存在
            ip route show table "$ROUTE_TABLE_NUM" | grep -q "default" || {
                ip route add default via "$ROUTE_SIDE_IP" dev "$ROUTE_INTERFACE" table "$ROUTE_TABLE_NUM"
                log "info" "side-route online, restore table $TABLE_ID default route"
            }
        else
            # 如果离线，删除路由
            ip route del default via "$route_side_ip" dev "$route_interface" table "$route_table_num" 2>/dev/null
            log "info"  "siede-route offline, remove table $TABLE_ID default route"
        fi
        
        sleep $CHECK_TIMEOUT &  # 后台睡眠
        wait $!     # 等待睡眠结束或被信号中断
    done
}

# 启动主函数
main