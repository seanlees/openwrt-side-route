#!/bin/sh /etc/rc.common

# 启动顺序
START=95

# start 函数
start() {
    # 载入/etc/config/bargo 中的配置信息，以供我们的程序使用
    config_load side-route
    # 可以判断 enable 是否勾选并执行我们的程序
    echo "Side Route Client has start."
}

stop() {
    # 清理程序产生的内容
    echo "Side Route Client has stoped."
}

reload() {
    # 重新载入配置文件
    echo "Side Route Client has reloaded."
}
