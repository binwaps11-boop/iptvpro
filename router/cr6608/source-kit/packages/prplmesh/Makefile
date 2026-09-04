include $(TOPDIR)/rules.mk

PKG_NAME:=prplmesh
PKG_RELEASE:=4

PKG_SOURCE_VERSION:=25ffcee47f57343e1798c9488f6f802fccc0e0ff
PKG_VERSION:=4.3.1
PKG_SOURCE:=prplMesh-$(PKG_SOURCE_VERSION).tar.gz
PKG_SOURCE_URL:=https://gitlab.com/prpl-foundation/prplmesh/prplMesh/-/archive/$(PKG_SOURCE_VERSION)
PKG_HASH:=8a21124cab0ec71fd235662b561717104d92dda323676cf1244124f86ff41d73
PKG_BUILD_DIR:=$(BUILD_DIR)/prplMesh-$(PKG_SOURCE_VERSION)
PKG_MAINTAINER:=prpl Foundation <prplmesh@prplfoundation.org>
PKG_LICENSE:=BSD-2-Clause-Patent
PKG_LICENSE_FILES:=LICENSE

PRPLMESH_VERSION:=$(PKG_VERSION)
PRPLMESH_REVISION:=$(PKG_SOURCE_VERSION)

PKG_BUILD_PARALLEL:=1
PKG_CONFIG_DEPENDS:=CONFIG_PRPLMESH_ENABLE_UNIT_TESTS
CMAKE_BINARY_SUBDIR:=build

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/prplmesh
	SECTION:=net
	CATEGORY:=Network
	TITLE:=prplMesh EasyMesh Controller and Agent for CR6608
	URL:=https://gitlab.com/prpl-foundation/prplmesh/prplMesh
	DEPENDS:= \
		+libstdcpp +libpthread +librt +libjson-c +libopenssl +libnl \
		+uci +ubus +ubox +ebtables +getopt +wpad-openssl \
		+kmod-sched-act-vlan +kmod-sched-core +kmod-sched-flower \
		+kmod-sched-prio
endef

define Package/prplmesh/config
	source "$(SOURCE)/Config.in"
endef

CMAKE_OPTIONS+= \
	-DTARGET_PLATFORM=openwrt \
	-DTARGET_PLATFORM_TYPE=turris-omnia \
	-DBWL_TYPE=NL80211 \
	-DENABLE_NBAPI=OFF \
	-DUSE_PRPLMESH_WHM=OFF \
	-DBEEROCKS_BRIDGE_IFACE=br-lan \
	-DBEEROCKS_BH_WIRE_IFACE=lan1 \
	-DBEEROCKS_WLAN1_IFACE=phy0-ap0 \
	-DBEEROCKS_WLAN2_IFACE=phy1-ap0 \
	-DBEEROCKS_WLAN2_STEERING_VAPS= \
	-DBEEROCKS_MONITOR_POLLING_RATE_MSEC=1000 \
	-DBEEROCKS_CONTROLLER_LOG_SIZE=262144 \
	-DBEEROCKS_AGENT_LOG_SIZE=262144 \
	-DBEEROCKS_LOG_FILES_AUTO_ROLL=true \
	-DCMAKE_INSTALL_PREFIX=/opt/prplmesh \
	-DPLATFORM_BUILD_DIR=$(BUILD_DIR) \
	-DPLATFORM_STAGING_DIR=$(STAGING_DIR) \
	-DPLATFORM_INCLUDE_DIR=$(STAGING_DIR)/usr/include \
	-DPython3_EXECUTABLE=$(STAGING_DIR_HOST)/bin/python3 \
	-DPRPLMESH_REVISION=$(PRPLMESH_REVISION) \
	-DPRPLMESH_VERSION=$(PRPLMESH_VERSION) \
	-DCMAKE_CXX_FLAGS="-Wno-error=deprecated-declarations"

ifeq ($(CONFIG_PRPLMESH_ENABLE_UNIT_TESTS),y)
	CMAKE_OPTIONS += -DBUILD_TESTS=ON
endif

$(eval $(call TestHostCommand,python3-yaml, \
	Please install the Python3 YAML module, \
	$(STAGING_DIR_HOST)/bin/python3 -c 'import yaml'))

define Build/InstallDev
	$(INSTALL_DIR) $(1)/usr/lib $(1)/usr/include
	$(CP) $(PKG_INSTALL_DIR)/opt/prplmesh/lib/libbml* $(1)/usr/lib/
	$(CP) $(PKG_INSTALL_DIR)/opt/prplmesh/include/beerocks/bml $(1)/usr/include/
endef

define Package/prplmesh/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/etc/uci-defaults $(1)/usr/sbin
	$(INSTALL_DIR) $(1)/opt/prplmesh $(1)/usr/lib
	$(INSTALL_CONF) ./files/etc/config/prplmesh $(1)/etc/config/prplmesh
	$(INSTALL_BIN) ./files/etc/init.d/prplmesh $(1)/etc/init.d/prplmesh
	$(INSTALL_BIN) ./files/etc/uci-defaults/95-prplmesh-cr6608 $(1)/etc/uci-defaults/95-prplmesh-cr6608
	$(INSTALL_BIN) ./files/usr/sbin/cr6608-prplmesh-sync $(1)/usr/sbin/cr6608-prplmesh-sync
	$(CP) $(PKG_INSTALL_DIR)/opt/prplmesh/bin $(1)/opt/prplmesh/
	$(CP) $(PKG_INSTALL_DIR)/opt/prplmesh/scripts $(1)/opt/prplmesh/
	$(CP) $(PKG_INSTALL_DIR)/opt/prplmesh/share $(1)/opt/prplmesh/
	$(CP) $(PKG_INSTALL_DIR)/opt/prplmesh/config $(1)/opt/prplmesh/
	$(CP) $(PKG_INSTALL_DIR)/opt/prplmesh/lib/*.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,prplmesh))
