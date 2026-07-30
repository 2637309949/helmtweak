# ===== HelmTweak — Dopamine rootless (ElleKit) minimal demo =====
TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HelmTweak

HelmTweak_FILES = Tweak.x
HelmTweak_CFLAGS = -fobjc-arc -Wno-unused-variable
HelmTweak_FRAMEWORKS = Foundation UIKit
# 用 ldid 把以下 entitlements 嵌入并签名 dylib
HelmTweak_ENTITLEMENTS = entitlements.plist

include $(THEOS_MAKE_PATH)/tweak.mk
