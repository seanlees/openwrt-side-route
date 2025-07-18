#!/bin/sh /etc/rc.common

USE_PROCD=0

# 启动顺序
START=95
STOP=10

CONFIG_FILE="/etc/config/side-route"
CONFIG_FILE_TMP="/tmp/side-route"
PID_FILE="/var/run/side-route.pid"
STATUS_FILE="/tmp/side-route.state"

# start 函数
start_service() {
    # 可以判断 enable 是否勾选并执行我们的程序
    logger -t Side-route "Side Route Client has start"

    cp "$CONFIG_FILE" "$CONFIG_FILE_TMP"

    procd_open_instance
    procd_set_param command /bin/sh /usr/sbin/side-route-daemon.sh
    procd_set_param pidfile "$PID_FILE"
    procd_set_param respawn  # 崩溃时自动重启
    procd_set_param stdout 1
    procd_set_param stderr 1
    
    #procd_set_param file "$CONFIG_FILE"
    #procd_set_param reload_sighup HUP

    procd_close_instance
}

service_triggers() {
    procd_add_reload_trigger "side-route"
}

stop_service() {
    logger -t Side-route "Stop_service"
    # 停止守护进程
    local pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -n "$pid" ] && kill -TERM "$pid"
    # 等待进程退出
    local timeout=10
    while [ -e "/proc/$pid" ] && [ $timeout -gt 0 ]; do
        sleep 1
        timeout=$((timeout-1))
    done
    # 强制终止
    [ -e "/proc/$pid" ] && kill -KILL "$pid"
    # 清理资源
    rm -f "$CONFIG_FILE_TMP"   # 删除临时配置文件
    rm -f "$PID_FILE"
    rm -f "$STATUS_FILE"
}


# 注意:根据需求不同,需要注意:
# 1. 添加procd_set_param file "$CONFIG_FILE",注释该方法  这会使用procd,他会调用start\stop方法 
# 2. 删除procd_set_param file "$CONFIG_FILE",解注该方法  daemon中trap sighup方法,不会调用start\stop方法
#reload_service() {
    # 重新载入配置文件    
#    logger -t Side-route "Reload_service Reloading configuration"
#   [ -e "$PID_FILE" ] && kill -HUP $(cat "$PID_FILE")
#}


