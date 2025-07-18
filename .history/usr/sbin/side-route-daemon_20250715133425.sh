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

    local route_table_name=$(uci -q get $CONFIG_NAME.global.route_table_name)
    local route_side_ip=$(uci -q get $CONFIG_NAME.global.route_side_ip)
    local route_interface=$(uci -q get $CONFIG_NAME.global.route_interface)
    local route_mark=$(uci -q get $CONFIG_NAME.global.route_mark)
    local check_timeout=$(uci -q get $CONFIG_NAME.global.check_timeout)

    local route_table_name_tmp = $(uci -q get $TMP_CONFIG.global.route_table_name_tmp)
    local route_side_ip_tmp = $(uci -q get $TMP_CONFIG.global.route_side_ip_tmp)
    local route_interface_tmp = $(uci -q get $TMP_CONFIG.global.route_interface_tmp)
    local route_mark_tmp = $(uci -q get $TMP_CONFIG.global.route_mark_tmp)
    local check_timeout_tmp = $(uci -q get $TMP_CONFIG.global.check_timeout_tmp)
    
    if [ "$route_table_name" != "$route_table_name_tmp" ] || [ "$route_side_ip" != "$route_side_ip_tmp" ] || [ "$route_interface" != "$route_interface_tmp" ] || [ "$route_mark" != "$route_mark_tmp" ] || [ "$check_timeout" != "$check_timeout_tmp" ]; then
        log "info" "update global config"


    else
        log "info" "no update global config"

        if ! grep -q "^$route_table_name_tmp\t$route_table_name_tmp" /etc/iproute2/rt_tables; then
            echo "$route_table_name_tmp\t$route_table_name_tmp" >> /etc/iproute2/rt_tables  
            log "info" "create route table $route_table_name_tmp"
        fi

        # 删除基于fwmark的规则
        while ip rule delete fwmark $route_mark_tmp 2>/dev/null; do
            log "info" 
        done
        


    fi
        
    end
    
    log "info" "Reloaded configuration"
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