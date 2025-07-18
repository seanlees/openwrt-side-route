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
local uci = require "luci.model.uci".cursor(nil, true)
local sys = require "luci.sys"
local util = require("luci.util")

-- 创建配置页面
local m = Map("side-route", translate("Side Route"), translate("Configure side-route, Powered By xxx."))
m.pageaction = true
m.apply = true

-- ========== 全局配置 ==========
local g = m:section(NamedSection, "global","global", translate("Global Settings"))
g.anonymous = true
g.addremove = false  -- 可添加/删除条目

-- 添加一个路由表
local route_table_id = g:option(Value, "route_table_name", translate("Side Route Table ID"))
route_table_id.rmempty = false
route_table_id.datatype="integer"
-- 添加一个旁路由IP
local route_side_ip = g:option(Value, "route_side_ip", translate("Side Route IP"))
route_side_ip.rmempty = false
route_side_ip.datatype="ipaddr"
-- 添加一个选择网络接口
local route_interface = g:option(Value, "route_interface", translate("Side Route Interface"))
route_interface.rmempty = false
route_interface.default = "br-lan"
for _, iface in ipairs(net:get_networks()) do
    local name = iface:name()
    local title = iface:get_i18n()
    route_interface:value(name, "%s (%s)" %{ title, name })
end
-- 添加一个路由规则mark
local route_mark = g:option(Value, "route_mark", translate("Side Route Mark"))
route_mark.rmempty = false
route_mark.datatype="integer"

-- ========== 设备管理表格 ==========
local custom_section = m:section(cbi.SimpleSection, "device_list", translate("Manage Devices"))
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
            mac = v.mac,
            scientific = v.scientific
        })
    end
end

-- sys.exec(string.format('logger -t LUCI_DEBUG "custom_section.data:\\n%s"',util.serialize_data(custom_section.data)))

 function m.on_commit(self, section)
    -- 保存旧配置
    local tmp_diff = "/tmp/side_route_diff"
    luci.sys.exec("uci changes side-route > " .. tmp_diff)
end

return m