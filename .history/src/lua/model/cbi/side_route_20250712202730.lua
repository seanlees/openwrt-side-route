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
local uci = require "luci.model.uci".cursor()

-- 创建配置页面
local m = Map("side-route", translate("Site Route"), translate("Configure site-route, Powered By xxx."))
m.pageaction = false
m.apply = false

-- ========== 全局配置 ==========
local g = m:section(TypedSection, "global", translate("Global Settings"))
g.anonymous = false
g.addremove = false  -- 可添加/删除条目

-- 添加一个路由表
local route_table_id = g:option(Value, "route_table_name", translate("Site Route Table ID"))
route_table_id.rmempty = false
route_table_id.datatype="integer"
-- 添加一个旁路由IP
local route_side_ip = g:option(Value, "route_side_ip", translate("Site Route IP"))
route_side_ip.rmempty = false
route_side_ip.datatype="ipaddr"
-- 添加一个选择网络接口
local route_interface = g:option(Value, "route_interface", translate("Site Route Interface"))
route_interface.rmempty = false
route_interface.default = "br-lan"
for _, iface in ipairs(net:get_networks()) do
    local name = iface:name()
    local title = iface:get_i18n()
    route_interface:value(name, "%s (%s)" %{ title, name })
end
-- 添加一个路由规则mark
local route_mark = g:option(Value, "route_mark", translate("Site Route Mark"))
route_mark.rmempty = false
route_mark.datatype="integer"

-- 应用按钮
local apply = g:option(Button, "_apply", translate("Apply Changes"))
apply.inputtitle = translate("Apply and Refresh Rules")
apply.inputstyle = "apply"
apply.write = function(self, section)
    -- 强制解析表单以更新 changed 状态
    self.map:parse()
    if self.map.changed then
        -- 显式保存表单更改到内存
        self.map:save()
        uci:save("side-route")
        uci:commit("side-route")
        -- os.execute("/usr/bin/update_scientific_rules.sh")
    else
    end
    
   
end

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

for k, v in ipairs(uci:get_all("site-route")) do
    if v[".type"] == "device" then
        table.insert(custom_section.data.devices, {
            sid = k,
            name = v.name,
            mac = v.mac,
            scientific = v.scientific
        })
    end
end



return m