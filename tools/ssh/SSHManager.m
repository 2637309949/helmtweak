#import "SSHManager.h"
#import <HelmCore/HelmCore.h>
#import "MCPLogger.h"
#import <unistd.h>

// SSH 子系统日志单独落 helmtweak/ssh.log（走 MCPLogger 的命名文件 API，同 debugLoggingEnabled 门控）。
#define SSH_LOG(fmt, ...) do { \
    NSString *msg = [[NSString alloc] initWithFormat:@"[SSH] " fmt, ##__VA_ARGS__]; \
    [MCPLogger logMessage:msg toFileNamed:@"ssh"]; \
} while (0)

static NSString *const kSSHDDomainLabel = @"system/com.openssh.sshd";
static NSString *const kSSHDServiceName = @"com.openssh.sshd";

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

static NSString *SSHShellQuote(NSString *string) {
    NSString *value = string ?: @"";
    return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static NSString *SSHConfiguredSudoPassword(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("sudo_password"),
                                                        CFSTR("com.witchan.ios-mcp.preferences"));
    if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
        NSString *password = [(__bridge NSString *)value copy];
        CFRelease(value);
        if (password.length > 0) return password;
    } else if (value) {
        CFRelease(value);
    }
    return @"alpine";
}

// True when the mcp-root output indicates the helper ran but failed to escalate
// (sandbox blocks setuid on rootless) and a sudo fallback may still succeed.
static BOOL SSHOutputLooksLikePrivilegeFailure(NSString *output, int exitCode) {
    if (exitCode == 111) return YES;
    if (![output isKindOfClass:[NSString class]] || output.length == 0) return NO;
    return [output rangeOfString:@"setgid(0) failed"].location != NSNotFound ||
           [output rangeOfString:@"setuid(0) failed"].location != NSNotFound;
}

// Run a root command, matching AppManager's dual-channel pattern:
//   1. setuid mcp-root helper (roothide); if it runs but cannot escalate, or
//      is absent, fall through to:
//   2. `printf '<pw>' | sudo -k -S -p '' <command> <arguments>` (rootless/roothide).
// Returns NO with *errorMessage when no root channel is available at all.
- (BOOL)runRoot:(NSString *)command
      arguments:(NSArray<NSString *> *)arguments
         output:(NSString **)output
         error:(NSString **)errorMessage {
    if (output) *output = @"";
    if (errorMessage) *errorMessage = nil;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *rootHelper = MCPRootHelperPath();
    NSString *helperOutput = nil;
    NSString *helperError = nil;
    int helperExitCode = -1;

    if (rootHelper.length && [fm isExecutableFileAtPath:rootHelper]) {
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
        if (finished && exitCode == 0) {
            NSString *outText = outputData.length
                ? [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding]
                : @"";
            if (output) *output = outText;
            if (errorMessage) *errorMessage = nil;
            return YES;
        }
        helperExitCode = exitCode;
        helperOutput = outputData.length
            ? [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding]
            : @"";
        helperError = runError ?: @"";
        if (!SSHOutputLooksLikePrivilegeFailure(helperOutput, helperExitCode)) {
            if (output) *output = helperOutput;
            if (errorMessage) *errorMessage = helperError.length ? helperError : @"mcp-root invocation failed";
            SSH_LOG(@"root command failed spawn=%@ args=%@ err=%@",
                    command, arguments, helperError ?: @"-");
            return NO;
        }
        SSH_LOG(@"mcp-root privilege failed (exit=%d), trying sudo fallback", helperExitCode);
    }

    // sudo fallback (AppManager pattern): printf '<pw>' | sudo -k -S -p '' <cmd> <args>
    NSString *sudoPath = MCPResolvedJailbreakPath(@"/usr/bin/sudo");
    NSString *shellPath = MCPResolvedJailbreakPath(@"/bin/sh");
    if (![fm isExecutableFileAtPath:sudoPath]) {
        if (errorMessage) {
            *errorMessage = @"No privileged helper available (requires roothide jailbreak). On rootless, install/start/stop SSH manually via Sileo.";
        }
        return NO;
    }
    if (![fm isExecutableFileAtPath:shellPath]) {
        shellPath = @"/bin/sh";
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObjects:
                                         @"printf '%s\\n'",
                                         SSHShellQuote(SSHConfiguredSudoPassword()),
                                         @"|",
                                         SSHShellQuote(sudoPath),
                                         @"-k",
                                         @"-S",
                                         @"-p",
                                         @"''",
                                         SSHShellQuote(command),
                                         nil];
    for (NSString *argument in arguments) {
        [parts addObject:SSHShellQuote(argument)];
    }
    NSString *shellCommand = [parts componentsJoinedByString:@" "];

    NSString *sudoOutput = nil;
    NSString *sudoError = nil;
    int sudoExitCode = -1;
    BOOL sudoFinished = MCPRunProcess(shellPath,
                                      @[@"-lc", shellCommand],
                                      MCPJailbreakEnvironment(),
                                      120.0,
                                      512 * 1024,
                                      &sudoOutput,
                                      &sudoExitCode,
                                      &sudoError);
    if (output) *output = sudoOutput;
    if (errorMessage) {
        if (sudoError.length > 0) {
            *errorMessage = sudoError;
        } else if (sudoExitCode != 0) {
            *errorMessage = sudoOutput.length ? sudoOutput
                           : [NSString stringWithFormat:@"command exited %d", sudoExitCode];
        } else if (!sudoFinished) {
            *errorMessage = @"sudo invocation failed";
        }
    }
    SSH_LOG(@"sudo result finished=%d exit=%d args=%@", sudoFinished ? 1 : 0, sudoExitCode, arguments);
    return sudoFinished && sudoExitCode == 0;
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

    // Running: sshd is socket-activated (Sockets + inetdCompatibility), so there is no
    // persistent `sshd` process and `pgrep -x sshd` never matches. The service counts as
    // running when launchd has it registered with a listening socket:
    //   1. user/<uid>/ domain (Dopamine rootless) — readable without root.
    //   2. system/ domain (roothide) — via the root channel.
    //   3. process-list check as a last resort.
    BOOL running = NO;
    NSString *launchdState = @"unknown";
    NSString *rootHelper = MCPRootHelperPath();
    NSString *sudoPath = MCPResolvedJailbreakPath(@"/usr/bin/sudo");
    BOOL rootAvailable = (rootHelper.length && [fm isExecutableFileAtPath:rootHelper])
                      || ([sudoPath length] && [fm isExecutableFileAtPath:sudoPath]);
    NSString *launchctlPath = MCPResolvedJailbreakPath(@"/usr/bin/launchctl");
    NSString *userLabel = [NSString stringWithFormat:@"user/%d/%@",
                           (int)getuid(), kSSHDServiceName];
    NSString *launchctlOut = nil;
    int launchctlExit = -1;
    NSString *launchctlError = nil;
    BOOL launchctlOk = MCPRunProcess(launchctlPath,
                                     @[@"print", userLabel],
                                     MCPJailbreakEnvironment(),
                                     5.0,
                                     64 * 1024,
                                     &launchctlOut,
                                     &launchctlExit,
                                     &launchctlError);
    if (launchctlOk && launchctlExit == 0) {
        running = YES;
        launchdState = @"running";
    } else {
        if (rootAvailable) {
            NSString *systemOut = nil;
            NSString *systemError = nil;
            BOOL systemOk = [self runRoot:MCPResolvedJailbreakPath(@"/usr/bin/launchctl")
                                 arguments:@[@"print", kSSHDDomainLabel]
                                    output:&systemOut
                                     error:&systemError];
            if (systemOk && systemOut.length) {
                running = YES;
                launchdState = @"running";
            } else {
                launchdState = @"not-loaded";
            }
        } else {
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
        @"root_available": @(rootAvailable),
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
            rootAvailable ? 1 : 0);
    return status;
}

#pragma mark - Privileged operations

- (NSDictionary *)installSSH:(NSString **)error {
    NSString *output = nil;
    NSString *runError = nil;
    BOOL ok = [self runRoot:MCPResolvedJailbreakPath(@"/usr/bin/apt-get")
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
    BOOL ok = [self runRoot:MCPResolvedJailbreakPath(@"/usr/bin/launchctl")
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
    BOOL ok = [self runRoot:MCPResolvedJailbreakPath(@"/usr/bin/launchctl")
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
    BOOL ok = [self runRoot:MCPResolvedJailbreakPath(@"/usr/bin/launchctl")
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
        BOOL kicked = [self runRoot:MCPResolvedJailbreakPath(@"/usr/bin/launchctl")
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
