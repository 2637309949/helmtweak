#ifndef HelmSystemInfo_h
#define HelmSystemInfo_h

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, HelmPath) {
    HelmPathMobileSubstrate,      // /Library/MobileSubstrate/DynamicLibraries
    HelmPathPreferenceBundles,    // /Library/PreferenceBundles
    HelmPathPreferenceLoader,     // /Library/PreferenceLoader/Preferences
    HelmPathUsrBin,               // /usr/bin
    HelmPathUsrLib,               // /usr/lib
    HelmPathSystemLibrary,        // /Library
};

/// 系统信息查询 + jailbreak 路径解析。工具层**唯一**允许接触 rootless/roothide 路径语义的地方。
/// 所有 `rootfs()`/`jbroot()` 调用、`/var/jb` 硬编码、iOS 版本号，一律经这里查，不直接写死。
@interface HelmSystemInfo : NSObject

+ (BOOL)isSupportedOnCurrentIOS;

+ (NSInteger)iOSMajorVersion;
+ (NSString *)iOSVersionString;

+ (BOOL)isRootless;
+ (BOOL)isRoothide;
+ (BOOL)isRootful;

/// jailbreak 根路径：rootless -> /var/jb，roothide/rootful -> /（或 libroothide 报告的 jb root）。
+ (NSString *)jbRootPath;

/// 把某个逻辑路径解析成当前 scheme 下的真实路径（等价旧 `rootfs()`）。
+ (NSString *)rootfs:(NSString *)path;

/// 把某个逻辑路径解析成 jailbreak 安装根下的路径（等价旧 `jbroot()`）。
+ (NSString *)jbroot:(NSString *)path;

/// 常用安装路径，scheme 自动适配（rootless 自动前缀 /var/jb，绝不在工具层写死）。
+ (NSString *)pathFor:(HelmPath)path;

/// 设备型号标识符，如 "iPhone12,1"（A12 -> iPhone11,* 起）。
+ (NSString *)deviceModelIdentifier;

/// A12+ 设备 = arm64e。
+ (BOOL)isArm64eDevice;

@end

#endif
