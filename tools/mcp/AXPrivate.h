#ifndef MCP_AXPRIVATE_SHIM_h
#define MCP_AXPRIVATE_SHIM_h

// 私有 header 已集中到 SDK/HelmCore/Private/AXPrivate.h。
// 此文件保留为兼容 shim，避免工具层改动。
// 注意：guard 名必须和 SDK 目标头不同，否则 SDK 头会被跳过（CI 已踩过）。
#import "../../SDK/HelmCore/Private/AXPrivate.h"

#endif /* MCP_AXPRIVATE_SHIM_h */
