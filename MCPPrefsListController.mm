// MCPPrefsListController — MCP 工具子面板
// PSSwitchCell 在切换时会先把新值写入 com.witchan.ios-mcp.preferences/enabled，
// 然后调用 auto-derive 出来的 setEnabled:（命名必须匹配 key=enabled）。
// 这里 post darwin notification 通知 HelmMCP dylib 启动/停止 MCP server。

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

// PSSwitchCell auto-derives set<Key>: from key=enabled.
// Method name MUST be setEnabled: for the cell to call it.
- (void)setEnabled:(PSSpecifier *)spec {
    // PSSwitchCell has just written the new value to com.witchan.ios-mcp.preferences/enabled
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

    // DIAGNOSTIC (1.0.16): record that this action ran + what value it read
    NSDictionary *marker = @{
        @"lastActionAt": [[NSDate date] description],
        @"lastActionReadsEnabled": @(on),
    };
    CFPreferencesSetAppValue(CFSTR("actionMarker"),
                             (__bridge CFPropertyListRef)marker,
                             CFSTR("com.witchan.ios-mcp.preferences"));
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));

    CFStringRef name = on ? CFSTR("com.witchan.ios-mcp.control/start")
                          : CFSTR("com.witchan.ios-mcp.control/stop");
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        name, NULL, NULL, true);
}

@end
