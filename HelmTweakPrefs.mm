// HelmTweakPrefs — PreferenceBundle for Settings.app
// Settings 根入口，显示 hello 分组标题 + 工具箱列表（按当前系统 minIOS/maxIOS/scheme 过滤）
// 工具箱 cells 静态定义在 Root.plist，控制器按 tool_id 匹配 tool_manifest.json 灰化不兼容项。
// 注意：不动态构造 PSSpecifier —— 私有构造方法（preferenceSpecifierNamed:/groupSpecifierWithName:）
// 在 iOS 15+ 触发 forwarding 异常（Settings 闪退，2026-08-01 踩过）。

#import <Preferences/Preferences.h>
#import <HelmCore/HelmCore.h>

@interface PSListController (HelmTweakPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface PSSpecifier (HelmTweakPrivate)
- (void)setEnabled:(BOOL)enabled;
@end

@interface HelmTweakPrefsListController : PSListController
@end

@implementation HelmTweakPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self applyToolboxCompatibility];
    }
    return _specifiers;
}

// 遍历 Root.plist 里 id 为 tool_<manifest-id> 的 cell，按当前系统灰化 + 标注原因。
// 只读 manifest 的 name/minIOS/scheme 做判断，不新建 specifier。
- (void)applyToolboxCompatibility {
    NSInteger major = [HelmSystemInfo iOSMajorVersion];
    BOOL rootless = [HelmSystemInfo isRootless];

    NSDictionary *manifestById = [self manifestById];
    if (!manifestById.count) return;

    for (PSSpecifier *spec in _specifiers) {
        NSString *specId = [spec propertyForKey:@"id"];
        if (![specId hasPrefix:@"tool_"]) continue;

        NSString *toolId = [specId substringFromIndex:5];
        NSDictionary *tool = manifestById[toolId];
        if (![tool isKindOfClass:[NSDictionary class]]) continue;

        double minIOS = [tool[@"minIOS"] doubleValue];
        NSString *scheme = [tool[@"scheme"] isKindOfClass:[NSString class]] ? tool[@"scheme"] : nil;

        NSMutableString *reason = [NSMutableString string];
        if (major < (NSInteger)minIOS) {
            [reason appendFormat:@"需要 iOS %.0f+", minIOS];
        }
        if ([scheme isEqualToString:@"roothide"] && !rootless) {
            if (reason.length) [reason appendString:@" 且"];
            [reason appendString:@"需要 roothide 环境"];
        }

        BOOL incompatible = reason.length > 0;
        [spec setEnabled:!incompatible];
        if (incompatible) {
            NSString *name = tool[@"name"];
            if (name.length) {
                [spec setName:[NSString stringWithFormat:@"%@ — %@", name, reason]];
            }
        }
    }
}

- (NSDictionary *)manifestById {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"tool_manifest" ofType:@"json"];
    if (!path) return @{};
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @{};
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSArray class]]) return @{};

    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    for (id entry in obj) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *toolId = entry[@"id"];
        if (toolId.length) byId[toolId] = entry;
    }
    return byId;
}

@end
