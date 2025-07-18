#!/bin/sh /etc/rc.common

USE_PROCD=1

# 启动顺序
START=95
STOP=10

CONFIG_FILE="/etc/config/side-route"
TMP_CONFIG="/tmp/side-route"
PID_FILE="/var/run/side-route.pid"
local CONFIG_FILE = "/etc/config/side-route"
local TMP_CONFIG = "/tmp/side-route-config"
local PID_FILE = "/var/run/side-route.pid"

# start 函数
start_service() {
    # 可以判断 enable 是否勾选并执行我们的程序
    echo "Side Route Client has start."

    cp "$CONFIG_FILE" "$TMP_CONFIG"

    procd_open_instance
    procd_set_param command /usr/bin/lua /usr/sbin/side-route-daemon.lua
    procd_set_param pidfile "$PID_FILE"
    procd_set_param respawn  # 崩溃时自动重启
    procd_set_param file "$CONFIG_FILE"
    procd_close_instance
}

stop_service() {
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
    rm -f "$TMP_CONFIG"   # 删除临时配置文件
    rm -f "$PID_FILE"
}

reload_service() {
    # 重新载入配置文件
    echo "Side Route Client has reloaded."
    [ -e "$PID_FILE" ] && kill -HUP $(cat "$PID_FILE")
}
