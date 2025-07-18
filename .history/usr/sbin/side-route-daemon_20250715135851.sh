#!/bin/sh

# 配置路径
CONFIG_FILE="/etc/config/side-route"
TMP_CONFIG="/tmp/side-route"
PID_FILE="/var/run/side-route.pid"

LOG_TAG="SIDE_ROUTE"

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
    # 例如：解析配置并应用路由规则
    # ...
    local route_table_num=$(uci -q get $CONFIG_NAME.global.route_table_num)
    local route_side_ip=$(uci -q get $CONFIG_NAME.global.route_side_ip)
    local route_interface=$(uci -q get $CONFIG_NAME.global.route_interface)
    local route_mark=$(uci -q get $CONFIG_NAME.global.route_mark)
    local check_timeout=$(uci -q get $CONFIG_NAME.global.check_timeout)

    declare -A route_config=(
        [table_num]=route_table_num
        [fwmark]=route_mark
        [gateway]=route_side_ip
        [interface]=route_interface
    )

    local route_table_num_tmp = $(uci -q get $TMP_CONFIG.global.route_table_num_tmp)
    local route_side_ip_tmp = $(uci -q get $TMP_CONFIG.global.route_side_ip_tmp)
    local route_interface_tmp = $(uci -q get $TMP_CONFIG.global.route_interface_tmp)
    local route_mark_tmp = $(uci -q get $TMP_CONFIG.global.route_mark_tmp)
    local check_timeout_tmp = $(uci -q get $TMP_CONFIG.global.check_timeout_tmp)
    
    declare -A route_config_old=(
        [table_num]=route_table_num_tmp
        [fwmark]=route_mark_tmp
        [gateway]=route_side_ip_tmp
        [interface]=route_interface_tmp
    )

    
    if [ "$route_table_num" != "$route_table_num_tmp" ] || [ "$route_side_ip" != "$route_side_ip_tmp" ] || [ "$route_interface" != "$route_interface_tmp" ] || [ "$route_mark" != "$route_mark_tmp" ] || [ "$check_timeout" != "$check_timeout_tmp" ]; then
        log "info" "update global config"
        update_routing_table route_config_old
    else
        update_routing_table route_config_old
    fi
        
    end
    
    log "info" "Reloaded configuration"
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
        if [ -n "$old_table_num" ] && [ "$old_table_num" != "$table_num" ] && \
            grep -q "$old_table_num" /etc/iproute2/rt_tables; then
            sed -i "/$old_table_num/d" /etc/iproute2/rt_tables
            log "info" "删除旧路由表: $old_table_num"
        fi
    fi
    
    # 2. 删除旧规则（基于旧配置）
    if [ -n "$old_fwmark" ]; then
        while ip rule delete fwmark $old_fwmark 2>/dev/null; do
            log "info" "删除旧规则: fwmark $old_fwmark"
        done
    fi
    
    # 3. 清空旧路由表（基于旧配置）
    if [ -n "$old_table_num" ] && [ "$old_table_num" != "$table_num" ]; then
        ip route flush table $old_table_num 2>/dev/null && \
            log "info" "清空旧路由表: $old_table_num"
    fi
    
    # 4. 清空新路由表（确保干净状态）
    ip route flush table $table_num 2>/dev/null && \
        log "info" "清空新路由表: $table_num"
    
    # 5. 添加新规则
    if ip rule add fwmark $fwmark lookup $table_num; then
        log "info" "添加新规则: fwmark $fwmark -> table $table_num"
    else
        log "error" "添加规则失败: fwmark $fwmark"
        return 1
    fi
    
    # 6. 添加默认路由
    if ip route add default via $gateway dev $interface table $table_num; then
        log "info" "添加默认路由: via $gateway dev $interface (table $table_num)"
        return 0
    else
        log "error" "添加默认路由失败"
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
        log "info" "进入主循环"
        sleep 60 &  # 后台睡眠
        wait $!     # 等待睡眠结束或被信号中断
    done
}

# 启动主函数
main