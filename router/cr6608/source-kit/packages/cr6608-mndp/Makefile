include $(TOPDIR)/rules.mk

PKG_NAME:=cr6608-mndp
PKG_VERSION:=1.0.3
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/cr6608-mndp
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Auditable CR6608 MNDP discovery sender
endef

define Package/cr6608-mndp/description
  Minimal source-built MNDP broadcaster used by the CR6608 neighbor service.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/cr6608-mndp-advertise.c $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CPPFLAGS) $(TARGET_CFLAGS) \
		-std=c11 -Wall -Wextra -Werror \
		-o $(PKG_BUILD_DIR)/cr6608-mndp-advertise \
		$(PKG_BUILD_DIR)/cr6608-mndp-advertise.c \
		$(TARGET_LDFLAGS)
endef

define Package/cr6608-mndp/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/cr6608-mndp-advertise \
		$(1)/usr/sbin/cr6608-mndp-advertise
endef

$(eval $(call BuildPackage,cr6608-mndp))
