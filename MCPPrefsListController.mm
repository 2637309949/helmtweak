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
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <net/if.h>

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

- (BOOL)probeAddress:(NSString *)ip port:(uint16_t)port {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;

    struct timeval tv;
    tv.tv_sec = 0;
    tv.tv_usec = 400 * 1000;
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, ip.UTF8String, &addr.sin_addr);

    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    close(fd);
    return rc == 0;
}

// 取设备当前局域网 IPv4 地址（Settings 进程内获取，用于兜底 probe）。
- (NSString *)currentLANIPv4Address {
    struct ifaddrs *interfaces = NULL;
    NSString *address = nil;
    if (getifaddrs(&interfaces) == 0) {
        for (struct ifaddrs *ifa = interfaces; ifa; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
            if (!(ifa->ifa_flags & IFF_UP) || (ifa->ifa_flags & IFF_LOOPBACK)) continue;
            char buf[INET_ADDRSTRLEN];
            struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
            if (!inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf))) continue;
            NSString *iface = ifa->ifa_name ? [NSString stringWithUTF8String:ifa->ifa_name] : @"";
            if ([iface isEqualToString:@"en0"]) {
                address = [NSString stringWithUTF8String:buf];
                break;
            }
            if (!address) address = [NSString stringWithUTF8String:buf];
        }
    }
    if (interfaces) freeifaddrs(interfaces);
    return address;
}

- (BOOL)probeMCPServerOnPort:(uint16_t)port {
    // 先试 loopback，再试局域网 IP（Settings 沙箱可能拦 loopback，但允许局域网连接）。
    if ([self probeAddress:@"127.0.0.1" port:port]) return YES;
    NSString *lanIP = [self currentLANIPv4Address];
    if (lanIP.length > 0 && [self probeAddress:lanIP port:port]) return YES;
    return NO;
}

- (void)writeEnabledPref:(BOOL)on {
    CFPreferencesSetAppValue(CFSTR("enabled"),
                              on ? kCFBooleanTrue : kCFBooleanFalse,
                              CFSTR("com.witchan.ios-mcp.preferences"));
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
}

// 读服务端写的状态机（starting/started/stopping/stopped）。
- (NSString *)serverStatusString {
    NSString *status = @"stopped";
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("serverStatus"),
                                                     CFSTR("com.witchan.ios-mcp.preferences"));
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
        status = (__bridge NSString *)v;
        CFRelease(v);
    }
    return status;
}

// 心跳判断：server 每 1s 写 serverHeartbeat 时间戳，>3s 未更新 = 死。
// 这是最可靠的真实存活判断（Settings 沙箱连 127.0.0.1 不可靠）。
- (BOOL)serverRunningByHeartbeat {
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("serverHeartbeat"),
                                                     CFSTR("com.witchan.ios-mcp.preferences"));
    if (!v) return NO;
    double ts = 0;
    if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        CFNumberGetValue((CFNumberRef)v, kCFNumberDoubleType, &ts);
    } else if (CFGetTypeID(v) == CFStringGetTypeID()) {
        ts = [(__bridge NSString *)v doubleValue];
    }
    CFRelease(v);
    if (ts <= 0) return NO;
    return (CFAbsoluteTimeGetCurrent() - ts) <= 3.0;
}

// 综合判断真实运行状态：status=started 且心跳新鲜 = 在跑。
- (BOOL)serverRunningByStatus {
    NSString *status = [self serverStatusString];
    if ([status isEqualToString:@"started"]) {
        return [self serverRunningByHeartbeat];
    }
    return NO;
}

// 给 mcpToggleButton 的 cell 加/去转圈 spinner（模拟系统开关等待态）。
- (void)setButtonLoading:(BOOL)loading {
    UITableView *table = [self valueForKey:@"table"];
    if (!table) return;
    for (UITableViewCell *cell in [table visibleCells]) {
        if (![cell.textLabel.text isEqualToString:@"启动中..."] &&
            ![cell.textLabel.text isEqualToString:@"关闭中..."]) {
            continue;
        }
        if (loading) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        } else {
            cell.accessoryView = nil;
        }
    }
}

- (void)refreshServerStatus {
    PSSpecifier *buttonSpec = [self specifierForID:@"mcpToggleButton"];
    if (buttonSpec) {
        [buttonSpec setName:@"检测中..."];
        [self reload];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        // 真实状态：状态机+心跳为准，probe 通了再覆盖为 YES。
        BOOL isUp = [self serverRunningByStatus];
        BOOL probeUp = [self probeMCPServerOnPort:[self configuredPort]];
        if (probeUp) isUp = YES;   // probe 通了必为运行中
        // probe 失败不影响状态机判断

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.serverRunning = isUp;
            [self setButtonLoading:NO];
            PSSpecifier *s = [self specifierForID:@"mcpToggleButton"];
            if (s) {
                [s setName:isUp ? @"关闭服务" : @"启动服务"];
                [self reload];
            }
        });
    });
}

- (void)toggleServer:(PSSpecifier *)spec {
    // 期望方向由点击时按钮 label 决定：
    //   "启动服务" -> 期望启动；"关闭服务" -> 期望关闭。
    // 点击后先"检测中..."，探测实际状态，与期望方向对齐后再操作，避免
    // 界面不同步时盲目重复启动/停止。
    NSString *currentName = [spec name];
    BOOL wantStart = YES;
    if ([currentName isEqualToString:@"关闭服务"]) {
        wantStart = NO;
    } else if ([currentName isEqualToString:@"检测中..."] ||
               [currentName isEqualToString:@"启动中..."] ||
               [currentName isEqualToString:@"关闭中..."]) {
        // 处于过渡态时以最后已知状态取反作为期望
        wantStart = !self.serverRunning;
    }

    [spec setName:@"检测中..."];
    [self reload];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        BOOL isUp = [self serverRunningByStatus];
        if ([self probeMCPServerOnPort:[self configuredPort]]) isUp = YES;

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;

            if (isUp == wantStart) {
                // 实际状态已符合期望方向，无需操作，只纠正 label。
                self.serverRunning = isUp;
                [self writeEnabledPref:isUp];
                PSSpecifier *s = [self specifierForID:@"mcpToggleButton"];
                if (s) {
                    [s setName:isUp ? @"关闭服务" : @"启动服务"];
                    [self reload];
                }
                return;
            }

            // 状态不符合期望，发对应通知。
            [self writeEnabledPref:wantStart];
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                wantStart ? CFSTR("com.witchan.ios-mcp.control/start")
                                                          : CFSTR("com.witchan.ios-mcp.control/stop"),
                                                NULL, NULL, true);

            PSSpecifier *s = [self specifierForID:@"mcpToggleButton"];
            if (s) {
                [s setName:wantStart ? @"启动中..." : @"关闭中..."];
                [self reload];
            }

            // reload 完成后给 cell 加 spinner（模拟系统开关等待态）
            __weak typeof(self) weakSpin = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong typeof(weakSpin) self = weakSpin;
                if (self) [self setButtonLoading:YES];
            });

            // 等 1.5s 让 dylib 起/停 server，再 probe 实际状态刷新 label
            __weak typeof(self) weakSelf2 = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf2) self = weakSelf2;
                if (self) {
                    [self setButtonLoading:NO];
                    [self refreshServerStatus];
                }
            });
        });
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
