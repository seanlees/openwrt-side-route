#!/bin/sh /etc/rc.common

# 启动顺序
START=95
STOP=10

# start 函数
start() {
    # 可以判断 enable 是否勾选并执行我们的程序
    echo "Side Route Client has start."

    cp /etc/config/side-route /tmp/side-route

    # 载入/etc/config/side-route 中的配置信息，以供我们的程序使用
    config_load side-route

    procd_open_instance
    procd_set_param command /usr/bin/lua /usr/sbin/side-route-daemon.lua
    procd_set_param pidfile /var/run/side-route.pid
    procd_set_param respawn  # 崩溃时自动重启
    procd_set_param file /etc/config/side-route
    procd_close_instance
}

stop() {
    # 清理程序产生的内容
    echo "Side Route Client has stoped."
    kill -HUP $(cat /var/run/ride-route.pid 2>/dev/null) 2>/dev/null
}

reload_service() {
    # 重新载入配置文件
    echo "Side Route Client has reloaded."
}
