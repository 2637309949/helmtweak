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
@property (nonatomic, assign) BOOL logViewerInstalled;
@property (nonatomic, strong) UILabel *logTextLabel;
@property (nonatomic, strong) UIButton *logRefreshButton;
@property (nonatomic, strong) UILabel *logTimeLabel;
@property (nonatomic, strong) UIView *logFooterView;
@end

@implementation MCPPrefsListController

// 端口 cell 文本右对齐（PSEditTextCell 默认不保证右侧）。
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([cell.textLabel.text isEqualToString:@"端口"]) {
        for (UIView *sub in cell.contentView.subviews) {
            if ([sub isKindOfClass:[UITextField class]]) {
                ((UITextField *)sub).textAlignment = NSTextAlignmentRight;
            }
        }
    }
    return cell;
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
// 服务开关 -> 接管启停；启动日志开关 -> 开时立即刷新一次日志显示；其余直接透传。
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
    NSString *name = [spec name];
    BOOL isToggle = [name isEqualToString:@"服务"];
    BOOL isLogging = [name isEqualToString:@"启动日志"];
    if (isToggle) {
        [self logPrefs:@"toggle to %@", value];
        [self handleToggleRequest:[value boolValue]];
    } else if (isLogging) {
        // 用拨动目标值直接控制容器显示（此时 pref 还没写盘，不能读）。
        [self showLogFooter:[value boolValue]];
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
    [self updateLogFooter];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self unregisterControlObservers];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutLogFooter];
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
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
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

- (BOOL)debugLoggingEnabled {
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("debugLoggingEnabled"),
                                                     CFSTR("com.witchan.ios-mcp.preferences"));
    BOOL on = NO;
    if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) {
        on = CFBooleanGetValue((CFBooleanRef)v);
    }
    if (v) CFRelease(v);
    return on;
}

// 日志 footer 只在「启动日志」开关打开时挂到 table 底部。
- (void)updateLogFooter {
    [self showLogFooter:[self debugLoggingEnabled]];
}

- (void)showLogFooter:(BOOL)show {
    UITableView *table = [self valueForKey:@"table"];
    if (!table) return;
    if (show) {
        if (!self.logFooterView) {
            [self buildLogFooterWithTable:table];
        }
        table.tableFooterView = self.logFooterView;
        [self layoutLogFooter];
        [self refreshLogViewer];
    } else {
        table.tableFooterView = nil;
    }
}

// 构建日志 footer：只创建控件，frame 统一在 layoutLogFooter 里按当前真实宽度计算。
- (void)buildLogFooterWithTable:(UITableView *)table {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, 160)];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *time = [[UILabel alloc] initWithFrame:CGRectZero];
    time.font = [UIFont systemFontOfSize:13.0];
    time.textColor = [UIColor secondaryLabelColor];
    time.text = @"";
    [footer addSubview:time];
    self.logTimeLabel = time;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectZero;
    [btn setTitle:@"刷新" forState:UIControlStateNormal];
    [btn.titleLabel setFont:[UIFont systemFontOfSize:13.0]];
    // 文字右对齐，贴按钮右缘：按钮右缘=开关右缘，文字右缘才能与开关右缘对齐
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [btn addTarget:self action:@selector(refreshLogsTapped:) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:btn];
    self.logRefreshButton = btn;

    UILabel *log = [[UILabel alloc] initWithFrame:CGRectZero];
    log.numberOfLines = 8;
    log.lineBreakMode = NSLineBreakByTruncatingTail;
    log.backgroundColor = [UIColor clearColor];
    log.textColor = [UIColor secondaryLabelColor];
    log.font = [UIFont systemFontOfSize:11.0];
    log.text = @"（暂无日志，点右上角刷新）";
    [footer addSubview:log];
    self.logTextLabel = log;

    self.logFooterView = footer;
}

// footer 固定高度：8 条日志 + 顶部行。所有 frame 在此用当前 table 宽度统一计算。
- (void)layoutLogFooter {
    UITableView *table = [self valueForKey:@"table"];
    if (!table || !self.logFooterView) return;

    CGFloat width = table.bounds.size.width;
    CGFloat inset = 16.0;
    CGFloat footerTop = 8.0;       // 距最后一行间距
    CGFloat headerH = 20.0;        // 顶部时间+刷新行高
    CGFloat logH = 120.0;          // 8 行日志高度
    CGFloat btnW = 56.0;

    CGRect f = self.logFooterView.frame;
    f.size.width = width;
    f.size.height = footerTop + headerH + logH;
    self.logFooterView.frame = f;

    // 文本左缘基准：设置项标题在 x=32（16 卡片边距 + 16 文本内边距）。
    // 时间戳与日志区与标题行严格左对齐。
    CGFloat textX = inset + 16;          // 32pt，与"服务/启动日志"文本左缘一致

    // 刷新按钮右缘 = 上面开关行 UISwitch 的真实右缘（与开关右对齐）。
    // 取当前可见的任一 UISwitch accessory 右缘；滚动后看不到开关时退回标准边距。
    CGFloat switchRight = width - inset; // 默认：开关右缘 = 卡片右边距
    for (UITableViewCell *cell in [table visibleCells]) {
        if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
            CGRect accessoryFrame = [table convertRect:cell.accessoryView.frame
                                              fromView:cell.accessoryView.superview];
            switchRight = CGRectGetMaxX(accessoryFrame);
            break;
        }
    }
    CGFloat btnX = switchRight - btnW;   // 刷新按钮右缘 = 开关右缘

    self.logTimeLabel.frame = CGRectMake(textX, footerTop, btnX - textX - 8, headerH);
    // 刷新按钮：右缘与上面开关行的 UISwitch 右缘对齐
    self.logRefreshButton.frame = CGRectMake(btnX, footerTop, btnW, headerH);
    // 日志区：与标题行左对齐
    self.logTextLabel.frame = CGRectMake(textX, footerTop + headerH, width - textX - inset, logH);

    table.tableFooterView = self.logFooterView;
}

// 「刷新」按钮：点击转圈刷新日志。
- (void)refreshLogsTapped:(UIButton *)sender {
    if (self.logViewerInstalled) return;  // 正在刷新
    self.logViewerInstalled = YES;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.frame = sender.bounds;
    [sender addSubview:spinner];
    [sender setTitle:@"" forState:UIControlStateNormal];
    [spinner startAnimating];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self refreshLogViewer];
        self.logViewerInstalled = NO;
        [spinner removeFromSuperview];
        [sender setTitle:@"刷新" forState:UIControlStateNormal];
    });
}

// 读 ios-mcp.log 最近 5 条，倒序（最新在前）写入 textView。
// 仅最新一条保留完整时间戳显示在左上角，其余行去掉时间前缀。
// 仅在当前看板 + 日志开关开时执行。
- (void)refreshLogViewer {
    if (![self debugLoggingEnabled]) return;
    if (!(self.isViewLoaded && self.view.window != nil)) return;  // 不在当前看板不读
    NSArray<NSString *> *lines = [self lastLogLines:5];  // 最新在前
    if (!lines.count) {
        self.logTextLabel.text = @"（暂无日志）";
        self.logTimeLabel.text = @"";
        return;
    }

    NSString *newestTime = [self timestampFromLogLine:lines.firstObject];
    self.logTimeLabel.text = newestTime ?: @"";

    // 每行都去掉时间戳+pid，只留 message（时间统一显示在左上角 label）。
    NSMutableArray<NSString *> *display = [NSMutableArray array];
    for (NSString *line in lines) {
        NSString *clean = [self logLineWithoutTimestamp:line];
        if (clean.length) [display addObject:clean];
    }
    self.logTextLabel.text = display.count ? [display componentsJoinedByString:@"\n"] : @"（暂无日志）";
}

// 从日志行头部提取时间戳，如 "2026-08-02 13:42:00 +0000"。
- (NSString *)timestampFromLogLine:(NSString *)line {
    // MCPLogger 格式: "%Y-%m-%d %H:%M:%S%z pid=... " —— 前 19 字符是时间，随后是 +0800 时区
    if (line.length < 19) return nil;
    NSString *head = [line substringToIndex:19];
    // 简单校验是数字-数字格式
    if ([head characterAtIndex:4] == '-' && [head characterAtIndex:7] == '-') {
        return head;
    }
    return nil;
}

// 去掉行首时间戳和 pid= 前缀，只留 message。日志格式: "YYYY-MM-DD HH:MM:SS.mmm+0800 pid=36211 message"
- (NSString *)logLineWithoutTimestamp:(NSString *)line {
    // 找 pid= 位置
    NSRange pidRange = [line rangeOfString:@"pid="];
    if (pidRange.location != NSNotFound) {
        NSUInteger msgPos = pidRange.location + pidRange.length;
        // 跳过 pid 数字
        while (msgPos < line.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[line characterAtIndex:msgPos]]) msgPos++;
        // 跳过空格
        while (msgPos < line.length && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:msgPos]]) msgPos++;
        if (msgPos < line.length) {
            return [line substringFromIndex:msgPos];
        }
    }
    // 没有 pid=（异常行），退回只去时间戳
    NSString *ts = [self timestampFromLogLine:line];
    if (!ts) return line;
    NSUInteger pos = ts.length;
    while (pos < line.length && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:pos]]) pos++;
    if (pos + 5 <= line.length) {
        unichar c = [line characterAtIndex:pos];
        if (c == '+' || c == '-') pos += 6;
    }
    while (pos < line.length && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:pos]]) pos++;
    return [line substringFromIndex:pos];
}

- (NSArray<NSString *> *)lastLogLines:(NSUInteger)count {
    // rootless 下真实路径是 /private/var/...，/var 是符号链接可能解析失败，两个都试。
    NSArray<NSString *> *paths = @[
        @"/private/var/mobile/Library/Logs/iOSMCP/ios-mcp.log",
        @"/var/mobile/Library/Logs/iOSMCP/ios-mcp.log",
    ];
    NSString *content = @"";
    for (NSString *path in paths) {
        content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (content.length) break;
    }
    if (!content.length) return @[];
    NSArray<NSString *> *all = [content componentsSeparatedByString:@"\n"];
    // 从后往前取，最新在最前
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSInteger i = all.count - 1;
    while (i >= 0 && result.count < count) {
        NSString *line = [all[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length) [result addObject:line];
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
    // 清空后显示"已清空"，不自动重读（server 还在写，重读会有新日志）。
    if (self.logTextLabel) {
        self.logTextLabel.text = @"已清空";
        self.logTimeLabel.text = @"";
    }
}

@end
