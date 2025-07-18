-- controller/side_route/delete.lua
module("luci.controller.side_route.delete", package.seeall)

function index()
    entry({"admin", "services", "side_route", "device_delete"},
        call("delete_device"),
        nil
    )
end

function delete_device()
    local sid = luci.http.formvalue("sid")
    if sid then
        local cursor = require "luci.model.uci".cursor()
        cursor:delete("side-route", sid)
        cursor:commit("side-route")
    end
    
    -- 返回主页面
    luci.http.redirect(luci.dispatcher.build_url("admin/services/side_route"))
end