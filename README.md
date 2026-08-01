# HelmTweak

iOS **越狱 tweak**（Dopamine rootless / ElleKit），核心是一个 **MCP (Model Context Protocol) server**，注入 SpringBoard，让 AI 通过 MCP 协议操控手机（截图、OCR、触摸、文本输入、应用管理、文件系统、崩溃日志等）。

构建为 fat **arm64 + arm64e** deb，覆盖 A12–A17（iPhone XS → iPhone 16 系）。CI（macOS cloud）是唯一分发渠道，产出 deb artifact。

## 三层架构

```
helmtweak/
├── SDK/HelmCore/          # SDK 层：跨应用复用 dylib + 私有 header 集中声明
│   └── System/            # HelmSystemInfo / Screen / OCR / HID / AppManager / AX 栈等
├── tools/                 # 应用层
│   └── mcp/               # HelmMCP：用户可用的 MCP server（注入 SpringBoard）
│       └── helpers/       # MCP 内部 CLI（不暴露给用户）
│           ├── mcp-logreader/   # diagnosticd unified log
│           ├── mcp-ldid/        # 独立 codesign
│           ├── mcp-appsync/     # AppSync dylibs + mcp-appinst IPA 安装
│           ├── mcp-root/        # setuid root 命令白名单（roothide）
│           └── mcp-roothelper/  # setuid IPA 安装器（roothide）
├── scripts/               # 开发工具链（部署/验证/诊断/MCP 客户端，不进 deb）
├── third_party/           # vendored 构建依赖（ldid/libzip/procursus-sdk，只被 helpers 链接）
└── HelmTweakPrefs/        # Settings 面板（MCP 开关/端口/日志）
```

> 新增代码别放错层：用户可见的"工具"只能进 MCP 的 tools；CLI helper 放 `tools/mcp/helpers/`；部署/诊断脚本放 `scripts/`；跨应用能力放 `SDK/HelmCore/`；第三方 vendored 依赖放 `third_party/`。

## MCP server

- 默认**关闭**（省电）。Settings → HelmTweak → MCP → 启动服务 手动开启。
- 端口 `8686`（可在面板改），HTTP JSON-RPC 端点 `http://<ip>:8686/mcp`。
- 47 个工具：硬件按键、触摸手势、截图/OCR/UI 树、文本输入、应用管理、文件系统、剪贴板、设备控制、日志/崩溃、`get_usage_guide`（完整使用指引）。

## Build

```sh
# 主项目（CI 前置会 build HelmCore + helpers）
make clean && make package
# 输出 packages/com.example.helmtweak_<ver>_iphoneos-arm64.deb

# CI 构建顺序（见 .github/workflows/build.yml）：
#   third_party/libzip -> SDK/HelmCore -> tools/mcp/helpers/* -> 主项目
```

- 只支持 rootless + roothide 双 scheme，**永不 ship rootful**。
- CI 只 build rootless；roothide 需在 roothide 设备本地 `make clean && make package THEOS_PACKAGE_SCHEME=roothide`。

## Deploy (装机)

见 `scripts/`：`deploy.py` / `verify.py` / `diag.py` / `mcp.py`。手机连接信息在 `mobile.txt`（gitignored）。详见 [CLAUDE.md](CLAUDE.md)。

## License

- HelmMCP：forked from [witchan/ios-mcp](https://github.com/witchan/ios-mcp)，GPL-3.0（见 `tools/mcp/LICENSE`）。
- AppSync Unified：GPL-3.0。
- mcp-ldid：forked from ProcursusSDK，LGPL-2.1+。
- libzip：vendored，BSD-3-Clause。
