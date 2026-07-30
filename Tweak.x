// HelmTweak — minimal Logos demo
// 注入 SpringBoard，respring 后在 syslog 打印 hello

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

%hook SpringBoard

// SpringBoard 启动完成回调，每次 respring 都会触发
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    NSLog(@"[HelmTweak] hello! SpringBoard injected on respring (pid=%d).",
          (int)getpid());
}

%end
