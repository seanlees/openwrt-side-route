#!/bin/sh /etc/rc.common

# 启动顺序
START=95
STOP=10

# start 函数
start() {
    # 载入/etc/config/bargo 中的配置信息，以供我们的程序使用
    config_load side-route
    # 可以判断 enable 是否勾选并执行我们的程序
    echo "Side Route Client has start."

    procd_open_instance
    procd_set_param command /usr/sbin/ride-route-daemon -c /etc/config/side-route
    procd_set_param respawn  # 崩溃时自动重启
    procd_set_param file /etc/config/side-route  # 监听配置文件
    procd_close_instance
}

stop() {
    # 清理程序产生的内容
    echo "Side Route Client has stoped."
     killall -HUP side-route-daemon
}

reload_service() {
    # 重新载入配置文件
    echo "Side Route Client has reloaded."
}
