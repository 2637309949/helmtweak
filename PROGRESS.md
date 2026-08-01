# PROGRESS — Phase 3 (HelmCore SDK) 全部完成

下次打开先看这个 + [CLAUDE.md](CLAUDE.md)，直接接着干。

## 当前状态 ✅

- **Phase 3 全部完成**：HelmCore SDK 建立，HelmMCP 切到 HelmCore，工具 manifest + prefs 兼容性过滤落地，CI 全绿。
- **版本**：`1.0.27`。
- **step 5 变更**：
  - [HelmTweakPrefs/tool_manifest.json](HelmTweakPrefs/tool_manifest.json) — 工具清单，每项带 `minIOS` / `maxIOS` / `scheme`（roothide-only 工具标 `"scheme":"roothide"`）。
  - [HelmTweakPrefs.mm](HelmTweakPrefs.mm) — Root 面板 append 工具箱列表，按 `[HelmSystemInfo iOSMajorVersion]` + `isRootless` 灰掉不兼容 cell（标注"需要 iOS X+"/"需要 roothide 环境"）。
  - 根 [Makefile](Makefile) — `HelmTweakPrefs_CFLAGS/LDFLAGS` 链接 HelmCore.dylib + `-I.../SDK`。
- **step 4 变更**：
  - [tools/mcp/MCPServer.m](tools/mcp/MCPServer.m) — `#import <HelmCore/HelmCore.h>`，调用换成 `[HelmScreenManager sharedInstance]` / `[HelmOCRManager sharedInstance]`。
  - 删掉 [tools/mcp/ScreenManager.h](tools/mcp/ScreenManager.h) / `.m` 和 [tools/mcp/OCRManager.h](tools/mcp/OCRManager.h) / `.m`（被 HelmCore 版取代）。
  - 根 [Makefile](Makefile) — `HelmMCP_CFLAGS += -I$(THEOS_PROJECT_DIR)/SDK`，`HelmMCP_LDFLAGS` 链接 `SDK/HelmCore/.theos/obj/HelmCore.dylib`。
- **新文件（step 3）**：
  - [SDK/HelmCore/System/HelmLogger.h](SDK/HelmCore/System/HelmLogger.h) / [.m](SDK/HelmCore/System/HelmLogger.m) — 最小日志器（NSLog + `/var/mobile/Library/Logs/HelmCore/helmcore.log`），debug 开关复用 MCP prefs。
  - [SDK/HelmCore/System/HelmScreenManager.h](SDK/HelmCore/System/HelmScreenManager.h) / [.m](SDK/HelmCore/System/HelmScreenManager.m) — 私有 SB 调用保持软引用，`+isSupportedOnCurrentIOS`。
  - [SDK/HelmCore/System/HelmOCRManager.h](SDK/HelmCore/System/HelmOCRManager.h) / [.m](SDK/HelmCore/System/HelmOCRManager.m) — Vision OCR，支持判断用 runtime `@available`。
- **新文件（step 1-2）**：SDK/HelmCore Makefile（library.mk，dual scheme）+ umbrella HelmCore.h + HelmSystemInfo + Private/HelmPrivateHeaders.h（SpringBoardPrivate.h 已成 shim）。
- **构建接入**：CI 前置 `Build HelmCore SDK library (rootless)`；主 Makefile `after-stage::` 把 HelmCore.dylib 拷进 deb `/usr/lib/`。

## Phase 3 已完成（2026-08-01）

HelmCore SDK 建立 + 全链路接入完成，见上面「当前状态」。

## 下次干啥（候选，挑一个继续）

- **Phase 4 剩余**：把剩下的 MCP Manager 抽进 HelmCore：
  - AppManager（2499 行，重 roothide 逻辑 + SpringBoardPrivate）— 大活，可分拆。
  - AccessibilityManager + MCPAX 栈（AX 树、UI element 序列化，~7000 行）— 最大最难。
  - TextInputManager（依赖 AccessibilityManager.frontmostApplicationInfo，等 AX 先抽）。
  - ClipboardManager / FileSystemManager / LogManager（无私有 API，价值低，可不动）。
- **已抽**：HelmSystemInfo / HelmScreenManager / HelmOCRManager / HelmHIDManager + HelmLogger。
  MCPProcessUtil 的 jbroot/rootfs 已改走 [HelmSystemInfo]，不再直接碰 roothide_shim.h。
- **shim guard 坑**（本轮踩过）：tools/mcp/IOHIDPrivate.h 做 shim 时 guard 不能和 SDK 目标头
  （HelmPrivateHeaders.h / IOHIDPrivate.h）同名，否则 SDK 头整个被跳过 → 类型缺失。shim 用独立 guard。
- **验证**：装机验证 1.0.27 的 prefs 工具箱列表 + HelmMCP 截图/OCR/触摸行为不变（见下「复现部署」）。

## Phase 2c 已完成的 5 个迭代

1. `mcp-logreader` — diagnosticd unified log，rootless+roothide 都 build。
2. `mcp-root` — setuid root 命令白名单，roothide-only + chmod 4755。
3. `mcp-roothelper` — setuid IPA 安装器，roothide-only（依赖 `roothide.h` + libroothide）。
4. `mcp-ldid` — codesign CLI，vendored `libcrypto.a` + `libplist-2.0.a`（ProcursusSDK）。
5. `libzip` vendor — 源码进 [third_party/libzip/](third_party/libzip/)，deflate-only，CI 能 build。`mcp-appinst` 现在 rootless 也 bundle。

### iter 5 撞过的坑（已沉淀到 [memory](C:\Users\Doubl\.claude\projects\x--repo-helmtweak\memory\feedback_theos_action_libzip.md)，简记）

- libzip `zip_random_uwp.c` / `zip_source_file_win32*.c` 要排除（`<windows.h>`）。
- `zip_winzip_aes*.c` / `zip_source_winzip_aes_*.c` 要排除（`#error "no crypto backend found"`，我们没有 crypto backend；caller 都 `#if defined(HAVE_CRYPTO)` 守好，link-safe）。
- `zip_err_str.c` 是 CMake 生成的，源码不带 — 写了 [gen_zip_err_str.py](third_party/libzip/gen_zip_err_str.py)（Python 移植 `GenerateZipErrorStrings.cmake`）。
- Theos `library.mk` 默认只 build dylib，要 `zip_LINKAGE_TYPE = static` 才 emit `.a`。
- mcp-appinst 在 `tools/helpers/mcp-appsync/appinst/`（**4 层深**）→ `../../../../` 才到 repo root；mcp-roothelper / mcp-ldid 在 `tools/helpers/<name>/`（3 层深）→ `../../../`。差一层 CI 才暴露。

## 下次干啥：Phase 3 — HelmCore SDK 层

**目标**：把 HelmMCP 里散在各 Manager 的 iOS 版本/私有 API 调用抽到 `SDK/HelmCore/` dylib，工具层（`tools/*`、`HelmTweakPrefs/`）只走 HelmCore 高层 API，不直接碰私有 header / 版本号 / 私有 selector。

**铁律**（CLAUDE.md 已有，重点重申）：
- 工具层**绝不直接**接触：私有 header、`iOSVersion == 17` 硬编码、`[SBIconController ...]` 直接调、`#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000` 编译期单独分支。
- 一律经 HelmCore：`SDK/HelmCore/Private/HelmPrivateHeaders.h` 集中声明私有 header；`HelmSystemInfo` 暴露 `iOSMajorVersion` / `isRootless` / `jbRootPath` / `+pathFor:`；私有 selector 走 `NSClassFromString` + `NSSelectorFromString` + `dlsym` 软引用，找不到走 capability query 返回 nil/fallback，**绝不 crash**。
- 每个 Manager 暴露 `+ (BOOL)isSupportedOnCurrentIOS`，工具启动先问再做。
- runtime `@available(iOS X, *)` 分派，**不**靠编译期 `#if`。
- 工具 manifest 字段 `minIOS` / `maxIOS`，不兼容的 cell 灰掉。
- fat arm64 + arm64e，rootless 路径自动从 `HelmSystemInfo` 拿。

**起步顺序（建议）**：
1. 建 `SDK/HelmCore/` 目录 + Makefile（Theos `library.mk`，`LIBRARY_NAME = HelmCore`，dual scheme 自适应）。
2. 第一个 Manager 抽 `HelmSystemInfo`（最基础，其他都依赖它）—— 把 [tools/mcp/roothide_shim.h](tools/mcp/roothide_shim.h) 的 `rootfs()` / `jbroot()` 升级成正式 API。
3. 抽 `HelmScreenManager` + `HelmOCRManager`（已有实现，搬 + 加 `+isSupportedOnCurrentIOS` + 把硬编码 iOS 版本分支改成 runtime `@available`）。
4. HelmMCP 各 Manager 改成调用 HelmCore，验证行为不变。
5. 工具 manifest 加 `minIOS` / `maxIOS` 字段，prefs 列表里灰掉不兼容 cell。

## 复现部署（下次直接跑）

```sh
# 1. 拉 CI artifact（gh CLI 已装在 /c/Program Files/GitHub CLI/）
"/c/Program Files/GitHub CLI/gh.exe" run download <run-id> --repo 2637309949/helmtweak -D /tmp/helm_artifact

# 2. deploy 脚本（已存在 deploy_1_0_25.py，下次版本变了改 DEB_LOCAL 路径）
python deploy_1_0_25.py
#   流程：SFTP put deb → dpkg -i → ls 验证 → mcp-appinst 跑一下 → MCP probe
```

## 本地机密文件（均已 .gitignore，**别提交**）

| 文件 | 内容 |
|---|---|
| `token.txt` | GitHub fine-grained PAT（如果还在用 gh CLI 就不需要） |
| `mobile.txt` | 手机 ssh 指令 + test 编译机 sudo 密码 |
| `deploy*.py` | 各版本部署脚本（硬编码手机 IP/pw） |
| `debug*.py` / `diag*.py` / `probe*.py` / `purge*.py` / `fetch*.py` | 临时诊断脚本 |
| `packages/` | 本机 build 的 deb |
| `_diag_binary/` | 反编译产物 |

## 不要做的事

- **不写 spec / 设计文档**（CLAUDE.md 硬约束）。brainstorming 到「present design」就停，用户说 OK 直接 code。
- **不要 bundle rootful scheme**。dual-scheme = rootless + roothide，永远不 ship rootful。
- **不要降 ARCHS**。`arm64 arm64e` 都要。
- **不要手动 `cp dylib` 部署**。CI 是唯一发布渠道。
- **不要碰 `--no-verify` / `--no-gpg-sign`**。
