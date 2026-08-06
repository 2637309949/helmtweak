// HelmLogViewerController — 全屏日志查看器
//
// 独立于 PreferenceBundle 的普通 UIViewController，由面板「查看日志」PSButtonCell 的
// action 推入（见 MCPPrefsListController/SSHPrefsListController 的 showMCPLog:/showSSHLog:）。
// 页面主体是可滚动 UITextView（Menlo 等宽字体），最新日志在最上，可选中复制。
// 导航栏右侧「刷新」「清空」按钮。进页面自动加载。
//
// 子类只需覆写 logFilePaths: 指定日志文件；MCP/SSH 各自一个子类。

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import "HelmLogViewerController.h"

@implementation HelmLogViewerController {
    UITextView *_textView;
    BOOL _loading;
}

- (NSUInteger)maxLines {
    return 800;
}

- (NSArray<NSString *> *)logFilePaths {
    return @[];
}

- (NSArray<NSString *> *)clearFilePaths {
    return [self logFilePaths];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.edgesForExtendedLayout = UIRectEdgeNone;

    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.dataDetectorTypes = UIDataDetectorTypeNone;
    _textView.font = [UIFont fontWithName:@"Menlo" size:12.0];
    _textView.textColor = [UIColor labelColor];
    _textView.backgroundColor = [UIColor clearColor];
    _textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.view addSubview:_textView];

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithTitle:@"刷新"
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(refreshTapped:)];
    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(clearTapped:)];
    self.navigationItem.rightBarButtonItems = @[clear, refresh];

    [self reloadLogs];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    // 每次进入（含从别的页面返回）刷新一次，保持最新。
    if (_textView && _textView.text.length == 0) {
        [self reloadLogs];
    }
}

- (void)refreshTapped:(id)sender {
    [self reloadLogs];
}

// 读日志文件最新 N 行，倒序（最新在最上）写入 textView。
- (void)reloadLogs {
    if (_loading) return;
    _loading = YES;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *content = @"";
        for (NSString *path in [self logFilePaths]) {
            NSString *c = [NSString stringWithContentsOfFile:path
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
            if (c.length) {
                content = c;
                break;
            }
        }

        // 取最新 maxLines 行，倒序。
        NSArray<NSString *> *all = [content componentsSeparatedByString:@"\n"];
        NSMutableArray<NSString *> *tail = [NSMutableArray array];
        NSInteger i = (NSInteger)all.count - 1;
        NSUInteger count = 0;
        while (i >= 0 && count < [self maxLines]) {
            NSString *line = [all[i] stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (line.length) {
                [tail addObject:line];
                count++;
            }
            i--;
        }

        NSString *display = tail.count ? [tail componentsJoinedByString:@"\n"] : @"暂无日志";
        dispatch_async(dispatch_get_main_queue(), ^{
            _textView.text = display;
            _loading = NO;
        });
    });
}

- (void)clearTapped:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空日志"
                                                                   message:@"将删除日志文件，确认清空？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *path in [self clearFilePaths]) {
            if ([fm fileExistsAtPath:path]) {
                [fm removeItemAtPath:path error:nil];
            }
        }
        _textView.text = @"已清空";
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// ===== MCP 日志查看器 =====

@implementation MCPLogViewerController

- (instancetype)init {
    self = [super init];
    if (self) self.title = @"MCP 日志";
    return self;
}

- (NSArray<NSString *> *)logFilePaths {
    return @[
        @"/private/var/mobile/Library/Logs/helmtweak/mcp.log",
        @"/var/mobile/Library/Logs/helmtweak/mcp.log",
    ];
}

- (NSArray<NSString *> *)clearFilePaths {
    // 清 helmtweak + HelmCore 两个日志目录。
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithArray:[self logFilePaths]];
    for (NSString *dir in @[@"/var/mobile/Library/Logs/helmtweak",
                            @"/var/mobile/Library/Logs/HelmCore"]) {
        for (NSString *file in [fm contentsOfDirectoryAtPath:dir error:nil]) {
            if ([file hasSuffix:@".log"]) {
                [paths addObject:[dir stringByAppendingPathComponent:file]];
            }
        }
    }
    return paths;
}

@end

// ===== SSH 日志查看器 =====

@implementation SSHLogViewerController

- (instancetype)init {
    self = [super init];
    if (self) self.title = @"SSH 日志";
    return self;
}

- (NSArray<NSString *> *)logFilePaths {
    return @[
        @"/private/var/mobile/Library/Logs/helmtweak/ssh.log",
        @"/var/mobile/Library/Logs/helmtweak/ssh.log",
    ];
}

@end
