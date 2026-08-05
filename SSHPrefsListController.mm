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
            if ([[spec name] isEqualToString:@"加载中"]) {
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
        statusText = @"未安装 openssh-server";
    } else if (running) {
        statusText = @"运行中";
    } else {
        statusText = @"已安装，未运行";
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

@end
