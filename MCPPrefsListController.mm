// MCPPrefsListController — MCP 工具子面板（阶段 1 占位）
// 后续 fork ios-mcp 源码进 tools/mcp/，把真实 MCP 配置项接到这里

#import <Preferences/Preferences.h>

@interface PSListController (HelmTweakPrivate)
- (NSMutableArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
@end

@interface MCPPrefsListController : PSListController
@end

@implementation MCPPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"MCP" target:self];
    }
    return _specifiers;
}

@end
