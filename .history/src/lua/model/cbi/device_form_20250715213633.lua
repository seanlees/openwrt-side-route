-- device_form.lua
require("luci.cbi")
local Map = luci.cbi.Map
local TypedSection = luci.cbi.TypedSection
local Value = luci.cbi.Value
local Button = luci.cbi.Button
local ListValue = luci.cbi.ListValue
local DynamicList = luci.cbi.DynamicList
local Flag = luci.cbi.Flag
local cursor = require("luci.model.uci").cursor()
local dispatcher = require "luci.dispatcher"
local sys = require "luci.sys"
local network = require "luci.model.network"

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
m.pageaction = true
m.apply = true

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
    cursor:set("side-route", s.newsection, "device")
else
    -- 设置当前 section 为要编辑的 sid
    s.section = sid
end   

-- 设备名称
local device_name = s:option(Value, "name", translate("Device Name"))
device_name.rmempty = false  -- 不允许为空

-- IP 地址
local device_ip = s:option(DynamicList, "ip", translate("IP Address"))
device_ip.datatype = "ipaddr"
device_ip.rmempty = false
device_ip.placeholder = "e.g. 192.168.1.100"
-- 只需添加路由器自身 IP
local network = network.init()
local router_ip
local lan = network:get_network("lan")
if lan then
    router_ip = lan:ipaddr()
end
function read_arptable()
    local f = io.open("/proc/net/arp")
    local arp_table = {}

    if not f then
        print("无法打开 /proc/net/arp")
        return arp_table
    end

    for line in f:lines() do
        -- 只提取 IP 和 MAC（第1列和第4列）
        local ip, mac = line:match("([^%s]+)%s+[^%s]+%s+[^%s]+%s+([^%s]+)")
        if ip and mac and ip ~= "IP" then
            table.insert(arp_table, {
                ["IP address"] = ip,
                ["HW address"] = mac
            })
        else
            -- 可选：打印无法解析的行，方便调试
            -- print("无法解析: " .. line)
        end
    end

    f:close()
    return arp_table
end
local arp_table = read_arptable()
local route_side_ip = cursor:get("side-route", "global", "route_side_ip")
for _, entry in ipairs(arp_table) do
    local ip = entry["IP address"]
    
        device_ip:value(ip)
    
end


-- 是否启用科学上网路由
local device_enable = s:option(Flag, "enable","Enabled", translate("Use Routing"))
device_enable.default = "1"
device_enable.disable = "0"
device_enable.enable = "1"

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


