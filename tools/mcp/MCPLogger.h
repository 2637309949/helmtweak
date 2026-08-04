#import <Foundation/Foundation.h>

@interface MCPLogger : NSObject

+ (BOOL)isDebugLoggingEnabled;
+ (NSString *)logDirectoryPath;
+ (NSString *)logFilePath;
+ (NSString *)previousLogFilePath;
+ (NSArray<NSString *> *)allLogFilePaths;
+ (NSString *)lastLogError;
+ (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (void)logMessage:(NSString *)message;
+ (void)logMessage:(NSString *)message toFileNamed:(NSString *)name;
+ (BOOL)clearLogsWithError:(NSError **)error;

@end
