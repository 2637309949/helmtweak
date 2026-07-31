// MCPPrefsListController — MCP 工具子面板
// 开关改用 PSButtonCell（PSSwitchCell 在 iOS 15+ 不调用 action，1.0.15/1.0.16 已确认）
// PSButtonCell 100% 调 toggleServer: action。
//
// 进面板时探测 :8686/mcp 实际状态：
//   - server 起来了 -> label = "关闭 MCP 服务"，pref enabled = True
//   - server 没起 -> label = "启动 MCP 服务"，pref enabled = False
// 这样重启手机后 autostart 失败的话，进面板会显示 server 实际没起，不会误显示开。

#import <Preferences/Preferences.h>
#import <CoreFoundation/CoreFoundation.h>

@interface PSListController (HelmTweakPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
@end

@interface MCPPrefsListController : PSListController
@property (nonatomic, assign) BOOL serverRunning;
@end

@implementation MCPPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"MCP" target:self];
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshServerStatus];
}

#pragma mark - Port + probe

- (uint16_t)configuredPort {
    uint16_t port = 8686;
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("port"),
                                                     CFSTR("com.witchan.ios-mcp.preferences"));
    if (v) {
        if (CFGetTypeID(v) == CFNumberGetTypeID()) {
            port = (uint16_t)[(__bridge NSNumber *)v unsignedShortValue];
        } else if (CFGetTypeID(v) == CFStringGetTypeID()) {
            port = (uint16_t)[(__bridge NSString *)v integerValue];
        }
        CFRelease(v);
    }
    if (port == 0) port = 8686;
    return port;
}

- (BOOL)probeMCPServerOnPort:(uint16_t)port {
    NSString *urlStr = [NSString stringWithFormat:@"http://127.0.0.1:%u/mcp", (unsigned)port];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    req.HTTPMethod = @"POST";
    [req setTimeoutInterval:1.0];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [@"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}" dataUsingEncoding:NSUTF8StringEncoding];

    __block BOOL isUp = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 1.0;
    cfg.timeoutIntervalForResource = 1.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    [[session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        (void)err;
        if (data && [resp isKindOfClass:[NSHTTPURLResponse class]] && [(NSHTTPURLResponse *)resp statusCode] == 200) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:[NSDictionary class]] && [json[@"jsonrpc"] isEqualToString:@"2.0"]) {
                isUp = YES;
            }
        }
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)));
    [session invalidateAndCancel];
    return isUp;
}

- (void)writeEnabledPref:(BOOL)on {
    CFPreferencesSetAppValue(CFSTR("enabled"),
                              on ? kCFBooleanTrue : kCFBooleanFalse,
                              CFSTR("com.witchan.ios-mcp.preferences"));
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
}

- (void)refreshServerStatus {
    PSSpecifier *spec = [self specifierForID:@"mcpToggleButton"];
    if (spec) {
        [spec setProperty:@"检测中..." forKey:@"label"];
        [self reloadSpecifier:spec animated:NO];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        BOOL isUp = [self probeMCPServerOnPort:[self configuredPort]];

        // 同步 pref 跟实际状态走
        [self writeEnabledPref:isUp];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.serverRunning = isUp;
            PSSpecifier *s = [self specifierForID:@"mcpToggleButton"];
            if (s) {
                [s setProperty:isUp ? @"关闭 MCP 服务" : @"启动 MCP 服务" forKey:@"label"];
                [self reloadSpecifier:s animated:YES];
            }
        });
    });
}

- (void)toggleServer:(PSSpecifier *)spec {
    BOOL shouldStart = !self.serverRunning;
    [self writeEnabledPref:shouldStart];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        shouldStart ? CFSTR("com.witchan.ios-mcp.control/start")
                                                    : CFSTR("com.witchan.ios-mcp.control/stop"),
                                        NULL, NULL, true);

    [spec setProperty:shouldStart ? @"启动中..." : @"关闭中..." forKey:@"label"];
    [self reloadSpecifier:spec animated:YES];

    // 等 1.5s 让 dylib 起/停 server，再 probe 实际状态刷新 label
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self refreshServerStatus];
    });
}

@end
