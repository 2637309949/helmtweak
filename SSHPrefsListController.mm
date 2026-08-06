// SSHPrefsListController — SSH 工具子面板
//
// 主控制：单个 cell（sshToggleCell），按 SSH 状态机动态呈现（与 MCP 面板的「服务」开关对齐）：
//   - uninstalled  -> 一行文字「开始安装」，点击即安装（隐藏开关）
//   - installing   -> 「安装中」+ 转圈
//   - installed    -> 开关 off（显示 UISwitch）
//   - starting     -> 「启动中」+ 转圈
//   - running      -> 开关 on
//   - stopping     -> 「停止中」+ 转圈
//   - 安装/操作失败 -> 文字「安装失败」+ 日志见「查看日志」页
//
// 状态来源：SpringBoard 内 SSHManager 把最新状态写成 JSON pref `sshStatus` + 状态机
// `sshServerStatus`，再广播 `ssh-status-updated`。本面板：
//   - 进面板/收到更新 -> 读这两个 pref -> 更新 cell 呈现
//   - 点击「开始安装」/ 拨动开关 -> 发 darwin 事件（install/start/stop）给 MCP
//   - 开机自启 PSSwitchCell 绑定 sshAutostart pref，setPreferenceValue: 拦截后发 autostart 事件
//
// 与 MCP 面板同样的硬约束：不动态构造 PSSpecifier；只 [spec setName:]+[self reload] 改文字。

#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "IOSMCPPreferences.h"
#import "HelmLogViewerController.h"

@interface PSListController (HelmSSHPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reload;
@end

@interface PSSpecifier (HelmSSHPrivate)
- (void)setName:(NSString *)name;
@end

@interface SSHPrefsListController : PSListController
@property (nonatomic, strong) NSDictionary *sshStatus;
@property (nonatomic, strong) PSSpecifier *toggleSpec;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL serverInstalled;
@property (nonatomic, assign) BOOL serverRunning;
@property (nonatomic, copy) NSString *serverStatus;
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
            if ([[spec name] isEqualToString:@"SSH 服务"]) {
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
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self unregisterObservers];
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
    });
}

#pragma mark - Status

- (void)requestStatusRefresh {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        IOS_MCP_DARWIN_NOTIFICATION_SSH_STATUS,
                                        NULL, NULL, true);
}

- (NSString *)prefString:(NSString *)key {
    CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                     CFSTR("com.witchan.ios-mcp.preferences"));
    NSString *value = nil;
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) {
        value = [(__bridge NSString *)v copy];
    }
    if (v) CFRelease(v);
    return value ?: @"";
}

// 读 sshStatus JSON + sshServerStatus 状态机，更新主 cell 呈现。
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

    self.serverInstalled = [self.sshStatus[@"server_installed"] boolValue];
    self.serverRunning = [self.sshStatus[@"running"] boolValue];
    self.serverStatus = [self prefString:@"sshServerStatus"];
    BOOL rootAvail = [self.sshStatus[@"root_available"] boolValue];
    NSString *lastError = self.sshStatus[@"last_error"];

    [self logPrefs:@"refresh installed=%d running=%d status=%@ root=%d",
            self.serverInstalled ? 1 : 0, self.serverRunning ? 1 : 0,
            self.serverStatus, rootAvail ? 1 : 0];

    // 中间态：转圈 + 文字，busy 锁定，不可操作。
    if ([self.serverStatus isEqualToString:@"installing"] ||
        [self.serverStatus isEqualToString:@"starting"] ||
        [self.serverStatus isEqualToString:@"stopping"]) {
        self.busy = YES;
        NSString *label = [self.serverStatus isEqualToString:@"installing"] ? @"安装中"
                          : [self.serverStatus isEqualToString:@"starting"] ? @"启动中"
                          : @"停止中";
        [self.toggleSpec setName:label];
        [self reload];
        [self applyAccessorySpinner:YES];
        [self scheduleStatusTimeout];
        return;
    }

    self.busy = NO;
    [self applyAccessorySpinner:NO];

    if (!self.serverInstalled) {
        // 未安装：文字按钮「开始安装」，隐藏开关。
        [self.toggleSpec setName:@"开始安装"];
        [self reload];
        [self setSwitchVisible:NO];
        return;
    }

    // 已安装：显示开关，on=running。
    [self.toggleSpec setName:@"SSH 服务"];
    [self reload];
    [self setSwitchVisible:YES];
    self.toggleSwitch.on = self.serverRunning;

    // 操作失败提示：文字标注 + 日志见查看日志页。
    if (lastError.length && ![self.serverRunning boolValue]) {
        [self.toggleSpec setName:lastError];
        [self reload];
    }

    [self logPrefs:@"state installed=%d running=%d", self.serverInstalled ? 1 : 0, self.serverRunning ? 1 : 0];
}

// 开关位置转圈：中间态时把 toggle cell 的 accessory 换成 spinner。
- (void)applyAccessorySpinner:(BOOL)loading {
    UITableView *table = [self valueForKey:@"table"];
    if (!table) return;
    for (UITableViewCell *cell in [table visibleCells]) {
        if (![cell.textLabel.text isEqualToString:[self.toggleSpec name]] &&
            ![cell.textLabel.text isEqualToString:@"安装中"] &&
            ![cell.textLabel.text isEqualToString:@"启动中"] &&
            ![cell.textLabel.text isEqualToString:@"停止中"]) {
            continue;
        }
        if (loading) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        }
    }
}

// 显示/隐藏开关：仅安装在非中间态时显示 UISwitch。
- (void)setSwitchVisible:(BOOL)visible {
    UITableView *table = [self valueForKey:@"table"];
    if (!table) return;
    for (UITableViewCell *cell in [table visibleCells]) {
        if (![cell.textLabel.text isEqualToString:@"SSH 服务"]) {
            continue;
        }
        if (visible) {
            if (self.toggleSwitch) {
                cell.accessoryView = self.toggleSwitch;
                self.toggleSwitch.on = self.serverRunning;
            } else {
                UISwitch *sw = [[UISwitch alloc] init];
                self.toggleSwitch = sw;
                sw.on = self.serverRunning;
                [sw addTarget:self action:@selector(sshSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = sw;
            }
        } else {
            cell.accessoryView = nil;
        }
    }
}

// 已安装时拨动开关 -> 发 start/stop 事件。
- (void)sshSwitchChanged:(UISwitch *)sender {
    if (self.busy) return;
    [self postEvent:sender.isOn ? IOS_MCP_DARWIN_NOTIFICATION_SSH_START
                                : IOS_MCP_DARWIN_NOTIFICATION_SSH_STOP];
    [self logPrefs:@"toggle switch -> %@", sender.isOn ? @"start" : @"stop"];
}

// 3s 兜底定时器：等待事件回执期间超时后，主动请求最新状态。
- (void)scheduleStatusTimeout {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (self.busy) {
            [self requestStatusRefresh];
        }
    });
}

- (void)postEvent:(CFStringRef)event {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        event, NULL, NULL, true);
}

// 未安装时点击「开始安装」行 -> 发 install 事件。
// 主 cell 点击（PSButtonCell action）：未安装 -> 触发安装；已安装 -> 开关自己处理拨动。
- (void)toggleRowTapped:(PSSpecifier *)spec {
    if (self.busy) return;
    if (!self.serverInstalled) {
        self.busy = YES;
        [self postEvent:IOS_MCP_DARWIN_NOTIFICATION_SSH_INSTALL];
        [self.toggleSpec setName:@"安装中"];
        [self reload];
        [self logPrefs:@"post install"];
    }
}

#pragma mark - Actions

// PSSwitchCell 拨动 -> 写 sshAutostart pref 后发 autostart 事件让 MCP 落地。
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)spec {
    BOOL isAutostart = [[spec name] isEqualToString:@"开机自启"];
    if (isAutostart) {
        [self logPrefs:@"autostart switch -> %@", value];
        // 先落盘再发事件（super 会写盘，这里确保 MCP 侧能读到最新值）
        [super setPreferenceValue:value specifier:spec];
        CFPreferencesAppSynchronize(CFSTR("com.witchan.ios-mcp.preferences"));
        [self postEvent:IOS_MCP_DARWIN_NOTIFICATION_SSH_AUTOSTART];
        return;
    }
    [super setPreferenceValue:value specifier:spec];
}

- (void)statusSpecPending:(NSString *)text {
    [self.toggleSpec setName:text];
    [self reload];
}

// 「查看日志」PSButtonCell action：手动推入 SSH 日志查看器。
- (void)showSSHLog:(PSSpecifier *)spec {
    SSHLogViewerController *vc = [[SSHLogViewerController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
