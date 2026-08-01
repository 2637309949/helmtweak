#import "HelmLogger.h"
#import <CoreFoundation/CoreFoundation.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <sys/time.h>
#import <unistd.h>

#define HELM_CORE_PREFERENCES_DOMAIN @"com.witchan.ios-mcp.preferences"
#define HELM_CORE_DEBUG_LOGGING_KEY @"debugLoggingEnabled"

static const CFTimeInterval HelmLoggerCacheTTL = 2.0;
static BOOL sHelmLoggerCached = NO;
static CFAbsoluteTime sHelmLoggerCacheTime = 0;

static NSObject *HelmLoggerStateLock(void) {
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lock = [NSObject new];
    });
    return lock;
}

static BOOL HelmLoggerReadDebugPreference(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)HELM_CORE_DEBUG_LOGGING_KEY,
                                                        (__bridge CFStringRef)HELM_CORE_PREFERENCES_DOMAIN);
    if (!value) {
        return NO;
    }

    BOOL enabled = NO;
    CFTypeID typeID = CFGetTypeID(value);
    if (typeID == CFBooleanGetTypeID()) {
        enabled = CFBooleanGetValue((CFBooleanRef)value);
    } else if (typeID == CFNumberGetTypeID()) {
        int numericValue = 0;
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &numericValue);
        enabled = numericValue != 0;
    }

    CFRelease(value);
    return enabled;
}

static NSString *HelmLoggerTimestamp(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);

    struct tm localTime;
    localtime_r(&tv.tv_sec, &localTime);

    char buffer[40];
    strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &localTime);
    char zone[8];
    strftime(zone, sizeof(zone), "%z", &localTime);
    return [NSString stringWithFormat:@"%s.%03d%s", buffer, (int)(tv.tv_usec / 1000), zone];
}

static NSString *HelmLoggerSanitizedMessage(NSString *message) {
    if (![message isKindOfClass:[NSString class]] || message.length == 0) {
        return @"";
    }

    NSString *clean = [message stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    clean = [clean stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if (clean.length > 4096) {
        clean = [[clean substringToIndex:4096] stringByAppendingString:@"...<truncated>"];
    }
    return clean;
}

static BOOL HelmLoggerWriteAll(int fd, NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    NSUInteger offset = 0;

    while (remaining > 0) {
        ssize_t written = write(fd, bytes + offset, remaining);
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written <= 0) {
            return NO;
        }
        offset += (NSUInteger)written;
        remaining -= (NSUInteger)written;
    }
    return YES;
}

@implementation HelmLogger

+ (BOOL)isDebugLoggingEnabled {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @synchronized (HelmLoggerStateLock()) {
        CFAbsoluteTime last = sHelmLoggerCacheTime;
        if (last != 0 && (now - last) >= 0 && (now - last) < HelmLoggerCacheTTL) {
            return sHelmLoggerCached;
        }
    }

    BOOL enabled = HelmLoggerReadDebugPreference();
    @synchronized (HelmLoggerStateLock()) {
        sHelmLoggerCached = enabled;
        sHelmLoggerCacheTime = now;
    }
    return enabled;
}

+ (void)log:(NSString *)format, ... {
    if (!format.length || ![self isDebugLoggingEnabled]) {
        return;
    }

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[HelmCore] %@", message);
    [self logMessage:message];
}

+ (void)logMessage:(NSString *)message {
    if (!message.length || ![self isDebugLoggingEnabled]) {
        return;
    }

    NSString *cleanMessage = HelmLoggerSanitizedMessage(message);
    NSString *line = [NSString stringWithFormat:@"%@ pid=%d %@\n",
                      HelmLoggerTimestamp(),
                      getpid(),
                      cleanMessage];
    NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!lineData.length) {
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dirPath = @"/var/mobile/Library/Logs/HelmCore";
    NSError *dirError = nil;
    if (![fm createDirectoryAtPath:dirPath
       withIntermediateDirectories:YES
                        attributes:@{NSFilePosixPermissions: @0755}
                             error:&dirError]) {
        return;
    }

    NSString *logPath = [dirPath stringByAppendingPathComponent:@"helmcore.log"];
    int logFd = open(logPath.fileSystemRepresentation, O_CREAT | O_APPEND | O_WRONLY, 0644);
    if (logFd < 0) {
        return;
    }
    HelmLoggerWriteAll(logFd, lineData);
    close(logFd);
}

@end
