// MCPPrefsListController — MCP 工具子面板
// PSSwitchCell 在切换时会先把新值写入 com.witchan.ios-mcp.preferences/enabled，
// 然后调用本类的 setMCPEnabled:，这里 post darwin notification
// 通知 ios-mcp 主 dylib 启动/停止 MCP server。

#import <Preferences/Preferences.h>
#import <CoreFoundation/CoreFoundation.h>

@interface PSListController (HelmTweakPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface MCPPrefsListController : PSListController
@end

@implementation MCPPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"MCP" target:self];
    }
    return _specifiers;
}

- (void)setMCPEnabled:(PSSpecifier *)spec {
    // PSSwitchCell 已把新值写入 com.witchan.ios-mcp.preferences/enabled
    BOOL on = NO;
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("enabled"),
                                                    CFSTR("com.witchan.ios-mcp.preferences"));
    if (v) {
        if (CFGetTypeID(v) == CFBooleanGetTypeID()) {
            on = CFBooleanGetValue((CFBooleanRef)v);
        } else if (CFGetTypeID(v) == CFNumberGetTypeID()) {
            on = [(__bridge NSNumber *)v boolValue];
        }
        CFRelease(v);
    }
    CFStringRef name = on ? CFSTR("com.witchan.ios-mcp.control/start")
                          : CFSTR("com.witchan.ios-mcp.control/stop");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        name, NULL, NULL, true);
}

@end
