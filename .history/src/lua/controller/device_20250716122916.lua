-- controller/side_route/device.lua
module("luci.controller.side_route.device", package.seeall)

function index()
    entry({"admin", "services", "side_route", "device", "-"}, cbi("side_route/device_form", {
        display = "modal"
    }), nil)

    entry({"admin", "services", "side_route", "device", "%d+"}, cbi("side_route/device_form", {
        display = "modal"
    }), nil)
end
