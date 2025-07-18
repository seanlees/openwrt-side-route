#!/bin/sh /etc/rc.common

USE_PROCD=1

# 启动顺序
START=95
STOP=10

CONFIG_FILE="/etc/config/side-route"
TMP_CONFIG="/tmp/side-route-config"
PID_FILE="/var/run/ride-route.pid"

# start 函数
start() {
    # 可以判断 enable 是否勾选并执行我们的程序
    echo "Side Route Client has start."

    cp "$CONFIG_FILE" "$TMP_CONFIG"

    procd_open_instance
    procd_set_param command /usr/bin/lua /usr/sbin/side-route-daemon.lua
    procd_set_param pidfile /var/run/side-route.pid
    procd_set_param respawn  # 崩溃时自动重启
    procd_set_param file "$CONFIG_FILE"
    procd_close_instance
}

stop_service() {
    # 清理程序产生的内容
    echo "Side Route Client has stoped."
    # 发送SIGTERM信号，优雅停止守护进程
    kill -TERM $(cat /var/run/ride-route.pid 2>/dev/null) 2>/dev/null
    # 等待进程退出（可选，避免强制终止）
    local i=0
    while [ -e /var/run/ride-route.pid ] && [ $i -lt 10 ]; do
        sleep 1
        i=$((i+1))
    done
    # 如果进程仍未退出，则强制杀死
    if [ -e /var/run/ride-route.pid ]; then
        kill -KILL $(cat /var/run/ride-route.pid 2>/dev/null) 2>/dev/null
        rm -f /var/run/ride-route.pid
    fi
}

reload_service() {
    # 重新载入配置文件
    echo "Side Route Client has reloaded."
    kill -HUP $(cat /var/run/ride-route.pid 2>/dev/null) 2>/dev/null
}
