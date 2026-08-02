// MCPPrefsListController — MCP 工具子面板
//
// 蓝牙式开关：PSSwitchCell 绑定 enabled pref。
//   - 用户拨动开关 -> Preferences 框架调 setPreferenceValue:specifier:（iOS 15+ action: 不触发，走这里）
//   - 这里转发 START/STOP darwin 事件给 MCP，立即挂转圈（模拟系统开关等待态）
//   - MCP 完成 -> 回 STARTED/STOPPED 事件 -> 恢复开关真实状态（转圈停）
//   - 3s 无回执 -> 发 CHECK 事件让 MCP 传回最新状态（应对启动中被打断）
//   - 进面板时读 serverStatus，中间态则发 CHECK
//
// 开关位置转圈：loading 时把 cell 的 accessoryView（UISwitch）换成 spinner，
// 完成时换回 UISwitch 并按 enabled pref 恢复 on 值。

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
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) NSTimer *logTimer;
@property (nonatomic, strong) PSSpecifier *logViewerSpec;
@property (nonatomic, assign) BOOL logViewerInstalled;
@end

@implementation MCPPrefsListController

// 端口 cell 文本右对齐（PSEditTextCell 默认不保证右侧）+ 日志 cell 多行小字。
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [self specifierForID:@"logViewerCell"];
    NSUInteger logIdx = NSNotFound;
    if (spec) {
        logIdx = [[self specifiers] indexOfObject:spec];
    }
    if ([cell.textLabel.text isEqualToString:@"端口"]) {
        for (UIView *sub in cell.contentView.subviews) {
            if ([sub isKindOfClass:[UITextField class]]) {
                ((UITextField *)sub).textAlignment = NSTextAlignmentRight;
            }
        }
    }
    if (logIdx != NSNotFound && indexPath.section == 0 && (NSInteger)logIdx == indexPath.row) {
        cell.textLabel.font = [UIFont systemFontOfSize:11.0];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.lineBreakMode = NSLineBreakByCharWrapping;
    }
    return cell;
}

// 日志 cell 给足够高度容纳 5 行。单 section，row 即 specifiers 索引。
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierForID:@"logViewerCell"];
    if (spec) {
        NSUInteger idx = [[self specifiers] indexOfObject:spec];
        if (idx != NSNotFound && indexPath.section == 0 && (NSInteger)idx == indexPath.row) {
            return 120.0;
        }
    }
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

// 验证用：NSLog 进 unified log 手机上读不到，写文件。
- (void)logPrefs:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *path = @"/var/mobile/helmtweak_prefs.log";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

// 用户拨动开关时，Preferences 框架调这里（iOS 15+ action: 不触发，已验证走这条路）。
// 服务开关 -> 接管启停；启动日志开关 -> 启停日志刷新 timer；其余直接透传。
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
    NSString *name = [spec name];
    BOOL isToggle = [name isEqualToString:@"服务"];
    BOOL isLogging = [name isEqualToString:@"启动日志"];
    if (isToggle) {
        [self logPrefs:@"toggle to %@", value];
        [self handleToggleRequest:[value boolValue]];
    } else if (isLogging) {
        [self stopLogTimer];
        if ([value boolValue]) {
            [self installLogViewer];
            [self startLogTimerIfNeeded];
        } else {
            PSSpecifier *v = [self specifierForID:@"logViewerCell"];
            if (v) {
                [v setName:@"（开启启动日志后这里显示最近 5 条）"];
                [self reload];
            }
        }
    }
    [super setPreferenceValue:value specifier:spec];
}

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
    [self startLogTimerIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self unregisterControlObservers];
    [self stopLogTimer];
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

// 收到 MCP 事件后恢复开关。为保证转圈状态用户可见，
// 若距离拨动不足 1 秒，延迟到满 1 秒再恢复（否则启动太快事件秒回，转圈一闪而过）。
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

// 恢复开关：写 enabled pref（PSSwitchCell 显示以此为准），换回 UISwitch。
- (void)applyButtonForRunning:(BOOL)running {
    self.waitingForStart = NO;
    self.waitingForStop = NO;
    self.serverRunning = running;
    [self writeEnabledPref:running];
    [self setButtonLoading:NO];
    self.toggleSwitch.on = running;
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

// 开关位置转圈：loading 时把 mcpToggleButton 的 cell 的 accessoryView（UISwitch）换成 spinner，
// 完成时换回原 UISwitch（on 值由调用方在 applyButtonForRunning 里设置）。
- (void)setButtonLoading:(BOOL)loading {
    UITableView *table = [self valueForKey:@"table"];
    if (!table) return;
    for (UITableViewCell *cell in [table visibleCells]) {
        if (![cell.textLabel.text isEqualToString:@"服务"]) {
            continue;
        }
        if (loading) {
            if (self.toggleSwitch) {
                // 已有引用，无需重复保存
            } else if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
                self.toggleSwitch = (UISwitch *)cell.accessoryView;
            }
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        } else {
            if (self.toggleSwitch) {
                cell.accessoryView = self.toggleSwitch;
                self.toggleSwitch.on = self.serverRunning;
            }
        }
    }
}

// 开启启动日志时定时刷新日志 cell。用 NSTimer 轮询文件，避免动态构造 specifier。
- (void)startLogTimerIfNeeded {
    BOOL logging = [self debugLoggingEnabled];
    if (!logging) return;
    if (self.logTimer) return;
    [self installLogViewer];
    self.logTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                     target:self
                                                   selector:@selector(refreshLogViewer)
                                                   userInfo:nil
                                                    repeats:YES];
    [self refreshLogViewer];
}

- (void)stopLogTimer {
    [self.logTimer invalidate];
    self.logTimer = nil;
}

- (BOOL)debugLoggingEnabled {
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("debugLoggingEnabled"),
                                                     CFSTR("com.witchan.ios-mcp.preferences"));
    BOOL on = NO;
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) {
        on = CFBooleanGetValue((CFBooleanRef)v);
    }
    if (v) CFRelease(v);
    return on;
}

// 日志 cell 存在与否跟随调试开关：开关开 -> 补上日志 cell；关 -> 移除。
// 用 [self reload] 重建（specifier 列表改动后安全路径）。
- (void)installLogViewer {
    if (self.logViewerInstalled) return;
    self.logViewerInstalled = YES;
    [self refreshLogViewer];
}

// 读 ios-mcp.log 最后 5 行，写入 logViewerCell。每次重新取 spec（reload 会重建对象）。
- (void)refreshLogViewer {
    PSSpecifier *s = [self specifierForID:@"logViewerCell"];
    if (!s) return;
    NSArray *lines = [self lastLogLines:5];
    NSString *text = lines.count ? [lines componentsJoinedByString:@"\n"] : @"（暂无日志）";
    if (![text isEqualToString:[s name]]) {
        [s setName:text];
        [self reload];
    }
}

- (NSArray<NSString *> *)lastLogLines:(NSUInteger)count {
    NSString *path = @"/var/mobile/Library/Logs/iOSMCP/ios-mcp.log";
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content.length) return @[];
    NSArray<NSString *> *all = [content componentsSeparatedByString:@"\n"];
    // 去掉尾部空行，从后往前取
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSInteger i = all.count - 1;
    while (i >= 0 && result.count < count) {
        NSString *line = [all[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length) [result insertObject:line atIndex:0];
        i--;
    }
    return result;
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
    self.toggleSwitch.on = isUp;
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

// 用户拨动开关（经 setPreferenceValue: 转发）：立即进入等待态并转圈，发事件给 MCP。
// MCP 完成后回 STARTED/STOPPED 事件，这里收到即恢复；3s 无回执则发 CHECK。
- (void)handleToggleRequest:(BOOL)wantStart {
    if (self.waitingForStart || self.waitingForStop) {
        return;  // 等待中忽略重复拨动
    }

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

    [self setButtonLoading:YES];
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
    [self refreshLogViewer];
}

@end
