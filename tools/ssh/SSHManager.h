#import <Foundation/Foundation.h>

/// SSH lifecycle management for the OpenSSH server (com.openssh.sshd) installed via
/// the jailbreak package manager. Status (installed/running/autostart) works on both
/// rootless and roothide; privileged operations (install/start/stop/autostart) run
/// through the setuid mcp-root helper when available (roothide), falling back to
/// `sudo -S` on rootless (AppManager pattern). Returns a no-root-channel message
/// only when neither helper exists.
@interface SSHManager : NSObject

+ (instancetype)sharedInstance;

/// Returns device/package/daemon status. Queries launchd state via the root channel
/// when available (otherwise falls back to a process check).
/// Returns dict, or nil with *error.
- (NSDictionary *)getStatus:(NSString **)error;

/// Install openssh-server + openssh-client via apt-get (root required).
/// Returns a human-readable result, or nil with *error when no root channel exists.
- (NSDictionary *)installSSH:(NSString **)error;

/// Start the sshd daemon via launchctl bootstrap system (root required).
- (NSDictionary *)startSSH:(NSString **)error;

/// Stop the sshd daemon via launchctl bootout system (root required).
- (NSDictionary *)stopSSH:(NSString **)error;

/// Toggle launchd auto-start for sshd (root required).
- (NSDictionary *)setAutostart:(BOOL)enabled error:(NSString **)error;

@end
