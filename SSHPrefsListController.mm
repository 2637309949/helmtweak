// SSHPrefsListController — SSH 工具子面板
//
// 状态来源：MCP server（SpringBoard 内 SSHManager）把最新状态写成 JSON pref `sshStatus`，
// 再广播 `ssh-status-updated`。本面板：
//   - 进面板/收到更新 -> 读 sshStatus -> 更新「状态」按钮文字 + 「启动/停止」按钮文字
//   - 点按钮 -> 发 darwin 事件（start/stop/install/autostart）给 MCP，MCP 执行后回写状态
//   - 开机自启 PSSwitchCell 绑定 sshAutostart pref，setPreferenceValue: 拦截后发 autostart 事件
//
// 与 MCP 面板同样的硬约束：不动态构造 PSSpecifier；只 [spec setName:]+[self reload] 改文字。

#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "IOSMCPPreferences.h"

@interface PSListController (HelmSSHPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reload;
@end

@interface PSSpecifier (HelmSSHPrivate)
- (void)setName:(NSString *)name;
@end

@interface SSHPrefsListController : PSListController
@property (nonatomic, strong) NSDictionary *sshStatus;
@property (nonatomic, strong) PSSpecifier *statusSpec;
@property (nonatomic, strong) PSSpecifier *toggleSpec;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong) UILabel *logTextLabel;
@property (nonatomic, strong) UIButton *logRefreshButton;
@property (nonatomic, strong) UILabel *logTimeLabel;
@property (nonatomic, strong) UIView *logFooterView;
@property (nonatomic, assign) BOOL logViewerInstalled;
@end

@implementation SSHPrefsListController

- (void)logPrefs:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *path = @"/var/mobile/helmtweak_ssh_prefs.log";
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[msg dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"SSH" target:self];
        for (PSSpecifier *spec in _specifiers) {
            if ([[spec name] isEqualToString:@"状态：加载中"]) {
                self.statusSpec = spec;
            } else if ([[spec name] isEqualToString:@"启动 SSH"]) {
                self.toggleSpec = spec;
            }
        }
    }
    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self registerObservers];
    [self requestStatusRefresh];
    [self updateLogFooter];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self unregisterObservers];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutSSHLogFooter];
}

#pragma mark - Darwin observers

- (void)registerObservers {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center,
                                    (__bridge const void *)self,
                                    &SSHPrefsControlCallback,
                                    IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS_UPDATED,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)unregisterObservers {
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterRemoveObserver(center, (__bridge const void *)self,
                                       IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS_UPDATED, NULL);
}

static void SSHPrefsControlCallback(CFNotificationCenterRef center,
                                    void *observer,
                                    CFStringRef name,
                                    const void *object,
                                    CFDictionaryRef userInfo) {
    SSHPrefsListController *controller = (__bridge SSHPrefsListController *)observer;
    if (!controller) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [controller refreshFromStatusPref];
        [controller refreshLogViewer];
    });
}

#pragma mark - Status

- (void)requestStatusRefresh {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS,
                                        NULL, NULL, true);
}

// 读 sshStatus JSON pref 更新按钮文字。
- (void)refreshFromStatusPref {
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("sshStatus"),
                                                     CFSTR("com.witchan.ios-mcp.preferences"));
    NSString *json = nil;
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
        json = (__bridge NSString *)v;
    }
    if (v) CFRelease(v);

    NSDictionary *status = nil;
    if (json.length) {
        NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([obj isKindOfClass:[NSDictionary class]]) {
            status = obj;
        }
    }
    self.sshStatus = status ?: @{};

    BOOL installed = [self.sshStatus[@"server_installed"] boolValue];
    BOOL running = [self.sshStatus[@"running"] boolValue];
    BOOL autostart = [self.sshStatus[@"autostart"] boolValue];
    BOOL rootAvail = [self.sshStatus[@"root_available"] boolValue];
    NSString *scheme = self.sshStatus[@"scheme"] ?: @"?";

    NSString *statusText;
    if (!installed) {
        statusText = @"状态：未安装 openssh-server";
    } else if (running) {
        statusText = @"状态：运行中 (端口 22)";
    } else {
        statusText = @"状态：已安装，未运行";
    }
    if (self.sshStatus[@"last_error"]) {
        statusText = [NSString stringWithFormat:@"%@｜%@", statusText, self.sshStatus[@"last_error"]];
    }

    NSString *toggleText;
    if (!installed) {
        toggleText = @"安装 OpenSSH";
    } else if (running) {
        toggleText = @"停止 SSH";
    } else {
        toggleText = @"启动 SSH";
    }
    if (!rootAvail) {
        toggleText = [NSString stringWithFormat:@"%@（无 root）", toggleText];
    }

    [self.statusSpec setName:statusText];
    [self.toggleSpec setName:toggleText];
    [self reload];

    [self logPrefs:@"refresh status installed=%d running=%d autostart=%d root=%d scheme=%@",
            installed ? 1 : 0, running ? 1 : 0, autostart ? 1 : 0, rootAvail ? 1 : 0, scheme];
}

#pragma mark - Actions

- (void)refreshSSHStatus:(PSSpecifier *)spec {
    [self requestStatusRefresh];
}

- (void)toggleSSH:(PSSpecifier *)spec {
    if (self.busy) return;
    self.busy = YES;

    BOOL installed = [self.sshStatus[@"server_installed"] boolValue];
    BOOL running = [self.sshStatus[@"running"] boolValue];

    CFStringRef event = nil;
    if (!installed) {
        event = IOS_MCP_DARWIN_NOTIFICATION_SSH_INSTALL;
    } else if (running) {
        event = IOS_MCP_DARWIN_NOTIFICATION_SSH_STOP;
    } else {
        event = IOS_MCP_DARWIN_NOTIFICATION_SSH_START;
    }

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        event, NULL, NULL, true);
    [self logPrefs:@"post event %@", event];
    [self statusSpecPending:@"执行中…"];

    // MCP 执行后回写 sshStatus + 广播 updated，这里延迟读一次兜底（apt-get 可能较慢）。
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf refreshFromStatusPref];
        weakSelf.busy = NO;
    });
}

// PSSwitchCell 拨动 -> 写 sshAutostart pref 后发 autostart 事件让 MCP 落地。
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
    BOOL isAutostart = [[spec name] isEqualToString:@"开机自启"];
    if (isAutostart) {
        [self logPrefs:@"autostart switch -> %@", value];
        // 先落盘再发事件（super 会写盘，这里确保 MCP 侧能读到最新值）
        [super setPreferenceValue:value specifier:spec];
        CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                            IOS_MCP_DARWIN_NOTIFICATION_SSH_AUTOSTART,
                                            NULL, NULL, true);
        return;
    }
    [super setPreferenceValue:value specifier:spec];
}

- (void)statusSpecPending:(NSString *)text {
    [self.statusSpec setName:text];
    [self reload];
}

#pragma mark - SSH 日志视图（读 helmtweak/ssh.log，参考 MCP 面板的悬浮 footer）

- (void)updateLogFooter {
    UITableView *table = [self valueForKey:@"table"];
    if (!table) return;
    if (!self.logFooterView) {
        [self buildSSHLogFooterWithTable:table];
    }
    table.tableFooterView = self.logFooterView;
    [self layoutSSHLogFooter];
    [self refreshLogViewer];
}

- (void)buildSSHLogFooterWithTable:(UITableView *)table {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, 253)];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *time = [[UILabel alloc] initWithFrame:CGRectZero];
    time.font = [UIFont systemFontOfSize:13.0];
    time.textColor = [UIColor secondaryLabelColor];
    time.text = @"暂无日志，点右上角刷新";
    [footer addSubview:time];
    self.logTimeLabel = time;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectZero;
    [btn setTitle:@"刷新" forState:UIControlStateNormal];
    [btn.titleLabel setFont:[UIFont systemFontOfSize:13.0]];
    btn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    btn.contentVerticalAlignment = UIControlContentVerticalAlignmentBottom;
    [btn addTarget:self action:@selector(refreshLogsTapped:) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:btn];
    self.logRefreshButton = btn;

    UILabel *log = [[UILabel alloc] initWithFrame:CGRectZero];
    log.numberOfLines = 15;
    log.lineBreakMode = NSLineBreakByTruncatingTail;
    log.backgroundColor = [UIColor clearColor];
    log.textColor = [UIColor secondaryLabelColor];
    log.font = [UIFont systemFontOfSize:11.0];
    log.text = @"";
    [footer addSubview:log];
    self.logTextLabel = log;

    self.logFooterView = footer;
}

- (void)layoutSSHLogFooter {
    UITableView *table = [self valueForKey:@"table"];
    if (!table || !self.logFooterView) return;

    CGFloat width = table.bounds.size.width;
    CGFloat inset = 16.0;
    CGFloat footerTop = 8.0;
    CGFloat headerH = 20.0;
    CGFloat logH = 225.0;
    CGFloat btnW = 56.0;

    CGRect f = self.logFooterView.frame;
    f.size.width = width;
    f.size.height = footerTop + headerH + logH;
    self.logFooterView.frame = f;

    CGFloat textX = inset + 16;
    CGFloat switchRight = width - inset;
    for (UITableViewCell *cell in [table visibleCells]) {
        if ([cell.accessoryView isKindOfClass:[UISwitch class]]) {
            CGRect accessoryFrame = [table convertRect:cell.accessoryView.frame
                                              fromView:cell.accessoryView.superview];
            switchRight = CGRectGetMaxX(accessoryFrame);
            break;
        }
    }
    CGFloat btnX = switchRight - btnW;

    CGFloat lineH = self.logTimeLabel.font.lineHeight;
    self.logTimeLabel.frame = CGRectMake(textX, footerTop + headerH - lineH, btnX - textX - 8, lineH);
    self.logRefreshButton.frame = CGRectMake(btnX, footerTop, btnW, headerH);
    self.logTextLabel.frame = CGRectMake(textX, footerTop + headerH, width - textX - inset, logH);

    table.tableFooterView = self.logFooterView;
}

- (void)refreshLogsTapped:(UIButton *)sender {
    [self performLogRefreshWithButton:sender];
}

- (void)performLogRefreshWithButton:(UIButton *)button {
    if (self.logViewerInstalled) return;
    self.logViewerInstalled = YES;

    UIActivityIndicatorView *spinner = nil;
    if (button) {
        spinner = [[UIActivityIndicatorView alloc]
            initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        NSString *title = [button titleForState:UIControlStateNormal];
        CGSize ts = [title sizeWithAttributes:@{NSFontAttributeName: button.titleLabel.font}];
        CGRect titleFrame = CGRectMake(button.bounds.size.width - ts.width,
                                       button.bounds.size.height - ts.height,
                                       ts.width, ts.height);
        spinner.frame = CGRectMake(CGRectGetMidX(titleFrame) - 10, CGRectGetMidY(titleFrame) - 10, 20, 20);
        [button addSubview:spinner];
        [button setTitle:@"" forState:UIControlStateNormal];
        [spinner startAnimating];
    }

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self refreshLogViewer];
        self.logViewerInstalled = NO;
        [spinner removeFromSuperview];
        if (button) [button setTitle:@"刷新" forState:UIControlStateNormal];
    });
}

// 读 ssh.log 最近 15 条，倒序（最新在前）写入 textView。
- (void)refreshLogViewer {
    if (!(self.isViewLoaded && self.view.window != nil)) return;
    NSArray<NSString *> *lines = [self lastSSHLogLines:15];
    if (!lines.count) {
        self.logTextLabel.text = @"";
        self.logTimeLabel.text = @"暂无日志，点右上角刷新";
        return;
    }

    NSString *newestTime = [self timestampFromSSHLogLine:lines.firstObject];
    self.logTimeLabel.text = newestTime ?: @"";

    NSMutableArray<NSString *> *display = [NSMutableArray array];
    CGFloat maxWidth = self.logTextLabel.bounds.size.width;
    for (NSString *line in lines) {
        NSString *clean = [self logLineWithoutTimestamp:line];
        if (clean.length) [display addObject:[self truncateSSHLine:clean toWidth:maxWidth]];
    }
    if (display.count) {
        self.logTextLabel.text = [display componentsJoinedByString:@"\n"];
    } else {
        self.logTextLabel.text = @"";
        self.logTimeLabel.text = @"暂无日志，点右上角刷新";
    }
}

- (NSString *)truncateSSHLine:(NSString *)string toWidth:(CGFloat)maxWidth {
    if (maxWidth <= 0) return string;
    UIFont *font = self.logTextLabel.font;
    if ([string sizeWithAttributes:@{NSFontAttributeName: font}].width <= maxWidth) return string;
    NSMutableString *ms = [string mutableCopy];
    while (ms.length > 1) {
        [ms deleteCharactersInRange:NSMakeRange(ms.length - 1, 1)];
        NSString *cand = [ms stringByAppendingString:@"…"];
        if ([cand sizeWithAttributes:@{NSFontAttributeName: font}].width <= maxWidth) return cand;
    }
    return @"…";
}

- (NSString *)timestampFromSSHLogLine:(NSString *)line {
    if (line.length < 19) return nil;
    NSString *head = [line substringToIndex:19];
    if ([head characterAtIndex:4] == '-' && [head characterAtIndex:7] == '-') {
        return head;
    }
    return nil;
}

// 去掉行首时间戳和 pid= 前缀，只留 message。
- (NSString *)logLineWithoutTimestamp:(NSString *)line {
    NSRange pidRange = [line rangeOfString:@"pid="];
    if (pidRange.location != NSNotFound) {
        NSUInteger msgPos = pidRange.location + pidRange.length;
        while (msgPos < line.length && [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[line characterAtIndex:msgPos]]) msgPos++;
        while (msgPos < line.length && [[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:msgPos]]) msgPos++;
        if (msgPos < line.length) {
            return [line substringFromIndex:msgPos];
        }
    }
    NSString *ts = [self timestampFromSSHLogLine:line];
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

- (NSArray<NSString *> *)lastSSHLogLines:(NSUInteger)count {
    NSArray<NSString *> *paths = @[
        @"/private/var/mobile/Library/Logs/helmtweak/ssh.log",
        @"/var/mobile/Library/Logs/helmtweak/ssh.log",
    ];
    NSString *content = @"";
    for (NSString *path in paths) {
        content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (content.length) break;
    }
    if (!content.length) return @[];
    NSArray<NSString *> *all = [content componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSInteger i = all.count - 1;
    while (i >= 0 && result.count < count) {
        NSString *line = [all[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length) [result addObject:line];
        i--;
    }
    return result;
}

@end
