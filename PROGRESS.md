# PROGRESS — Phase 3 + Phase 4 全部完成（HelmCore SDK 全量接入）

下次打开先看这个 + [CLAUDE.md](CLAUDE.md)，直接接着干。

## 当前状态 ✅

- **Phase 3 + Phase 4 全部完成**：HelmCore SDK 建立，HelmMCP 所有私有 API 调用全部抽进 HelmCore，CI 全绿。
- **版本**：`1.0.27`。最新 CI run 30680105948。
- **Phase 4 完成（2026-08-01）**：
  - `HelmHIDManager`（touch/button 注入）→ SDK，`HelmCore/Private/IOHIDPrivate.h` 承载 IOHID 私有声明。
  - `AppManager` / `AccessibilityManager` / `MCPAX*` 栈 / `MCPUIElement*` / `TextInputManager` / `MCPProcessUtil` 全部 git mv 进 `SDK/HelmCore/System/`。
  - `AXPrivate.h` → `HelmCore/Private` + shim。
  - 转换：`MCPLogger`→`HelmLogger`；`SpringBoardPrivate`/`AXPrivate`/`IOHIDPrivate` import → `../Private/...`；`MCP_ROOTHIDE`→`HELM_CORE_ROOTHIDE`；`jbroot()`/`rootfs()`→`[HelmSystemInfo ...]`；`IOSMCPPreferences` 域字符串内联。
  - `AppManager`/`AccessibilityManager`/`TextInputManager` 加 `+isSupportedOnCurrentIOS`。
  - `MCPAXNodeSource` 版本判断改走 `[HelmSystemInfo iOSMajorVersion]`。
  - **tools/mcp 现在只剩**：MCPServer + MCPLogger + Clipboard/FileSystem/LogManager（无私有 API 的普通 Manager）。
- **私有 header 全部集中**：`HelmCore/Private/` = HelmPrivateHeaders.h（SB 类）+ AXPrivate.h + IOHIDPrivate.h；tools/mcp 下同名文件全是 shim。
- **坑（本轮踩过）**：
  - **shim guard 不能和 SDK 目标头同名**（否则 SDK 头被跳过）。shim 用独立 guard。
  - **PowerShell `Set-Content` 会弄坏 UTF-8 多字节字符**（`…` U+2026 → 乱码），CI -Werror 报 `missing terminating '"'`。Windows 上不要用 PowerShell 改源码，用 edit 工具或 `git mv` 后按行改。

## Phase 4 剩余

- ClipboardManager / FileSystemManager / LogManager 无私有 API 访问，留在 tools/mcp 即可（低价值不动）。
- roothide 本地 build 验证（CI 只 build rootless）：`make clean && make package THEOS_PACKAGE_SCHEME=roothide`。

## 装机验证

- 版本 `1.0.27`，CI artifact：`HelmTweak-rootless`。
- 验证点：prefs 工具箱列表（含 minIOS/scheme 灰掉）、MCP server 46 tools、截图/OCR/触摸/文本输入、install_app/uninstall_app。

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
