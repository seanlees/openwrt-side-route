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
m.pageaction = false
m.apply = false

-- ========== 全局配置 ==========
local g = m:section(NamedSection, "global", translate("Global Settings"))
g.anonymous = false
g.addremove = false  -- 可添加/删除条目

-- 保存原始配置用于比较
local original_config = {}
uci:foreach("side-route", "global", function(s)
    original_config = s
end)

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

-- 创建选项列表（不使用 g.options）
local global_options = {
    route_table_id,
    route_side_ip,
    route_interface,
    route_mark
}

-- 自定义应用按钮
local apply = g:option(Button, "_apply", translate("Apply Changes"))
apply.inputtitle = translate("Apply and Refresh Rules")
apply.inputstyle = "apply"

-- 添加自定义重置按钮
local reset = g:option(Button, "_reset", translate("Reset Changes"))
reset.inputtitle = translate("Reset")
reset.inputstyle = "reset"

-- 应用按钮处理函数
function apply.write(self, section)
    -- 手动检测配置变更
    local has_changes = false
    local current_config = {}
    
    -- 收集当前配置值（使用我们定义的选项列表）
    for _, option in ipairs(global_options) do
        local value = option:formvalue(section)
        if value ~= nil then
            current_config[option.option] = value
        end
    end
    sys.exec(string.format('logger -t LUCI_DEBUG "current_config:\\n%s"',util.serialize_data(current_config)))
    
    -- 比较配置是否变化
    for key, value in pairs(current_config) do
        if tostring(original_config[key] or "") ~= tostring(value) then
            has_changes = true
            break
        end
    end
    
    if has_changes then
        -- 显式保存表单更改到内存
        for key, value in pairs(current_config) do
            uci:set("side-route", "global", key, value)
        end
        
        uci:save("side-route")
        uci:commit("side-route")
        
        -- 更新原始配置
        original_config = current_config
        
        -- 执行更新脚本
        -- os.execute("/usr/bin/update_scientific_rules.sh")
        sys.exec(string.format('logger -t LUCI_DEBUG "side-route config changed"'))
        
        -- 显示成功消息
        luci.http.script(
            [[
            setTimeout(function() {
                window.location.reload();
            }, 1000);
            ]]
        )
        return translate("Configuration applied successfully. Page will refresh in 1 second.")

        -- 设置成功消息
        luci.dispatcher.set_message(translate("Configuration applied successfully. Page will refresh in 1 second.!"))
        
        -- 重定向到当前页面
        luci.http.redirect(luci.dispatcher.build_url(luci.dispatcher.context.path))
        return nil

    else
        sys.exec(string.format('logger -t LUCI_DEBUG "side-route config not change"'))
        return translate("No changes detected.")
    end
end
-- 重置按钮处理函数
function reset.write(self, section)
    -- 直接重置 UCI 配置
    uci:revert("side-route", "global")
    uci:save("side-route")
    
    sys.exec('logger -t LUCI_DEBUG "Global settings reset"')
    
    -- 刷新页面显示原始值
    luci.http.script(
        [[
        setTimeout(function() {
            window.location.reload();
        }, 500);
        ]]
    )
    return translate("Configuration reset to original values.")
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

return m