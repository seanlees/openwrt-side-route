# Copyright (C) 2016 Openwrt.org
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-side-route
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

# 定义基础信息
define Package/$(PKG_NAME)
	SECTION:=luci
	CATEGORY:=Services
	TITLE:=LuCI Configuration for Side Route
	DEPENDS:=+luci +luci-base +luci-compat +luci-mod-admin-full
	URL:=http://blog.sirgo.com
	MAINTAINER:=skyline661@163.com
endef

# 描述信息
define Package/$(PKG_NAME)/description
	This package contains LuCI configuration pages for side_route.
endef

include $(TOPDIR)/feeds/luci/luci.mk
# call BuildPackage - OpenWrt buildroot signature

# 编译安装
define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/side_route
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller/side_route
	# $(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/side_route

	$(INSTALL_CONF) ./etc/config/side-route $(1)/etc/config/side-route
	$(INSTALL_BIN) ./etc/init.d/side-route.sh $(1)/etc/init.d/side-route
	# $(INSTALL_BIN) ./usr/sbin/side-route-daemon.lua	$(1)/usr/sbin/side-route-daemon.lua
	$(INSTALL_BIN) ./usr/sbin/side-route-daemon.sh	$(1)/usr/sbin/side-route-daemon.sh

	$(CP) ./src/lua/controller/*.lua $(1)/usr/lib/lua/luci/controller/side_route/
	$(CP) ./src/lua/model/cbi/*.lua $(1)/usr/lib/lua/luci/model/cbi/side_route/
	$(CP) ./src/lua/view/*.htm $(1)/usr/lib/lua/luci/view/side_route/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))