#ifndef HelmScreenManager_h
#define HelmScreenManager_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// 屏幕信息 + 截图 + 设备交互状态。私有 SB 调用全部走 NSClassFromString/NSSelectorFromString/
/// dlsym 软引用，找不到返回 nil/fallback，绝不 crash。
@interface HelmScreenManager : NSObject

+ (BOOL)isSupportedOnCurrentIOS;

+ (instancetype)sharedInstance;

/// Get screen info: width, height, scale, orientation
- (NSDictionary *)screenInfo;

/// Best-effort device interaction state from SpringBoard private APIs.
- (NSDictionary *)deviceInteractionState;

/// Take screenshot and return encoded image payload with data/mimeType.
- (NSDictionary *)takeScreenshotPayload;

/// Capture the current screen as a UIImage (for in-process OCR). Runs capture on the
/// main thread. Returns nil if all private capture paths fail.
- (UIImage *)captureScreenImage;

@end

#endif
