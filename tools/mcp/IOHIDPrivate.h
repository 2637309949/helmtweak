#ifndef MCP_IOHIDPRIVATE_SHIM_h
#define MCP_IOHIDPRIVATE_SHIM_h

// 私有 header 已集中到 SDK/HelmCore/Private/IOHIDPrivate.h。
// 此文件保留为兼容 shim，避免工具层改动。
// 注意：guard 名必须和 SDK 目标头不同，否则 SDK 头会被跳过（CI 已踩过）。
#import "../../SDK/HelmCore/Private/IOHIDPrivate.h"

#endif /* MCP_IOHIDPRIVATE_SHIM_h */
