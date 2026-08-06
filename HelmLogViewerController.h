// HelmLogViewerController — 全屏日志查看器（公开头）
//
// 由面板「查看日志」PSButtonCell 的 action 推入（不用 PSLinkCell detail，
// 纯 UIViewController 做 detail 会让 Preferences 的 controllerForSpecifier: 崩）。
// 页面主体是可滚动 UITextView（Menlo 等宽字体），最新日志在最上，可选中复制。
// 导航栏右侧「刷新」「清空」按钮。进页面自动加载。
//
// 子类只需覆写 logFilePaths: 指定日志文件；MCP/SSH 各自一个子类。

#ifndef HELM_LOG_VIEWER_CONTROLLER_H
#define HELM_LOG_VIEWER_CONTROLLER_H

#import <UIKit/UIKit.h>

@interface HelmLogViewerController : UIViewController
// 要读取的日志文件路径列表（按序尝试，取第一个存在的）。子类覆写。
- (NSArray<NSString *> *)logFilePaths;
// 清空时要删的文件列表。默认等于 logFilePaths。子类可覆写加目录扫描。
- (NSArray<NSString *> *)clearFilePaths;
// 读取的最大行数（最新 N 行），防止日志文件过大。
- (NSUInteger)maxLines;
@end

@interface MCPLogViewerController : HelmLogViewerController
@end

@interface SSHLogViewerController : HelmLogViewerController
@end

#endif
