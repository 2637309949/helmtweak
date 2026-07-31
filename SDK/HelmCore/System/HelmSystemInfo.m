#import "HelmSystemInfo.h"
#import <sys/utsname.h>

#if defined(HELM_CORE_ROOTHIDE)
#import <roothide.h>
#endif

@implementation HelmSystemInfo

+ (BOOL)isSupportedOnCurrentIOS {
    return YES;
}

+ (NSInteger)iOSMajorVersion {
    NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
    return version.majorVersion;
}

+ (NSString *)iOSVersionString {
    NSOperatingSystemVersion version = [NSProcessInfo processInfo].operatingSystemVersion;
    return [NSString stringWithFormat:@"%ld.%ld.%ld",
            (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion];
}

+ (BOOL)isRootless {
#if defined(HELM_CORE_ROOTLESS)
    return YES;
#elif defined(HELM_CORE_ROOTHIDE)
    return NO;
#else
    // 编译期没标记 scheme 时回退到运行时探测
    NSFileManager *fm = [NSFileManager defaultManager];
    return [fm fileExistsAtPath:@"/var/jb"];
#endif
}

+ (BOOL)isRoothide {
#if defined(HELM_CORE_ROOTHIDE)
    return YES;
#else
    return NO;
#endif
}

+ (BOOL)isRootful {
    return ![self isRootless] && ![self isRoothide];
}

+ (NSString *)jbRootPath {
#if defined(HELM_CORE_ROOTHIDE)
    NSString *root = jbroot(@"/");
    return root.length > 0 ? root : @"/";
#elif defined(HELM_CORE_ROOTLESS)
    return @"/var/jb";
#else
    if ([self isRootless]) return @"/var/jb";
    return @"/";
#endif
}

+ (NSString *)rootfs:(NSString *)path {
    if (path.length == 0) return path;

#if defined(HELM_CORE_ROOTHIDE)
    return rootfs(path);
#elif defined(HELM_CORE_ROOTLESS)
    if ([path hasPrefix:@"/var/jb"]) return path;
    return [NSString stringWithFormat:@"/var/jb%@", path];
#else
    if ([self isRootless]) {
        if ([path hasPrefix:@"/var/jb"]) return path;
        return [NSString stringWithFormat:@"/var/jb%@", path];
    }
    return path;
#endif
}

+ (NSString *)jbroot:(NSString *)path {
    if (path.length == 0) return path;

#if defined(HELM_CORE_ROOTHIDE)
    return jbroot(path);
#else
    return [self rootfs:path];
#endif
}

+ (NSString *)pathFor:(HelmPath)path {
    switch (path) {
        case HelmPathMobileSubstrate:
            return [self rootfs:@"/Library/MobileSubstrate/DynamicLibraries"];
        case HelmPathPreferenceBundles:
            return [self rootfs:@"/Library/PreferenceBundles"];
        case HelmPathPreferenceLoader:
            return [self rootfs:@"/Library/PreferenceLoader/Preferences"];
        case HelmPathUsrBin:
            return [self rootfs:@"/usr/bin"];
        case HelmPathUsrLib:
            return [self rootfs:@"/usr/lib"];
        case HelmPathSystemLibrary:
            return [self rootfs:@"/Library"];
        default:
            return nil;
    }
}

+ (NSString *)deviceModelIdentifier {
    struct utsname systemInfo;
    if (uname(&systemInfo) != 0) return nil;
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

+ (BOOL)isArm64eDevice {
    // arm64e = A12 起（iPhoneXS/XS Max/XR, iPhone11,* -> 全系 A12+）。用 uname machine 前缀判断。
    NSString *model = [self deviceModelIdentifier];
    if (model.length < 9) return NO;

    // iPhone11,* 及之后都是 arm64e；iPhone10,*（iPhone X / 8）是 arm64 非 arm64e。
    if ([model hasPrefix:@"iPhone11,"]) return YES;
    if ([model hasPrefix:@"iPhone12,"]) return YES;
    if ([model hasPrefix:@"iPhone13,"]) return YES;
    if ([model hasPrefix:@"iPhone14,"]) return YES;
    if ([model hasPrefix:@"iPhone15,"]) return YES;
    if ([model hasPrefix:@"iPhone16,"]) return YES;

    // iPad Pro 3rd gen（A12X）起：iPad8,*。iPad 无 Home 键的 A12+ 平板都属于 arm64e。
    if ([model hasPrefix:@"iPad8,"]) return YES;
    if ([model hasPrefix:@"iPad11,"]) return YES;
    if ([model hasPrefix:@"iPad13,"]) return YES;
    if ([model hasPrefix:@"iPad14,"]) return YES;

    return NO;
}

@end
