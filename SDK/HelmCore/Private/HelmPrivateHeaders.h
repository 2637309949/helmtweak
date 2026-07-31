#ifndef HelmPrivateHeaders_h
#define HelmPrivateHeaders_h

#import <Foundation/Foundation.h>

// ============================================================
// HelmCore 私有 header 集中声明区。
// 任何 `_` 开头类 / SB 类的私有 selector 都只能在这里声明，
// 由 HelmCore 各 Manager 内部调用，工具层绝不直接接触。
// ============================================================

// ============================================================
// LSApplicationProxy (LaunchServices)
// ============================================================

@interface LSApplicationProxy : NSObject
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
- (NSString *)applicationType; // "User", "System", "Internal"
- (NSURL *)bundleURL;
@end

// ============================================================
// LSApplicationWorkspace (LaunchServices)
// ============================================================

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
- (BOOL)installApplication:(NSURL *)appURL withOptions:(NSDictionary *)options error:(NSError **)error;
- (BOOL)uninstallApplication:(NSString *)bundleIdentifier withOptions:(NSDictionary *)options;
@end

// ============================================================
// SBApplication (SpringBoard)
// ============================================================

@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
- (NSString *)displayName;
- (BOOL)isRunning;
- (id)processState;
@end

// ============================================================
// SBApplicationController (SpringBoard)
// ============================================================

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
+ (instancetype)sharedInstanceIfExists;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleId;
- (NSArray<SBApplication *> *)allApplications;
- (NSArray<SBApplication *> *)runningApplications;
@end

// ============================================================
// FBSSystemService (FrontBoard)
// ============================================================

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)terminateApplication:(NSString *)bundleId
                   forReason:(int)reason
                   andReport:(BOOL)report
             withDescription:(NSString *)description;
- (pid_t)pidForApplication:(NSString *)bundleId;
@end

// ============================================================
// SBMainWorkspace (SpringBoard) — frontmost app detection
// ============================================================

@interface SBMainWorkspace : NSObject
+ (instancetype)sharedInstance;
@end

// ============================================================
// SBLockScreenManager (SpringBoard)
// ============================================================

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
- (BOOL)attemptUnlockWithPasscode:(NSString *)passcode;
- (void)lockUIFromSource:(int)source withOptions:(NSDictionary *)options;
- (void)unlockUIFromSource:(int)source withOptions:(NSDictionary *)options;
@end

// ============================================================
// SBUserAgent (SpringBoard)
// ============================================================

@interface SBUserAgent : NSObject
+ (instancetype)sharedInstance;
- (void)lockAndDimDevice;
@end

#endif /* HelmPrivateHeaders_h */
