// HelmTweakPrefs — PreferenceBundle for Settings.app
// Settings 根入口，点开显示 hello 分组标题

#import <Preferences/Preferences.h>

@interface HelmTweakPrefsListController : PSListController
@end

@implementation HelmTweakPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"HelmTweakPrefs"];
    }
    return _specifiers;
}

@end
