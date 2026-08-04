#import <Foundation/Foundation.h>

/// SSH lifecycle management for the OpenSSH server (com.openssh.sshd) installed via
/// the jailbreak package manager. Read-only status works on both rootless and roothide;
/// privileged operations (install/start/stop/autostart) require the setuid mcp-root
/// helper, which is only available on roothide.
@interface SSHManager : NSObject

+ (instancetype)sharedInstance;

/// Returns device/package/daemon status. Never requires root.
/// Returns dict, or nil with *error.
- (NSDictionary *)getStatus:(NSString **)error;

/// Install openssh-server + openssh-client via apt-get (root required).
/// Returns a human-readable result, or nil with *error on rootless (no root channel).
- (NSDictionary *)installSSH:(NSString **)error;

/// Start the sshd daemon via launchctl bootstrap system (root required).
- (NSDictionary *)startSSH:(NSString **)error;

/// Stop the sshd daemon via launchctl bootout system (root required).
- (NSDictionary *)stopSSH:(NSString **)error;

/// Toggle launchd auto-start for sshd (root required).
- (NSDictionary *)setAutostart:(BOOL)enabled error:(NSString **)error;

@end
