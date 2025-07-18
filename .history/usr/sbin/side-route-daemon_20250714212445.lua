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
    nixio.syslog("info", "Reloading ride-route configuration")
    
    local cursor = uci.cursor()
    cursor:load("side-route")

    
    
    -- 应用路由规则
    cursor:foreach("side-route", "routing", function(section)
        os.execute("ip rule add " .. section.rule)
    end)
end



-- 初始加载配置
reload_config()

-- 主循环（可选）
while true do
    nixio.poll(nil, 60)  -- 60秒超时
    -- 定期维护任务



end



