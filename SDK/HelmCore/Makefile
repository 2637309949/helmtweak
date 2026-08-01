ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
    export TARGET = iphone:clang:latest:15.0
else
    export TARGET = iphone:clang:latest:15.0
endif
export ARCHS = arm64 arm64e
export DEBUG = 0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = HelmCore
HelmCore_FILES = System/HelmSystemInfo.m System/HelmLogger.m \
                System/HelmScreenManager.m System/HelmOCRManager.m \
                System/HelmHIDManager.m \
                System/MCPProcessUtil.m System/AppManager.m System/AccessibilityManager.m \
                System/MCPAXQueryContext.m System/MCPAXAttributeBridge.m System/MCPAXNodeSource.m \
                System/MCPAXRemoteContextResolver.m System/MCPUIElementSerializer.m \
                System/MCPUIElementsFacade.m System/TextInputManager.m
HelmCore_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations -Wno-unused-function -I$(THEOS_PROJECT_DIR)/SDK
HelmCore_FRAMEWORKS = Foundation UIKit CoreGraphics QuartzCore Vision IOKit Security AVFoundation MobileCoreServices
# 双 scheme 自适应：
#   roothide -> 链真 <roothide.h>（libroothide）+ -DHELM_CORE_ROOTHIDE=1
#   rootless -> HelmSystemInfo 内部用 /var/jb 逻辑，-DHELM_CORE_ROOTLESS=1
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
    HelmCore_CFLAGS += -DHELM_CORE_ROOTHIDE=1
    HelmCore_LIBRARIES = roothide
else
    HelmCore_CFLAGS += -DHELM_CORE_ROOTLESS=1
endif
HelmCore_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/library.mk
