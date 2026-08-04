#import "SSHManager.h"
#import <HelmCore/HelmCore.h>
#import "MCPLogger.h"

#define SSH_LOG(fmt, ...) [MCPLogger log:@"[SSH] " fmt, ##__VA_ARGS__]

static NSString *const kSSHDDomainLabel = @"system/com.openssh.sshd";

@implementation SSHManager

+ (instancetype)sharedInstance {
    static SSHManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SSHManager alloc] init];
    });
    return instance;
}

#pragma mark - Primitives

// Run a root command via the setuid mcp-root helper (roothide only).
// Returns NO with *errorMessage when no privileged helper is available.
- (BOOL)runRoot:(NSString *)command
      arguments:(NSArray<NSString *> *)arguments
         output:(NSString **)output
         error:(NSString **)errorMessage {
    NSString *rootHelper = MCPRootHelperPath();
    if (!rootHelper.length) {
        if (errorMessage) *errorMessage = @"No privileged helper available (requires roothide jailbreak). On rootless, install/start/stop SSH manually via Sileo.";
        return NO;
    }

    NSData *outputData = nil;
    BOOL truncated = NO;
    int exitCode = -1;
    NSString *runError = nil;

    BOOL finished = MCPRunRootProcessData(command,
                                          arguments,
                                          120.0,
                                          512 * 1024,
                                          &outputData,
                                          &truncated,
                                          &exitCode,
                                          &runError);
    if (!finished) {
        if (errorMessage) *errorMessage = runError.length ? runError : @"mcp-root invocation failed";
        SSH_LOG(@"root command failed spawn=%@ args=%@ err=%@",
                command, arguments, runError ?: @"-");
        return NO;
    }

    if (output) {
        *output = outputData.length
            ? [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding]
            : @"";
    }
    if (exitCode != 0) {
        NSString *outText = outputData.length
            ? [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding]
            : @"";
        if (errorMessage) {
            *errorMessage = outText.length ? outText : [NSString stringWithFormat:@"command exited %d", exitCode];
        }
        SSH_LOG(@"root command exit=%d args=%@", exitCode, arguments);
        return NO;
    }
    return YES;
}

// Non-root process check: true when any sshd process is alive.
- (BOOL)sshdProcessAlive {
    NSString *pgrep = MCPResolvedJailbreakPath(@"/usr/bin/pgrep");
    NSString *output = nil;
    NSString *runError = nil;
    int exitCode = -1;
    BOOL finished = MCPRunProcess(pgrep,
                                  @[@"-x", @"sshd"],
                                  MCPJailbreakEnvironment(),
                                  5.0,
                                  4096,
                                  &output,
                                  &exitCode,
                                  &runError);
    if (!finished) return NO;
    return exitCode == 0;
}

// True when the launchd autostart plist exists (RunAtLoad daemon installed).
- (BOOL)sshdAutostartPlistExists {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = MCPResolvedJailbreakPath(@"/Library/LaunchDaemons/com.openssh.sshd.plist");
    return path.length > 0 && [fm fileExistsAtPath:path];
}

#pragma mark - Status

- (NSDictionary *)getStatus:(NSString **)error {
    if (error) *error = nil;

    NSFileManager *fm = [NSFileManager defaultManager];

    NSString *sshdPath = MCPResolvedJailbreakPath(@"/usr/sbin/sshd");
    NSString *sshClientPath = MCPResolvedJailbreakPath(@"/usr/bin/ssh");
    NSString *scpPath = MCPResolvedJailbreakPath(@"/usr/bin/scp");

    BOOL serverInstalled = sshdPath.length > 0 && [fm isExecutableFileAtPath:sshdPath];
    BOOL clientInstalled = sshClientPath.length > 0 && [fm isExecutableFileAtPath:sshClientPath];
    BOOL scpInstalled = scpPath.length > 0 && [fm isExecutableFileAtPath:scpPath];

    // Running: prefer the launchd state via mcp-root (roothide), else process list.
    BOOL running = NO;
    NSString *launchdState = @"unknown";
    NSString *rootHelper = MCPRootHelperPath();
    if (rootHelper.length) {
        NSData *outputData = nil;
        BOOL truncated = NO;
        int exitCode = -1;
        NSString *runError = nil;
        BOOL finished = MCPRunRootProcessData(@"/usr/bin/launchctl",
                                              @[@"print", kSSHDDomainLabel],
                                              10.0,
                                              128 * 1024,
                                              &outputData,
                                              &truncated,
                                              &exitCode,
                                              &runError);
        if (finished && exitCode == 0 && outputData.length) {
            NSString *text = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
            if ([text containsString:@"state = running"]) {
                running = YES;
                launchdState = @"running";
            } else {
                launchdState = @"loaded-not-running";
            }
        } else if (finished) {
            launchdState = @"not-loaded";
        }
    }
    if (!running) {
        running = [self sshdProcessAlive];
    }

    BOOL autostart = [self sshdAutostartPlistExists];

    NSDictionary *status = @{
        @"scheme": [HelmSystemInfo isRoothide] ? @"roothide"
                  : [HelmSystemInfo isRootless] ? @"rootless" : @"rootful",
        @"server": @"openssh",
        @"server_installed": @(serverInstalled),
        @"client_installed": @(clientInstalled),
        @"scp_installed": @(scpInstalled),
        @"running": @(running),
        @"launchd_state": launchdState,
        @"autostart": @(autostart),
        @"root_available": @(rootHelper.length > 0),
        @"port": @22,
        @"ssh_cmd": sshClientPath,
        @"sshd_cmd": sshdPath,
    };

    SSH_LOG(@"status server=%d client=%d scp=%d running=%d launchd=%@ autostart=%d rootAvail=%d",
            serverInstalled ? 1 : 0,
            clientInstalled ? 1 : 0,
            scpInstalled ? 1 : 0,
            running ? 1 : 0,
            launchdState,
            autostart ? 1 : 0,
            (int)(rootHelper.length > 0));
    return status;
}

#pragma mark - Privileged operations

- (NSDictionary *)installSSH:(NSString **)error {
    NSString *output = nil;
    NSString *runError = nil;
    BOOL ok = [self runRoot:@"/usr/bin/apt-get"
                 arguments:@[@"install", @"-y", @"openssh-server", @"openssh-client"]
                    output:&output
                     error:&runError];
    if (!ok) {
        if (error) *error = runError.length ? runError : @"apt-get install failed";
        return nil;
    }
    SSH_LOG(@"installed openssh-server + openssh-client");
    return @{
        @"ok": @YES,
        @"message": @"Installed openssh-server + openssh-client",
        @"output": output ?: @""
    };
}

- (NSDictionary *)startSSH:(NSString **)error {
    NSString *output = nil;
    NSString *runError = nil;
    NSString *sshdPlist = MCPResolvedJailbreakPath(@"/Library/LaunchDaemons/com.openssh.sshd.plist");
    BOOL ok = [self runRoot:@"/usr/bin/launchctl"
                 arguments:@[@"bootstrap", @"system", sshdPlist]
                    output:&output
                     error:&runError];
    if (!ok) {
        if (error) *error = runError.length ? runError : @"launchctl bootstrap failed";
        return nil;
    }
    SSH_LOG(@"started sshd");
    return @{@"ok": @YES, @"message": @"sshd started", @"output": output ?: @""};
}

- (NSDictionary *)stopSSH:(NSString **)error {
    NSString *output = nil;
    NSString *runError = nil;
    BOOL ok = [self runRoot:@"/usr/bin/launchctl"
                 arguments:@[@"bootout", kSSHDDomainLabel]
                    output:&output
                     error:&runError];
    if (!ok) {
        if (error) *error = runError.length ? runError : @"launchctl bootout failed";
        return nil;
    }
    SSH_LOG(@"stopped sshd");
    return @{@"ok": @YES, @"message": @"sshd stopped", @"output": output ?: @""};
}

- (NSDictionary *)setAutostart:(BOOL)enabled error:(NSString **)error {
    NSString *output = nil;
    NSString *runError = nil;
    NSArray<NSString *> *verb = @[enabled ? @"enable" : @"disable", kSSHDDomainLabel];
    BOOL ok = [self runRoot:@"/usr/bin/launchctl"
                 arguments:verb
                    output:&output
                     error:&runError];
    if (!ok) {
        if (error) *error = runError.length ? runError : @"launchctl enable/disable failed";
        return nil;
    }

    // When enabling, kickstart so the daemon loads without waiting for reboot.
    if (enabled) {
        NSString *kickOutput = nil;
        NSString *kickError = nil;
        BOOL kicked = [self runRoot:@"/usr/bin/launchctl"
                          arguments:@[@"kickstart", @"-k", kSSHDDomainLabel]
                             output:&kickOutput
                              error:&kickError];
        if (!kicked && kickError.length) {
            if (error) *error = kickError;
            return nil;
        }
    }

    SSH_LOG(@"set autostart=%d", enabled ? 1 : 0);
    return @{@"ok": @YES, @"message": enabled ? @"开机自启已开启" : @"开机自启已关闭"};
}

@end
