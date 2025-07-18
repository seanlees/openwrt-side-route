module("luci.controller.side_route.index", package.seeall)

function index()
    -- 主菜单项
    local page = entry({"admin", "services", "side_route"}, nil, _("Side Route"), 100)
    page.dependent = true
    page.target = alias("admin", "services", "side_route", "index")
    page.leaf = true

    -- 设置主页
    entry({"admin", "services", "side_route", "index"}, cbi("side_route/side_route"), _("Side Route"), 10)

    -- 新增设备
    entry({"admin", "services", "side_route", "device-edit", "-"}, cbi("side_route/device_form"), _("Add New Device"), nil)

    -- 编辑设备（ID 匹配）
    entry({"admin", "services", "side_route", "device-edit", "%d+"}, cbi("side_route/device_form"), _("Edit Device"), nil)
end