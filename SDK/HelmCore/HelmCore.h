#ifndef HelmCore_h
#define HelmCore_h

// HelmCore SDK umbrella header.
// 工具层只允许经 HelmCore 高层 API 访问系统能力，禁止直接碰私有 header / 版本号 / 私有 selector。

#import <HelmCore/System/HelmSystemInfo.h>
#import <HelmCore/System/HelmLogger.h>
#import <HelmCore/System/HelmScreenManager.h>
#import <HelmCore/System/HelmOCRManager.h>
#import <HelmCore/System/HelmHIDManager.h>
#import <HelmCore/System/MCPProcessUtil.h>
#import <HelmCore/System/AppManager.h>
#import <HelmCore/System/AccessibilityManager.h>
#import <HelmCore/System/TextInputManager.h>

#endif
