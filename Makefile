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
# Helpers (mcp-root/mcp-ldid/mcp-logreader/AppSync/mcp-roothelper) 留到 Phase 2c
HelmMCP_FILES = tools/mcp/Tweak.x tools/mcp/MCPServer.m tools/mcp/MCPLogger.m \
                tools/mcp/HIDManager.m tools/mcp/ScreenManager.m tools/mcp/ClipboardManager.m \
                tools/mcp/AppManager.m tools/mcp/AccessibilityManager.m tools/mcp/TextInputManager.m \
                tools/mcp/FileSystemManager.m tools/mcp/LogManager.m tools/mcp/OCRManager.m \
                tools/mcp/MCPProcessUtil.m tools/mcp/MCPAXQueryContext.m tools/mcp/MCPAXRemoteContextResolver.m \
                tools/mcp/MCPUIElementSerializer.m tools/mcp/MCPUIElementsFacade.m tools/mcp/MCPAXAttributeBridge.m \
                tools/mcp/MCPAXNodeSource.m
HelmMCP_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations -DMCP_ROOTLESS=1
HelmMCP_FRAMEWORKS = IOKit UIKit CoreGraphics QuartzCore MobileCoreServices AVFoundation Security Vision
HelmMCP_ENTITLEMENTS = tools/mcp/entitlements.plist

include $(THEOS_MAKE_PATH)/tweak.mk

# ===== PreferenceBundle: Settings.app 入口，显示 hello =====
BUNDLE_NAME = HelmTweakPrefs
HelmTweakPrefs_FILES = HelmTweakPrefs.mm MCPPrefsListController.mm
HelmTweakPrefs_CFLAGS = -fobjc-arc -Wno-unused-variable
HelmTweakPrefs_FRAMEWORKS = UIKit Preferences
HelmTweakPrefs_PRIVATE_FRAMEWORKS = Preferences
HelmTweakPrefs_INSTALL_PATH = /Library/PreferenceBundles
HelmTweakPrefs_RESOURCE_DIRS = HelmTweakPrefs
include $(THEOS_MAKE_PATH)/bundle.mk
