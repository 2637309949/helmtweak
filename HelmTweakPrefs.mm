// HelmTweakPrefs — PreferenceBundle for Settings.app
// Settings 根入口，点开显示 hello 分组标题
// PSListController 的 loadSpecifiersFromPlistName:target: 是 working
// jailbreak tweak 标准模式（参考 Velvet2 RootListController）

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
