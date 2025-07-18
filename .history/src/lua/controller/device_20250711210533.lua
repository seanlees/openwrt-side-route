-- controller/side_route/device_edit.lua

module("luci.controller.side_route.device_edit", package.seeall)

function index()
    entry({"admin", "services", "side_route", "device-edit", "-"},1
        cbi("side_route/device_form"),
        nil)

    entry({"admin", "services", "side_route", "device-edit", "%d+"},
        cbi("side_route/device_form"),
        nil)
end