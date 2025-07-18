-- device_form.lua
require("luci.cbi")
local Map = luci.cbi.Map
local TypedSection = luci.cbi.TypedSection
local Value = luci.cbi.Value
local Button = luci.cbi.Button
local uci = require("luci.model.uci").cursor()
local dispatcher = require "luci.dispatcher"

-- 正确获取 sid 参数的方法
local sid = luci.dispatcher.context.path[6]  -- 从请求路径中提取参数
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

local m = Map("side-route", title, translate("Configure site-route, Powered By xxx."))
m.description = translate("Configure site-route, Powered By xxx.")

local s = m:section(TypedSection, "device", translate("Manage devices that use scientific routing"))
s.anonymous = true  -- 允许匿名设备（无名称段落）
s.addremove = true  -- 可添加/删除条目

s.newsection = "new_device_" .. os.time()

-- 设置 filter 函数，仅匹配当前 sid 的段落（如果是编辑模式）
function s.filter(self, section)
    if sid == "-" then
       return section == self.newsection
    else
        -- 编辑模式：只匹配指定 sid 的段落
        return section == sid
    end
end

-- 设备名称
local device_name = s:option(Value, "name", translate("Device Name"))
device_name.rmempty = false  -- 不允许为空

-- MAC 地址
local device_mac = s:option(Value, "mac", translate("MAC Address"))
device_mac.datatype = "macaddr"  -- 数据类型验证为 MAC 地址
device_mac.rmempty = false

-- 是否启用科学上网路由
local device_scientific = s:option(Value, "scientific", translate("Use Scientific Routing"))
device_scientific:value("1", translate("Yes"))
device_scientific:value("0", translate("No"))
device_scientific.default = "0"

-- 提交前执行
function m.handle(map, state)
    if state == "submitted" then
        -- 可在此处添加提交后执行的逻辑
        uci:commit("side-route")  -- 确保提交
        -- os.execute("/usr/bin/update_scientific_rules.sh")  -- 可选：执行外部脚本
    end
    return true
end

return m


