#!/usr/bin/env lua

local uci = require "uci"
local nixio = require "nixio"
local posix = require "posix"

-- 守护进程化
nixio.daemonize()

-- 创建PID文件
local pidfile = io.open("/var/run/ride-route.pid", "w")
pidfile:write(tostring(posix.getpid("pid")))
pidfile:close()

-- 信号处理
local function handle_signal(sig)
    if sig == nixio.const.SIGHUP then
        reload_config()
    elseif sig == nixio.const.SIGTERM then
        os.remove("/var/run/ride-route.pid")
        os.exit(0)
    end
end

nixio.signal(nixio.const.SIGHUP, handle_signal)
nixio.signal(nixio.const.SIGTERM, handle_signal)

-- 配置重载函数
function reload_config()
    nixio.syslog("info", "Reloading side-route configuration")
    
    local cursor = uci.cursor()
    cursor:load("side-route")

    -- 获取路由表ID
    local route_table_name ,route_side_ip,route_interface,route_mark
    -- 获取旁路由IP
    local route_side_ip = global.route_side_ip
    -- 获取路由规则mark
    local route_mark = global.route_mark
    
    -- 应用路由规则
    cursor:foreach("side-route", "global", function(section)
         route_table_id = section.route_table_name

    end)
end

-- 定义执行 ping 的函数
local function ping(host, count)
    -- 参数校验
    if not host or not count then
        return nil, "参数缺失"
    end

    -- 构建命令（注意转义特殊字符）
    local command = string.format("ping -c %d %q 2>&1", tonumber(count), host)

    -- 执行命令并捕获输出
    local handle = io.popen(command)
    if not handle then
        return nil, "无法执行命令"
    end

    local result = handle:read("*a")
    handle:close()

    local success = false

    -- 匹配 "X packets transmitted, Y received"
    if result:find("(%d+) packets transmitted, (%d+) received") then
        packets_received = tonumber(result:match("(%d+) packets transmitted, (%d+) received"))
        success = true
    end

    return success
end

-- 初始加载配置
reload_config()

-- 主循环（可选）
while true do
    nixio.poll(nil, 60)  -- 60秒超时
    -- 定期维护任务



end



