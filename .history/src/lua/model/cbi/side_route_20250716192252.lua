-- 引入正确的模块
local cbi = require "luci.cbi"
local Map = cbi.Map
local TypedSection = cbi.TypedSection
local NamedSection = cbi.NamedSection
local Value = cbi.Value
local Button = cbi.Button
local DummyValue = cbi.DummyValue
-- network
local network = require "luci.model.network"
local net = network.init()
-- uci
local uci = require"luci.model.uci".cursor(nil, true)
local sys = require "luci.sys"
local util = require("luci.util")

-- 创建配置页面
local m = Map("side-route", translate("Side Route"), translate("Configure side-route, Powered By xxx."))
m.pageaction = true
m.apply = true

-- ========== 全局配置 ==========
local g = m:section(NamedSection, "global", "global", translate("Global Settings"))
g.anonymous = true
g.addremove = false -- 可添加/删除条目

-- 添加一个路由表
local route_table_id = g:option(Value, "route_table_num", translate("Side Route Table ID"))
route_table_id.rmempty = false
route_table_id.datatype = "integer"
-- 添加一个旁路由IP
local route_side_ip = g:option(Value, "route_side_ip", translate("Side Route IP"))
route_side_ip.rmempty = false
route_side_ip.datatype = "ipaddr"
-- 添加一个选择网络接口
local route_interface = g:option(Value, "route_interface", translate("Side Route Interface"))
route_interface.rmempty = false
route_interface.default = "br-lan"
for _, iface in ipairs(net:get_networks()) do
    local name = iface:name()
    local title = iface:get_i18n()
    route_interface:value(name, "%s (%s)" % {title, name})
end
-- 添加一个路由规则mark
local route_mark = g:option(Value, "route_mark", translate("Side Route Mark"))
route_mark.rmempty = false
route_mark.datatype = "integer"

local check_timeout = g:option(Value, "check_timeout", translate("Check Timeout(seconds)"))
check_timeout.rmempty = false
check_timeout.default = "15"

-- ========== 设备管理表格 ==========
--[[ local custom_section = m:section(cbi.SimpleSection, "device_list", translate("Manage Devices"))
custom_section.description = translate("You can manage all your devices here.")

-- 自定义模板路径
custom_section.template = "side_route/side_route"

-- 准备数据传入模板
custom_section.data = {
    build_url = luci.dispatcher.build_url,
    devices = {}
}

local side_route_config = uci:get_all("side-route") or {}
-- sys.exec(string.format('logger -t LUCI_DEBUG "side-route devices: %s"', util.serialize_data(side_route_config)))

for k, v in pairs(side_route_config) do
    if v[".type"] == "device" then
        table.insert(custom_section.data.devices, {
            sid = k,
            name = v.name,
            ip = v.ip,
            enable = v.enable
        })
    end
end ]]

-- 显示设备列表
local device_section = m:section(cbi.TypedSection, "device", translate("Device List"))
device_section.description = translate("You can manage all your devices here.")
device_section.addremove = true -- 禁止通过界面添加或删除设备
device_section.anonymous = true  -- 不显示节名称
device_section.template = "cbi/tblsection"

-- ==== 自定义添加设备时的 SID 生成逻辑 ====
device_section.on_add = function(section)
    local sid = "device_" .. os.time()
    return sid
end

-- 设备名称
local name_opt = device_section:option(Value, "name", translate("Device Name"))
name_opt.rmempty = false

name_opt.validate = function(self, value, section)
    if not value or value == "" then
        return nil
    end

    local exists = false
    local sections = self.map:get_all("device")

    for k, v in pairs(sections) do
        if v[".name"] ~= section and v.name == value then
            exists = true
            break
        end
    end

    if exists then
        return nil, translate("Device name must be unique")
    else
        return value
    end
end
-- IP地址
local ip_opt = device_section:option(Value, "ip", translate("IP Address"))
ip_opt.datatype = "ipaddr"
ip_opt.validate = function(self, value, section)
    if not value or value == "" then
        return nil
    end

    local exists = false
    local sections = self.map:get_all("device")

    for k, v in pairs(sections) do
        if v[".name"] ~= section and v.ip == value then
            exists = true
            break
        end
    end

    if exists then
        return nil, translate("IP address must be unique")
    else
        return value
    end
end
-- 启用状态
device_section:option(Flag, "enable", translate("Enabled")).default = "1"

-- sys.exec(string.format('logger -t LUCI_DEBUG "custom_section.data:\\n%s"',util.serialize_data(custom_section.data)))

-- 使用procd触发重载,不需要手动
--[[ function m.on_commit(map)
    if map.changed then
        -- 配置有变化时，触发服务重载
        luci.sys.call("/etc/init.d/side-route reload >/dev/null")
        -- 记录日志以便调试
        luci.sys.call("logger -t side-route 'config changed trigger reload'")
    end
end ]]

return m
