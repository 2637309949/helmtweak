// HelmTweakPrefs — PreferenceBundle for Settings.app
// Settings 根入口，显示 hello 分组标题 + 工具箱列表（按当前系统 minIOS/maxIOS/scheme 过滤）
// PSListController 的 loadSpecifiersFromPlistName:target: 是 working
// jailbreak tweak 标准模式（参考 Velvet2 RootListController）

#import <Preferences/Preferences.h>
#import <HelmCore/HelmCore.h>

@interface PSListController (HelmTweakPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface PSSpecifier (HelmTweakPrivate)
+ (PSSpecifier *)preferenceSpecifierNamed:(NSString *)name
                                   target:(id)target
                                      set:(SEL)set
                                      get:(SEL)get
                                   detail:(Class)detail
                                     cell:(PSCellType)cell
                                     edit:(Class)edit;
+ (PSSpecifier *)groupSpecifierWithName:(NSString *)name;
- (void)setEnabled:(BOOL)enabled;
@end

@interface HelmTweakPrefsListController : PSListController
@end

@implementation HelmTweakPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self appendToolboxSpecifiers];
    }
    return _specifiers;
}

// 工具箱列表：读 bundle 内 tool_manifest.json，按当前 iOS 版本 + scheme 灰掉不兼容 cell。
- (void)appendToolboxSpecifiers {
    NSInteger major = [HelmSystemInfo iOSMajorVersion];
    BOOL rootless = [HelmSystemInfo isRootless];

    NSArray *manifest = [self loadToolManifest];
    if (!manifest.count) return;

    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"工具箱（按当前系统过滤）"];
    [_specifiers addObject:group];

    for (NSDictionary *tool in manifest) {
        if (![tool isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = tool[@"name"];
        if (!name.length) continue;

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
        NSString *label = incompatible
            ? [NSString stringWithFormat:@"%@ — %@", name, reason]
            : name;

        PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                           target:nil
                                                              set:NULL
                                                              get:NULL
                                                           detail:nil
                                                             cell:PSLinkCell
                                                             edit:nil];
        [spec setEnabled:!incompatible];
        [_specifiers addObject:spec];
    }
}

- (NSArray *)loadToolManifest {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"tool_manifest" ofType:@"json"];
    if (!path) return @[];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @[];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSArray class]]) return @[];
    return obj;
}

@end
