// MCPPrefsListController — MCP 工具子面板
//
// 事件驱动状态：状态以 MCP 服务为准。
//   - 点击启动/关闭 -> 立即变"启动中/关闭中"不可点，发 darwin 事件给 MCP
//   - MCP 完成 -> 回 STARTED/STOPPED 事件，这里收到即更新按钮
//   - 3s 无回执 -> 发 CHECK 事件让 MCP 传回最新状态（应对启动中被打断）
//   - 进面板时读 serverStatus，中间态则发 CHECK
//
// PSButtonCell title 刷新用 [spec setName:] + [self reload]。
// setProperty:forKey:@"label" + reloadSpecifier:animated: 在 iOS 15+ 不重画 title（1.0.17/1.0.18 已确认）。

#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "IOSMCPPreferences.h"

@interface PSListController (HelmTweakPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reload;
@end

@interface PSSpecifier (HelmTweakPrivate)
- (void)setName:(NSString *)name;
@end

@interface MCPPrefsListController : PSListController
@property (nonatomic, assign) BOOL serverRunning;
@property (nonatomic, assign) BOOL waitingForStart;
@property (nonatomic, assign) BOOL waitingForStop;
@property (nonatomic, assign) CFTimeInterval toggleTimestamp;
@property (nonatomic, assign) BOOL finalizeScheduled;
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
    [self registerControlObservers];
    [self refreshServerStatus];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self unregisterControlObservers];
}

#pragma mark - Darwin event observers

- (void)registerControlObservers {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center,
                                    (__bridge const void *)self,
                                    &MCPServerControlCallback,
                                    IOS_MCP_DARWIN_NOTIFICATION_STARTED,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center,
                                    (__bridge const void *)self,
                                    &MCPServerControlCallback,
                                    IOS_MCP_DARWIN_NOTIFICATION_STOPPED,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)unregisterControlObservers {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterRemoveObserver(center, (__bridge const void *)self,
                                       IOS_MCP_DARWIN_NOTIFICATION_STARTED, NULL);
    CFNotificationCenterRemoveObserver(center, (__bridge const void *)self,
                                       IOS_MCP_DARWIN_NOTIFICATION_STOPPED, NULL);
}

static void MCPServerControlCallback(CFNotificationCenterRef center,
                                     void *observer,
                                     CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
    MCPPrefsListController *controller = (__bridge MCPPrefsListController *)observer;
    if (!name || !controller) return;
    if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_STARTED)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller handleServerEventStarted];
        });
    } else if (CFEqual(name, IOS_MCP_DARWIN_NOTIFICATION_STOPPED)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller handleServerEventStopped];
        });
    }
}

// 收到 MCP 事件后恢复按钮。为保证"启动中/关闭中"中间态用户可见，
// 若距离点击不足 1 秒，延迟到满 1 秒再恢复（否则启动太快事件秒回，中间态一闪而过）。
- (void)handleServerEventStarted {
    [self finishToggleToRunning:YES];
}

- (void)handleServerEventStopped {
    [self finishToggleToRunning:NO];
}

- (void)finishToggleToRunning:(BOOL)running {
    NSTimeInterval elapsed = CACurrentMediaTime() - self.toggleTimestamp;
    if ((self.waitingForStart || self.waitingForStop) && elapsed < 1.0) {
        if (self.finalizeScheduled) return;  // 已有延迟任务在排队，忽略重复事件（如 CHECK 兜底回执）
        self.finalizeScheduled = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1.0 - elapsed) * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.finalizeScheduled = NO;
            [self applyButtonForRunning:running];
        });
        return;
    }
    [self applyButtonForRunning:running];
}

- (void)applyButtonForRunning:(BOOL)running {
    self.waitingForStart = NO;
    self.waitingForStop = NO;
    self.serverRunning = running;
    [self writeEnabledPref:running];
    [self setButtonLoading:NO];
    PSSpecifier *s = [self specifierForID:@"mcpToggleButton"];
    if (s) {
        [s setName:running ? @"关闭服务" : @"启动服务"];
        [self reload];
    }
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

// 综合判断真实运行状态：status=started = 在跑。
// 以 MCP 服务维护的状态为准（Settings 不探测，靠事件+状态变量）。
- (BOOL)serverRunningByStatus {
    NSString *status = [self serverStatusString];
    return [status isEqualToString:@"started"];
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
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        } else {
            cell.accessoryView = nil;
        }
    }
}

- (void)refreshServerStatus {
    // 进面板：读 serverStatus。
    //   中间态（starting/stopping）-> 发 CHECK 等 MCP 回执（事件驱动兜底）
    //   started -> "关闭服务"；stopped -> "启动服务"
    NSString *status = [self serverStatusString];
    BOOL isUp = [self serverRunningByStatus];

    if ([status isEqualToString:@"starting"] || [status isEqualToString:@"stopping"]) {
        // 上次处于中间态（可能被打断），主动 CHECK 让 MCP 传回最新状态。
        self.waitingForStart = NO;
        self.waitingForStop = NO;
        [self setButtonLoading:YES];
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                            IOS_MCP_DARWIN_NOTIFICATION_CHECK,
                                            NULL, NULL, true);
        [self scheduleStatusTimeout];
        return;
    }

    self.serverRunning = isUp;
    [self setButtonLoading:NO];
    PSSpecifier *s = [self specifierForID:@"mcpToggleButton"];
    if (s) {
        [s setName:isUp ? @"关闭服务" : @"启动服务"];
        [self reload];
    }
}

// 3s 兜底定时器：等待事件回执期间超时后，发 CHECK 确认最新状态。
- (void)scheduleStatusTimeout {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        // 若还在等待（事件没回来），发 CHECK 刷新。
        if (self.waitingForStart || self.waitingForStop) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                IOS_MCP_DARWIN_NOTIFICATION_CHECK,
                                                NULL, NULL, true);
        }
    });
}

- (void)toggleServer:(PSSpecifier *)spec {
    // 事件驱动：点击立即进入"启动中/关闭中"并不可点，发事件给 MCP。
    // MCP 完成后回 STARTED/STOPPED 事件，这里收到即更新；3s 无回执则发 CHECK。
    if (self.waitingForStart || self.waitingForStop) {
        return;  // 等待中不可重复点击
    }

    BOOL wantStart = ![self serverRunningByStatus];
    [self writeEnabledPref:wantStart];
    self.toggleTimestamp = CACurrentMediaTime();
    self.finalizeScheduled = NO;

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        wantStart ? IOS_MCP_DARWIN_NOTIFICATION_START
                                                  : IOS_MCP_DARWIN_NOTIFICATION_STOP,
                                        NULL, NULL, true);

    if (wantStart) {
        self.waitingForStart = YES;
        self.waitingForStop = NO;
    } else {
        self.waitingForStart = NO;
        self.waitingForStop = YES;
    }

    PSSpecifier *s = [self specifierForID:@"mcpToggleButton"];
    if (s) {
        [s setName:wantStart ? @"启动中..." : @"关闭中..."];
        [self reload];
    }

    __weak typeof(self) weakSpin = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSpin) self = weakSpin;
        if (self) [self setButtonLoading:YES];
    });

    [self scheduleStatusTimeout];
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
