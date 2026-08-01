#ifndef HelmLogger_h
#define HelmLogger_h

#import <Foundation/Foundation.h>

/// HelmCore 自带的最小日志器：NSLog + append 到 /var/mobile/Library/Logs/HelmCore/helmcore.log。
/// debug 开关复用 MCP prefs（com.witchan.ios-mcp.preferences/debugLoggingEnabled），
/// 这样 Settings 里已有的 debug switch 对 SDK 日志同样生效，行为不变。
@interface HelmLogger : NSObject

+ (BOOL)isDebugLoggingEnabled;
+ (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (void)logMessage:(NSString *)message;

@end

#endif
