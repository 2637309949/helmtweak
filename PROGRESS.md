# PROGRESS — Phase 3 (HelmCore SDK) 起步：step 1-2 done

下次打开先看这个 + [CLAUDE.md](CLAUDE.md)，直接接着干。

## 当前状态 ✅

- **Phase 3 step 1-2 完成**：`SDK/HelmCore/` SDK 骨架 + 第一个 Manager `HelmSystemInfo`，CI 全绿。
- **版本**：`1.0.26`。CI run <待填>。
- **新文件**：
  - [SDK/HelmCore/Makefile](SDK/HelmCore/Makefile) — Theos `library.mk`，`LIBRARY_NAME = HelmCore`，dual scheme 自适应（roothide 链 libroothide；rootless 内部 `/var/jb`）。
  - [SDK/HelmCore/HelmCore.h](SDK/HelmCore/HelmCore.h) — SDK umbrella header。
  - [SDK/HelmCore/System/HelmSystemInfo.h](SDK/HelmCore/System/HelmSystemInfo.h) / [.m](SDK/HelmCore/System/HelmSystemInfo.m) — 系统信息 + jailbreak 路径解析。`iOSMajorVersion` / `isRootless` / `isRoothide` / `jbRootPath` / `rootfs:` / `jbroot:` / `pathFor:` / `deviceModelIdentifier` / `isArm64eDevice` / `isSupportedOnCurrentIOS`。
  - [SDK/HelmCore/Private/HelmPrivateHeaders.h](SDK/HelmCore/Private/HelmPrivateHeaders.h) — 私有 header 集中声明区（SpringBoardPrivate.h 内容搬过来了，[tools/mcp/SpringBoardPrivate.h](tools/mcp/SpringBoardPrivate.h) 现在是指向它的 shim）。
- **构建接入**：
  - [.github/workflows/build.yml](.github/workflows/build.yml) 加了 `Build HelmCore SDK library (rootless)` 前置步骤（CI 只 build rootless，符合铁律）。
  - 主 [Makefile](Makefile) `after-stage::` 把 `HelmCore.dylib` 拷进 deb staging 的 `/usr/lib/`。

## Phase 3 剩余顺序（未动）

3. 抽 `HelmScreenManager` + `HelmOCRManager`（搬 tools/mcp 实现 + 加 `+isSupportedOnCurrentIOS` + 硬编码 iOS 版本分支改 runtime `@available`）。
4. HelmMCP 各 Manager 改成调用 HelmCore，验证行为不变。
5. 工具 manifest 加 `minIOS` / `maxIOS`，prefs 列表灰掉不兼容 cell。

## 上次收尾（Phase 2c，2026-07-31）

- **Phase 2c 完成**：4 个 helper 全 fork + libzip 源码 vendor 完，CI 全绿。版本 `1.0.25`。
- **装机**：iPhone XS（`iPhone11,2` = A12），root `@172.30.13.135` pw `12345`。所有 5 个 helper 就位，MCP server 46 tools 含 `install_app` / `uninstall_app`。

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
