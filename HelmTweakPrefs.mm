// HelmTweakPrefs — PreferenceBundle for Settings.app
// Settings 根入口，点开显示 hello 分组标题
// 显式从 bundle 加载 Root.plist → PSSpecifier specifiersFromArray:

#import <Preferences/Preferences.h>

@interface PSSpecifier (HelmTweakPrivate)
+ (NSMutableArray *)specifiersFromArray:(NSArray *)array;
@end

@interface HelmTweakPrefsListController : PSListController
@end

@implementation HelmTweakPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSBundle *b = [NSBundle bundleForClass:[self class]];
        NSString *path = [b pathForResource:@"Root" ofType:@"plist"];
        if (path) {
            NSArray *arr = [NSArray arrayWithContentsOfFile:path];
            _specifiers = [PSSpecifier specifiersFromArray:arr];
        }
    }
    return _specifiers;
}

@end
