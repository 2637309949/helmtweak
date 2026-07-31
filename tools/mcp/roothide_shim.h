// roothide_shim.h — non-roothide fallback for rootfs()/jbroot() calls
// upstream ios-mcp calls these unconditionally; when not building roothide
// we provide rootless (/var/jb) or rootful (identity) equivalents here.
#ifndef HELMCP_ROOTHIDE_SHIM_H
#define HELMCP_ROOTHIDE_SHIM_H

#import <Foundation/Foundation.h>

#ifdef MCP_ROOTLESS
static inline NSString *rootfs(NSString *path) {
    if (!path) return nil;
    return [NSString stringWithFormat:@"/var/jb%@", path];
}
static inline NSString *jbroot(NSString *path) {
    if (!path) return nil;
    return [NSString stringWithFormat:@"/var/jb%@", path];
}
#else
// rootful: identity
static inline NSString *rootfs(NSString *path) { return path; }
static inline NSString *jbroot(NSString *path) { return path; }
#endif

#endif
