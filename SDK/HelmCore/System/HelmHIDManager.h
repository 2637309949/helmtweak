#ifndef HelmHIDManager_h
#define HelmHIDManager_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSUInteger, HelmHIDButtonType) {
    HelmHIDButtonVolumeUp,
    HelmHIDButtonVolumeDown,
    HelmHIDButtonPower,
    HelmHIDButtonHome,
    HelmHIDButtonMute,
};

typedef NS_ENUM(NSUInteger, HelmTouchPhase) {
    HelmTouchPhaseBegan,
    HelmTouchPhaseMoved,
    HelmTouchPhaseEnded,
};

/// HID 触摸/按键注入。全部走 IOHIDEventSystemClient（私有 IOKit API 集中在 HelmCore/Private/IOHIDPrivate.h），
/// 工具层不直接接触 IOHID 私有函数。
@interface HelmHIDManager : NSObject

+ (BOOL)isSupportedOnCurrentIOS;

+ (instancetype)sharedInstance;

/// Simulate a physical button press with optional duration (ms)
- (void)pressButton:(HelmHIDButtonType)button duration:(NSTimeInterval)durationMs completion:(void (^)(BOOL success, NSString *error))completion;

/// Send a single touch event at screen point coordinates
- (void)sendTouchAtPoint:(CGPoint)point phase:(HelmTouchPhase)phase;

/// Simulate a tap at screen point coordinates
- (void)tapAtPoint:(CGPoint)point completion:(void (^)(BOOL success, NSString *error))completion;

/// Simulate a swipe gesture
- (void)swipeFromPoint:(CGPoint)from
               toPoint:(CGPoint)to
              duration:(NSTimeInterval)durationMs
                 steps:(NSInteger)steps
            completion:(void (^)(BOOL success, NSString *error))completion;

/// Simulate a long press at screen point coordinates
- (void)longPressAtPoint:(CGPoint)point
                duration:(NSTimeInterval)durationMs
              completion:(void (^)(BOOL success, NSString *error))completion;

/// Simulate a double tap at screen point coordinates
- (void)doubleTapAtPoint:(CGPoint)point
                interval:(NSTimeInterval)intervalMs
              completion:(void (^)(BOOL success, NSString *error))completion;

/// Simulate a drag and drop gesture (long press then move along a path)
- (void)dragAlongPoints:(NSArray<NSValue *> *)points
           holdDuration:(NSTimeInterval)holdMs
           moveDuration:(NSTimeInterval)moveMs
                  steps:(NSInteger)steps
             completion:(void (^)(BOOL success, NSString *error))completion;

/// Simulate a drag and drop gesture (long press then move to destination)
- (void)dragFromPoint:(CGPoint)from
              toPoint:(CGPoint)to
         holdDuration:(NSTimeInterval)holdMs
         moveDuration:(NSTimeInterval)moveMs
                steps:(NSInteger)steps
           completion:(void (^)(BOOL success, NSString *error))completion;

@end

#endif
