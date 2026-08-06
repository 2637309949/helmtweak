#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "MCPServer.h"
#import "MCPLogger.h"
#import "SSHManager.h"
#import "IOSMCPPreferences.h"

#define IOS_MCP_LOG(fmt, ...) do { \
    if ([MCPLogger isDebugLoggingEnabled]) { \
        NSString *message = [NSString stringWithFormat:(fmt), ##__VA_ARGS__]; \
        NSLog(@"[witchan][ios-mcp] %@", message); \
        [MCPLogger logMessage:message]; \
    } \
} while (0)

static BOOL ios_mcp_enabled_preference(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)IOS_MCP_ENABLED_PREFERENCE_KEY,
                                                        (__bridge CFStringRef)IOS_MCP_PREFERENCES_DOMAIN);
    if (!value) {
        return NO;
    }

    BOOL enabled = NO;
    CFTypeID typeID = CFGetTypeID(value);
    if (typeID == CFBooleanGetTypeID()) {
        enabled = CFBooleanGetValue((CFBooleanRef)value);
    } else if (typeID == CFNumberGetTypeID()) {
        int numericValue = 0;
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &numericValue);
        enabled = numericValue != 0;
    }

    CFRelease(value);
    return enabled;
}

static void ios_mcp_write_enabled_preference(BOOL enabled) {
    CFPreferencesSetAppValue((__bridge CFStringRef)IOS_MCP_ENABLED_PREFERENCE_KEY,
                             enabled ? kCFBooleanTrue : kCFBooleanFalse,
                             (__bridge CFStringRef)IOS_MCP_PREFERENCES_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)IOS_MCP_PREFERENCES_DOMAIN);
}

static BOOL ios_mcp_is_springboard_process(void) {
    NSString *processName = [[NSProcessInfo processInfo] processName];
    if ([processName isEqualToString:@"SpringBoard"]) {
        return YES;
    }

    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleIdentifier isEqualToString:@"com.apple.springboard"];
}

static uint16_t ios_mcp_start_server(void) {
    uint16_t port = IOSMCPConfiguredPort();
    [[MCPServer sharedInstance] startOnPort:port];
    return port;
}

static void ios_mcp_stop_server(void) {
    [[MCPServer sharedInstance] stop];
}

static NSString *ios_mcp_read_ssh_server_status(void);

static void ios_mcp_write_ssh_status_preference(NSDictionary *status, BOOL preserveIntermediate) {
    NSData *jsonData = nil;
    if ([NSJSONSerialization isValidJSONObject:status]) {
        jsonData = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
    }
    if (jsonData) {
        NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        CFPreferencesSetAppValue(CFSTR("sshStatus"),
                                 (__bridge CFStringRef)(json ?: @"{}"),
                                 CFSTR("com.witchan.ios-mcp.preferences"));
    } else {
        CFPreferencesSetAppValue(CFSTR("sshStatus"),
                                 CFSTR("{}"),
                                 CFSTR("com.witchan.ios-mcp.preferences"));
    }

    // 把实际 launchd autostart 状态写回 sshAutostart，让 Settings 的开关与真实状态一致。
    id autostartValue = status[@"autostart"];
    if (autostartValue) {
        CFPreferencesSetAppValue(CFSTR("sshAutostart"),
                                 [autostartValue boolValue] ? kCFBooleanTrue : kCFBooleanFalse,
                                 CFSTR("com.witchan.ios-mcp.preferences"));
    }

    // SSH 稳定态状态机：uninstalled / installed / running（中间态 installing/starting/stopping
    // 由操作发起时单独写入）。Settings 面板据此决定按钮/开关呈现。
    // 纯状态刷新（preserveIntermediate=YES）时若正处于中间态（操作进行中），保留中间态不覆盖。
    if (preserveIntermediate) {
        NSString *current = ios_mcp_read_ssh_server_status();
        if ([current isEqualToString:@"installing"] ||
            [current isEqualToString:@"starting"] ||
            [current isEqualToString:@"stopping"]) {
            CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS_UPDATED,
                                                NULL, NULL, true);
            return;
        }
    }
    NSString *sshState = @"uninstalled";
    if ([status[@"server_installed"] boolValue]) {
        sshState = [status[@"running"] boolValue] ? @"running" : @"installed";
    }
    CFPreferencesSetAppValue(CFSTR("sshServerStatus"),
                             (__bridge CFStringRef)sshState,
                             CFSTR("com.witchan.ios-mcp.preferences"));

    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS_UPDATED,
                                        NULL, NULL, true);
}

static NSString *ios_mcp_read_ssh_server_status(void) {
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("sshServerStatus"),
                                                     CFSTR("com.witchan.ios-mcp.preferences"));
    NSString *state = nil;
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
        state = [(__bridge NSString *)v copy];
    }
    if (v) CFRelease(v);
    return state ?: @"";
}

static void ios_mcp_handle_ssh_control(CFStringRef name) {
    SSHManager *ssh = [SSHManager sharedInstance];
    NSString *error = nil;
    NSDictionary *result = nil;

    if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_SSH_START)) {
        result = [ssh startSSH:&error];
    } else if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_SSH_STOP)) {
        result = [ssh stopSSH:&error];
    } else if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_SSH_INSTALL)) {
        result = [ssh installSSH:&error];
    } else if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_SSH_AUTOSTART)) {
        // Settings 先把目标值写进 sshAutostart 再发事件。
        CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
        CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("sshAutostart"),
                                                         CFSTR("com.witchan.ios-mcp.preferences"));
        BOOL autostart = NO;
        if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) {
            autostart = CFBooleanGetValue((CFBooleanRef)v);
        }
        if (v) CFRelease(v);
        result = [ssh setAutostart:autostart error:&error];
    } else {
        result = nil;
        error = @"未知 SSH 控制事件";
    }

    if (result == nil && error.length == 0) {
        error = @"未知错误";
    }

    // 关键：只把真实失败记进 sshLastError。成功操作（如 "sshd stopped"）是正常结果，
    // 不应被 Settings 面板当作失败提示显示在开关上。
    BOOL failed = (result == nil);
    CFPreferencesSetAppValue(CFSTR("sshLastError"),
                             (__bridge CFStringRef)(failed ? (error ?: @"操作失败") : @""),
                             CFSTR("com.witchan.ios-mcp.preferences"));
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));

    IOS_MCP_LOG(@"SSH control ok=%d result=%@", failed ? 0 : 1, failed ? error : [result[@"message"] description]);
}

static void ios_mcp_handle_control_notification(CFNotificationCenterRef center,
                                                void *observer,
                                                CFStringRef name,
                                                const void *object,
                                                CFDictionaryRef userInfo) {
    if (!name) {
        return;
    }

    MCPServer *server = [MCPServer sharedInstance];

    if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_START)) {
        ios_mcp_write_enabled_preference(YES);
        if (server.isRunning) {
            // 已启动：直接回执，让 Settings 立即更新。
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                IOS_MCP_DARWIN_NOTIFICATION_STARTED,
                                                NULL, NULL, true);
            IOS_MCP_LOG(@"Received start request but server already running; posted started");
            return;
        }
        uint16_t port = ios_mcp_start_server();
        if (!server.isRunning) {
            // 启动失败（如端口占用）：回写 enabled=NO + 发 STOPPED，让 Settings 开关归位。
            ios_mcp_write_enabled_preference(NO);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                IOS_MCP_DARWIN_NOTIFICATION_STOPPED,
                                                NULL, NULL, true);
            IOS_MCP_LOG(@"Start request FAILED (port %u busy); posted stopped", (unsigned int)port);
            return;
        }
        IOS_MCP_LOG(@"Received start request from Settings on port %u", (unsigned int)port);
        return;
    }

    if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_STOP)) {
        ios_mcp_write_enabled_preference(NO);
        if (!server.isRunning) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                IOS_MCP_DARWIN_NOTIFICATION_STOPPED,
                                                NULL, NULL, true);
            IOS_MCP_LOG(@"Received stop request but server not running; posted stopped");
            return;
        }
        ios_mcp_stop_server();
        IOS_MCP_LOG(@"Received stop request from Settings");
        return;
    }

    if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_CHECK)) {
        // Settings 请求当前状态：写 serverStatus + 按实际运行状态回执。
        CFPreferencesSetAppValue(CFSTR("serverStatus"),
                                 server.isRunning ? CFSTR("started") : CFSTR("stopped"),
                                 CFSTR("com.witchan.ios-mcp.preferences"));
        CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
        CFStringRef ack = server.isRunning ? IOS_MCP_DARWIN_NOTIFICATION_STARTED
                                           : IOS_MCP_DARWIN_NOTIFICATION_STOPPED;
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                            ack, NULL, NULL, true);
        IOS_MCP_LOG(@"Received check request; server running=%d", server.isRunning ? 1 : 0);
    }

    if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS) ||
        CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_SSH_START) ||
        CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_SSH_STOP) ||
        CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_SSH_INSTALL) ||
        CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_SSH_AUTOSTART)) {
        // SSH 操作（尤其 apt-get install）可能耗时数十秒，后台执行避免卡住 SpringBoard 主线程。
        NSString *sshEvent = [(__bridge NSString *)name copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            // 中间态：操作发起时先写 installing/starting/stopping，让 Settings 立即转圈。
            NSString *intermediate = nil;
            if ([sshEvent isEqualToString:(__bridge NSString *)IOS_MCP_DARWIN_NOTIFICATION_SSH_INSTALL]) {
                intermediate = @"installing";
            } else if ([sshEvent isEqualToString:(__bridge NSString *)IOS_MCP_DARWIN_NOTIFICATION_SSH_START]) {
                intermediate = @"starting";
            } else if ([sshEvent isEqualToString:(__bridge NSString *)IOS_MCP_DARWIN_NOTIFICATION_SSH_STOP]) {
                intermediate = @"stopping";
            }
            if (intermediate.length) {
                CFPreferencesSetAppValue(CFSTR("sshServerStatus"),
                                         (__bridge CFStringRef)intermediate,
                                         CFSTR("com.witchan.ios-mcp.preferences"));
                CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                    IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS_UPDATED,
                                                    NULL, NULL, true);
            }

            NSString *lastError = nil;
            if (![sshEvent isEqualToString:(__bridge NSString *)IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS]) {
                ios_mcp_handle_ssh_control((__bridge CFStringRef)sshEvent);
                CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
                CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("sshLastError"),
                                                                 CFSTR("com.witchan.ios-mcp.preferences"));
                if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
                    NSString *val = (__bridge NSString *)v;
                    if (val.length) {
                        lastError = val;
                    }
                }
                if (v) CFRelease(v);
            }
            // 纯状态刷新请求（无操作）或操作完成后写一份最新 status 回执给 Settings。
            // 只有纯状态刷新且当前处于中间态时保留中间态；操作完成的都覆盖为稳定态。
            BOOL preserveIntermediate = [sshEvent isEqualToString:(__bridge NSString *)IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS];
            SSHManager *ssh = [SSHManager sharedInstance];
            NSString *statusError = nil;
            NSDictionary *status = [ssh getStatus:&statusError];
            NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:status ?: @{}];
            if (lastError.length) {
                merged[@"last_error"] = lastError;
            }
            ios_mcp_write_ssh_status_preference(merged, preserveIntermediate);
        });
        return;
    }
}

static void ios_mcp_autostart_if_needed(NSString *reason) {
    if (!ios_mcp_is_springboard_process()) {
        return;
    }

    if (!ios_mcp_enabled_preference()) {
        IOS_MCP_LOG(@"Auto-start skipped (%@): disabled in Settings", reason ?: @"unknown");
        return;
    }

    MCPServer *server = [MCPServer sharedInstance];
    if (server.isRunning) {
        IOS_MCP_LOG(@"Auto-start skipped (%@): already running on port %d",
                    reason ?: @"unknown",
                    server.port);
        return;
    }

    uint16_t port = IOSMCPConfiguredPort();
    IOS_MCP_LOG(@"Auto-start attempt (%@) on port %u...",
                reason ?: @"unknown",
                (unsigned int)port);
    [[MCPServer sharedInstance] startOnPort:port];

    if (!server.isRunning) {
        IOS_MCP_LOG(@"Auto-start attempt (%@) did not start server; later retry may recover",
                    reason ?: @"unknown");
    }
}

static void ios_mcp_schedule_autostart_attempt(NSString *reason, NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * (NSTimeInterval)NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        ios_mcp_autostart_if_needed(reason);
    });
}

static void ios_mcp_schedule_bootstrap_autostart(NSString *reason) {
    if (!ios_mcp_is_springboard_process()) {
        return;
    }

    /*
     Do not rely only on -[SpringBoard applicationDidFinishLaunching:].
     On some jailbreak/iOS combinations after sbreload the tweak can be loaded
     before the hook-driven launch callback is useful, and the first UI action
     (for example Home) becomes the accidental trigger.  Schedule several
     idempotent attempts from the constructor/runloop/lifecycle path so the
     socket is brought up as soon as the new SpringBoard is alive.
     */
    const NSTimeInterval delays[] = {0.2, 1.0, 2.0, 5.0, 10.0, 20.0};
    const size_t count = sizeof(delays) / sizeof(delays[0]);
    for (size_t i = 0; i < count; i++) {
        NSString *attemptReason = [NSString stringWithFormat:@"%@#%zu", reason ?: @"bootstrap", i + 1];
        ios_mcp_schedule_autostart_attempt(attemptReason, delays[i]);
    }
}

static void ios_mcp_register_lifecycle_notifications(void) {
    if (!ios_mcp_is_springboard_process()) {
        return;
    }

    static BOOL registered = NO;
    if (registered) {
        return;
    }
    registered = YES;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {
        IOS_MCP_LOG(@"UIApplicationDidFinishLaunchingNotification observed");
        ios_mcp_schedule_bootstrap_autostart(@"UIApplicationDidFinishLaunching");
    }];

    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *notification) {
        IOS_MCP_LOG(@"UIApplicationDidBecomeActiveNotification observed");
        ios_mcp_schedule_autostart_attempt(@"UIApplicationDidBecomeActive", 0.1);
    }];
}

static void ios_mcp_register_control_notifications(void) {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    ios_mcp_handle_control_notification,
                                    IOS_MCP_DARWIN_NOTIFICATION_START,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    ios_mcp_handle_control_notification,
                                    IOS_MCP_DARWIN_NOTIFICATION_STOP,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    ios_mcp_handle_control_notification,
                                    IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    ios_mcp_handle_control_notification,
                                    IOS_MCP_DARWIN_NOTIFICATION_SSH_START,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    ios_mcp_handle_control_notification,
                                    IOS_MCP_DARWIN_NOTIFICATION_SSH_STOP,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    ios_mcp_handle_control_notification,
                                    IOS_MCP_DARWIN_NOTIFICATION_SSH_INSTALL,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    NULL,
                                    ios_mcp_handle_control_notification,
                                    IOS_MCP_DARWIN_NOTIFICATION_SSH_AUTOSTART,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

// Log immediately when dylib is loaded into process
__attribute__((constructor)) static void ios_mcp_init(void) {
    IOS_MCP_LOG(@"dylib loaded into process: %@", [[NSProcessInfo processInfo] processName]);
    ios_mcp_register_control_notifications();

    if (ios_mcp_is_springboard_process()) {
        ios_mcp_register_lifecycle_notifications();
        /*
         SpringBoard 重启（可能极端被杀重启）：先重置 serverStatus=stopped，
         避免停在假的 started。若 enabled=true 再走 autostart 重新启动。
         */
        CFPreferencesSetAppValue(CFSTR("serverStatus"), CFSTR("stopped"),
                                 CFSTR("com.witchan.ios-mcp.preferences"));
        CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
        /*
         Start once directly from the constructor as well.  The delayed
         dispatch_after retries are still kept as a safety net, but on some
         rootful/Substitute iOS 14 devices SpringBoard may not deliver the
         lifecycle notifications until after the first Home interaction.  A
         synchronous constructor start keeps the MCP socket available
         immediately after sbreload/respring.
         */
        ios_mcp_autostart_if_needed(@"constructor-immediate");
        ios_mcp_schedule_bootstrap_autostart(@"constructor");
    }
}

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;

    IOS_MCP_LOG(@"SpringBoard applicationDidFinishLaunching fired");

    ios_mcp_schedule_bootstrap_autostart(@"SpringBoard.applicationDidFinishLaunching");
}

%end
