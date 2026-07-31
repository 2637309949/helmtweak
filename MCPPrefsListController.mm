// MCPPrefsListController — MCP 工具子面板
// 诊断版：所有关键路径写 /var/mobile/helmtweak_prefs.log 以便远程排查
// 为什么用文件日志：iOS 设备无 `log show` CLI，NSLog 进 unified log 不好取。

#import <Preferences/Preferences.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *HelmPrefsLogPath(void) {
    return @"/var/mobile/helmtweak_prefs.log";
}

static void HelmPrefsLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void HelmPrefsLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"HH:mm:ss.SSS"];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], msg];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = HelmPrefsLogPath();
    if (![fm fileExistsAtPath:path]) {
        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        [h seekToEndOfFile];
        [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    }
}

@interface PSListController (HelmTweakPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
- (void)reload;
@end

@interface PSSpecifier (HelmTweakPrivate)
- (void)setName:(NSString *)name;
@end

@interface MCPPrefsListController : PSListController
@property (nonatomic, assign) BOOL serverRunning;
@end

@implementation MCPPrefsListController

- (NSArray *)specifiers {
    HelmPrefsLog(@"specifiers called");
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"MCP" target:self];
        HelmPrefsLog(@"loaded %lu specifiers", (unsigned long)_specifiers.count);
        for (PSSpecifier *s in _specifiers) {
            HelmPrefsLog(@"  spec id=%@ cell=%@ label=%@ action=%@",
                         s.identifier, [s propertyForKey:@"cell"], [s propertyForKey:@"label"], [s propertyForKey:@"action"]);
        }
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    HelmPrefsLog(@"viewWillAppear called");
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
    HelmPrefsLog(@"refreshServerStatus called");
    PSSpecifier *spec = [self specifierForID:@"mcpToggleButton"];
    HelmPrefsLog(@"  specifierForID mcpToggleButton = %@", spec);
    if (spec) {
        [spec setName:@"检测中..."];
        [self reload];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        BOOL isUp = [self probeMCPServerOnPort:[self configuredPort]];
        HelmPrefsLog(@"  probe isUp=%d", (int)isUp);

        // 同步 pref 跟实际状态走
        [self writeEnabledPref:isUp];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.serverRunning = isUp;
            PSSpecifier *s = [self specifierForID:@"mcpToggleButton"];
            HelmPrefsLog(@"  main-thread specifierForID = %@ name=%@", s, s.name);
            if (s) {
                [s setName:isUp ? @"关闭 MCP 服务" : @"启动 MCP 服务"];
                [self reload];
                HelmPrefsLog(@"  name set to %@, table reloaded", s.name);
            }
        });
    });
}

- (void)toggleServer:(PSSpecifier *)spec {
    HelmPrefsLog(@"toggleServer CALLED spec=%@ serverRunning=%d", spec, (int)self.serverRunning);
    BOOL shouldStart = !self.serverRunning;
    [self writeEnabledPref:shouldStart];
    HelmPrefsLog(@"  posting darwin %@ notification", shouldStart ? @"start" : @"stop");

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        shouldStart ? CFSTR("com.witchan.ios-mcp.control/start")
                                                    : CFSTR("com.witchan.ios-mcp.control/stop"),
                                        NULL, NULL, true);

    [spec setName:shouldStart ? @"启动中..." : @"关闭中..."];
    [self reload];
    HelmPrefsLog(@"  name set to %@, table reloaded", spec.name);

    // 等 1.5s 让 dylib 起/停 server，再 probe 实际状态刷新 label
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self refreshServerStatus];
    });
}

@end
