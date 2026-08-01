// MCPPrefsListController — MCP 工具子面板
//
// 进面板时 probe :8686/mcp 实际状态：
//   - server 起来了 -> label = "关闭服务"，pref enabled = True
//   - server 没起 -> label = "启动服务"，pref enabled = False
// 重启手机后 autostart 失败的话，进面板会显示 server 实际没起，不会误显示开。
//
// PSButtonCell title 刷新用 [spec setName:] + [self reload]。
// setProperty:forKey:@"label" + reloadSpecifier:animated: 在 iOS 15+ 不重画 title（1.0.17/1.0.18 已确认）。

#import <Preferences/Preferences.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>

@interface PSListController (HelmTweakPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
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
    // 用 BSD socket 直接测 TCP 连接，不经过 NSURLSession/ATS。
    // NSURLSession 在 Settings 进程里对 http://127.0.0.1 可能被 ATS 拦，导致误判 server 没起。
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;

    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 500 * 1000;
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    close(fd);
    return rc == 0;
}

- (void)writeEnabledPref:(BOOL)on {
    CFPreferencesSetAppValue(CFSTR("enabled"),
                              on ? kCFBooleanTrue : kCFBooleanFalse,
                              CFSTR("com.witchan.ios-mcp.preferences"));
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
}

- (void)refreshServerStatus {
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
                [s setName:isUp ? @"关闭服务" : @"启动服务"];
                [self reload];
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

    [spec setName:shouldStart ? @"启动中..." : @"关闭中..."];
    [self reload];

    // 等 1.5s 让 dylib 起/停 server，再 probe 实际状态刷新 label
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self) [self refreshServerStatus];
    });
}

- (void)clearLogs:(PSSpecifier *)spec {
    // 清日志文件（不依赖 MCPLogger 类，Settings 进程没有它）。
    // 清 iOSMCP + HelmCore 两个日志目录。
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *dirs = @[
        @"/var/mobile/Library/Logs/iOSMCP",
        @"/var/mobile/Library/Logs/HelmCore",
    ];

    BOOL allCleared = YES;
    NSString *lastError = nil;
    for (NSString *dir in dirs) {
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in files) {
            if (![file hasSuffix:@".log"]) continue;
            NSError *e = nil;
            if (![fm removeItemAtPath:[dir stringByAppendingPathComponent:file] error:&e]) {
                allCleared = NO;
                if (!lastError) lastError = e.localizedDescription;
            }
        }
    }

    NSString *message = allCleared ? @"已清空" : [@"清空失败: " stringByAppendingString:lastError ?: @"未知错误"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空日志"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
