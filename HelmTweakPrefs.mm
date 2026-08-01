// HelmTweakPrefs — PreferenceBundle for Settings.app
// Settings 根入口，面板只放 MCP 一个工具入口（用户可见的"工具"就是 MCP）。
// 不动态构造或修改 PSSpecifier —— 私有 API 在 iOS 15+ 触发 forwarding 崩溃
// （2026-08-01 两次 Settings 闪退已证实）。

#import <Preferences/Preferences.h>

@interface PSListController (HelmTweakPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface HelmTweakPrefsListController : PSListController
@end

@implementation HelmTweakPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

@end
