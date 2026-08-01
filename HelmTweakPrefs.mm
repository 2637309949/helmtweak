// HelmTweakPrefs — PreferenceBundle for Settings.app
// Settings 根入口。工具箱列表静态定义在 Root.plist（含灰化状态/label），
// 不动态构造或修改 PSSpecifier —— 私有 API 在 iOS 15+ 触发 forwarding 崩溃
// （2026-08-01 两次 Settings 闪退已证实）。如需按系统版本动态灰化，
// 用 plist 静态 isEnabled + 固定 label 标注（当前目标设备均满足 minIOS）。

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
