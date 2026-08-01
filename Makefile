# ===== HelmTweak — Dopamine rootless (ElleKit) minimal demo =====
TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HelmTweak HelmMCP

HelmTweak_FILES = Tweak.x
HelmTweak_CFLAGS = -fobjc-arc -Wno-unused-variable
HelmTweak_FRAMEWORKS = Foundation UIKit
# 用 ldid 把以下 entitlements 嵌入并签名 dylib
HelmTweak_ENTITLEMENTS = entitlements.plist

# ===== HelmMCP — forked from witchan/ios-mcp (GPL-3.0), core dylib only =====
# Helpers (mcp-root/mcp-ldid/mcp-logreader/AppSync/mcp-roothelper) 见 tools/mcp/helpers/
HelmMCP_FILES = tools/mcp/Tweak.x tools/mcp/MCPServer.m tools/mcp/MCPLogger.m \
                tools/mcp/ClipboardManager.m \
                tools/mcp/FileSystemManager.m tools/mcp/LogManager.m
HelmMCP_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations -I$(THEOS_PROJECT_DIR)/SDK
HelmMCP_FRAMEWORKS = IOKit UIKit CoreGraphics QuartzCore MobileCoreServices AVFoundation Security Vision
HelmMCP_ENTITLEMENTS = tools/mcp/entitlements.plist
# 链接 HelmCore SDK dylib（CI 前置步骤先 build；after-stage 把它拷进 deb 的 /usr/lib）
HelmMCP_LDFLAGS = $(THEOS_PROJECT_DIR)/SDK/HelmCore/.theos/obj/HelmCore.dylib
# 双 scheme 自适应（抄上游 ios-mcp 模式）：
#   roothide -> 链真 <roothide.h>（libroothide）+ -DMCP_ROOTHIDE=1
#   rootless -> 用 tools/mcp/roothide_shim.h fallback，-DMCP_ROOTLESS=1
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
    HelmMCP_LIBRARIES = roothide
    HelmMCP_CFLAGS += -DMCP_ROOTHIDE=1
else ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
    HelmMCP_CFLAGS += -DMCP_ROOTLESS=1
endif

include $(THEOS_MAKE_PATH)/tweak.mk

# ===== PreferenceBundle: Settings.app 入口，显示 hello =====
BUNDLE_NAME = HelmTweakPrefs
HelmTweakPrefs_FILES = HelmTweakPrefs.mm MCPPrefsListController.mm
HelmTweakPrefs_CFLAGS = -fobjc-arc -Wno-unused-variable -I$(THEOS_PROJECT_DIR)/SDK
HelmTweakPrefs_FRAMEWORKS = UIKit Preferences
HelmTweakPrefs_PRIVATE_FRAMEWORKS = Preferences
HelmTweakPrefs_INSTALL_PATH = /Library/PreferenceBundles
HelmTweakPrefs_RESOURCE_DIRS = HelmTweakPrefs
# 链接 HelmCore SDK dylib（工具箱列表用 HelmSystemInfo 查 iOS 版本 / scheme）
HelmTweakPrefs_LDFLAGS = $(THEOS_PROJECT_DIR)/SDK/HelmCore/.theos/obj/HelmCore.dylib
include $(THEOS_MAKE_PATH)/bundle.mk

# ===== Bundle CLI helpers into deb staging dir =====
# 每个 helper 自己一个 Makefile 在 tools/helpers/<name>/，主项目 build 前要先 `make` 它们。
# after-stage 把 build 好的 binary 拷进 staging，按 scheme 决定哪些 helper 进。
# - rootless: mcp-logreader + mcp-ldid + mcp-appsync (dylibs + appinst CLI，靠 vendored libzip)
# - roothide: 上面全部 + mcp-root (setuid) + mcp-roothelper (setuid)
HELPERS_DIR := $(THEOS_PROJECT_DIR)/tools/mcp/helpers
MSDYNLIB_DIR = $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries

after-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/usr/bin"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/usr/lib"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(MSDYNLIB_DIR)"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(THEOS_PROJECT_DIR)/SDK/HelmCore/.theos/obj/HelmCore.dylib" "$(THEOS_STAGING_DIR)/usr/lib/HelmCore.dylib"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(HELPERS_DIR)/mcp-logreader/.theos/obj/mcp-logreader" "$(THEOS_STAGING_DIR)/usr/bin/mcp-logreader"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(HELPERS_DIR)/mcp-ldid/.theos/obj/mcp-ldid" "$(THEOS_STAGING_DIR)/usr/bin/mcp-ldid"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(HELPERS_DIR)/mcp-appsync/appinst/.theos/obj/mcp-appinst" "$(THEOS_STAGING_DIR)/usr/bin/mcp-appinst"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(HELPERS_DIR)/mcp-appsync/.theos/obj/mcp-appsync-installd.dylib" "$(MSDYNLIB_DIR)/mcp-appsync-installd.dylib"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(HELPERS_DIR)/mcp-appsync/AppSyncUnified-installd/mcp-appsync-installd.plist" "$(MSDYNLIB_DIR)/mcp-appsync-installd.plist"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(HELPERS_DIR)/mcp-appsync/.theos/obj/mcp-appsync-frontboard.dylib" "$(MSDYNLIB_DIR)/mcp-appsync-frontboard.dylib"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(HELPERS_DIR)/mcp-appsync/AppSyncUnified-FrontBoard/mcp-appsync-frontboard.plist" "$(MSDYNLIB_DIR)/mcp-appsync-frontboard.plist"$(ECHO_END)
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
	$(ECHO_NOTHING)cp "$(HELPERS_DIR)/mcp-root/.theos/obj/mcp-root" "$(THEOS_STAGING_DIR)/usr/bin/mcp-root"$(ECHO_END)
	$(ECHO_NOTHING)chmod 4755 "$(THEOS_STAGING_DIR)/usr/bin/mcp-root"$(ECHO_END)
	$(ECHO_NOTHING)cp "$(HELPERS_DIR)/mcp-roothelper/.theos/obj/mcp-roothelper" "$(THEOS_STAGING_DIR)/usr/bin/mcp-roothelper"$(ECHO_END)
	$(ECHO_NOTHING)chmod 4755 "$(THEOS_STAGING_DIR)/usr/bin/mcp-roothelper"$(ECHO_END)
endif
