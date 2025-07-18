-- device_form.lua
require("luci.cbi")
local Map = luci.cbi.Map
local TypedSection = luci.cbi.TypedSection
local Value = luci.cbi.Value
local Button = luci.cbi.Button
local uci = require("luci.model.uci").cursor()
local dispatcher = require "luci.dispatcher"
local sys = require "luci.sys"

-- 正确获取 sid 参数的方法
local sid = luci.dispatcher.context.path[5] or "-" -- 从请求路径中提取参数
-- 记录日志用于调试
sys.exec(string.format('logger -t LUCI_DEBUG "CBI: sid=%s"', tostring(sid)))

local title
-- 动态设置页面标题
if sid == "-" then
    title = translate("Add New Device")
else
    local id = tonumber(sid)
    if id and id > 0 then
        title = translatef("Edit Device (%d)", id)
    else
        title = translate("Device Configuration")
    end
end

local m = Map("side-route", title, translate("Configure side-route, Powered By xxx."))
m.description = translate("Configure side-route, Powered By xxx.")
m.pageaction = false
m.apply = false

local s = m:section(TypedSection, "device", translate("Manage devices that use scientific routing"))
s.anonymous = true  -- 允许匿名设备（无名称段落）
s.addremove = false  -- 可添加/删除条目

-- 只显示当前设备
function s.filter(self, section)
    -- 在添加模式下，会显示新创建的 section
    -- 在编辑模式下，只显示指定 sid 的 section
    return section == (sid == "-" and self.newsection or sid)
end

-- 为添加操作创建新的 section ID
if sid == "-" then
    s.newsection = "new_device_" .. os.time()
    -- 创建临时 section 但不要保存到 UCI
    uci:set("side-route", s.newsection, "device")
else
    -- 设置当前 section 为要编辑的 sid
    s.section = sid
end   

-- 设备名称
local device_name = s:option(Value, "name", translate("Device Name"))
device_name.rmempty = false  -- 不允许为空

-- IP 地址
local device_ip = s:option(Value, "ip", translate("IP Address"))
device_ip.datatype = "ipaddr"
device_ip.rmempty = false

-- 是否启用科学上网路由
local device_enable = s:option(Value, "enable", translate("Use Scientific Routing"))
device_enable:value("1", translate("Yes"))
device_enable:value("0", translate("No"))
device_enable.default = "0"

-- 提交前执行
--[[ function m.handle(map, state)
    if state == "submitted" then
        -- 可在此处添加提交后执行的逻辑
        uci:commit("side-route")  -- 确保提交
        -- os.execute("/usr/bin/update_scientific_rules.sh")  -- 可选：执行外部脚本
    end
    return true
end ]]

return m


