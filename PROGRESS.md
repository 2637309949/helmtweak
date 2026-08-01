# PROGRESS — Phase 3 + Phase 4 全部完成 + 装机验证通过（2026-08-01）

下次打开先看这个 + [CLAUDE.md](CLAUDE.md)，直接接着干。

## 当前状态 ✅

- **Phase 3 + Phase 4 全部完成**：HelmCore SDK 建立，HelmMCP 所有私有 API 调用全部抽进 HelmCore，CI 全绿。
- **装机验证通过（2026-08-01 晚）**：1.0.27 部署到 iPhone XS（`172.20.10.6` root/12345），全功能回归 OK。
  - ✅ MCP server 46 tools，install_app/uninstall_app 都在
  - ✅ `get_screen_info` / `screenshot` / `ocr_screen` / `get_ui_elements` / `get_frontmost_app` / `get_device_info` / clipboard / brightness / volume
  - ✅ Settings 点进 HelmTweak 面板正常（不再闪退，见下方坑）
  - ✅ MCP 子面板正常，toggleServer 按钮无崩溃
- **版本**：`1.0.27`。
- **坑（2026-08-01，两次 Preferences 闪退才定位）**：
  - `[PSSpecifier preferenceSpecifierNamed:]` / `groupSpecifierWithName:` / `propertyForKey:` 私有构造 → `___forwarding___` → SIGABRT。
  - 修复：`HelmTweakPrefs.mm` 退化为纯 `loadSpecifiersFromPlistName:`，工具箱灰化改纯静态 plist（`isEnabled=false` + label 标注 roothide-only）。详见 CLAUDE.md gotchas。
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

## 装机验证（2026-08-01 完成）

- 版本 `1.0.27`，CI artifact：`HelmTweak-rootless`。
- 部署工具：`scripts/`（见下方「复现部署」）。
- **已验证**：MCP server 46 tools、截图/OCR/屏幕信息/UI 树/剪贴板/亮度/音量、Settings 面板（HelmTweak 根 + MCP 子面板 + toggle 按钮）。
- **未验证**：真实 tap/swipe 注入（避免误操作），install_app/uninstall_app（无 IPA 在手）。下次上机可补。

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
- mcp-appinst 在 `tools/mcp/helpers/mcp-appsync/appinst/`（**5 层深**）→ `../../../../../` 才到 repo root；mcp-roothelper / mcp-ldid 在 `tools/mcp/helpers/<name>/`（4 层深）→ `../../../../`。差一层 CI 才暴露。

## 复现部署（下次直接跑）

部署脚本在 `scripts/`（gitignored 本地资产，clone 后需重建——布局见下）。手机连接信息在 repo 根 `mobile.txt`（gitignored）。

```sh
# 1. 拉 CI artifact + 装机（用最新成功 run；gh 需要 token.txt）
python scripts/deploy.py            # 或 --deb <path.deb> 用本地 deb
python scripts/deploy.py --respring # 装完 sbreload

# 2. 验证
python scripts/verify.py            # 注入检查 + MCP probe + logreader

# 3. 诊断
python scripts/diag.py log    # 看 /var/mobile/*.log + HelmCore log
python scripts/diag.py prefs  # dump prefs bundle/plist
python scripts/diag.py ps     # 看进程
python scripts/diag.py prep   # 清日志 + kill Preferences/cfprefsd
python scripts/diag.py fetch  # 拉设备二进制到 _diag_binary/
```

`scripts/` 布局（gitignored，如缺失按此重建）：
- `device.py` — 手机连接共享模块，从 `mobile.txt` 读 `HOST/USER/PW`，暴露 `connect()` / `run(c,cmd)`。
- `deploy.py` — artifact 拉取 + SFTP 上传 + `dpkg -i`（含 `--force-depends` fallback）+ 产物列表 + MCP probe。
- `verify.py` — `launchctl procinfo` 注入检查 + mcp-logreader 冒烟 + MCP probe。
- `diag.py` — 日志/prefs/进程/清理/拉二进制子命令。

手机 IP 会随热点/Wi-Fi 环境变化：改 `mobile.txt` 的 `HOST` 即可，脚本无硬编码。

## 本地机密文件（均已 .gitignore，**别提交**）

| 文件 | 内容 |
|---|---|
| `token.txt` | GitHub fine-grained PAT（`gh` CLI 用它） |
| `mobile.txt` | 手机连接信息：`HOST/USER/PW`（`scripts/device.py` 读取） |
| `scripts/` | 本地部署脚本（gitignored，clone 后按上文布局重建） |
| `_diag_binary/` | 反编译产物 |
| `packages/` | 本机 build 的 deb |

## 不要做的事

- **不写 spec / 设计文档**（CLAUDE.md 硬约束）。brainstorming 到「present design」就停，用户说 OK 直接 code。
- **不要 bundle rootful scheme**。dual-scheme = rootless + roothide，永远不 ship rootful。
- **不要降 ARCHS**。`arm64 arm64e` 都要。
- **不要手动 `cp dylib` 部署**。CI 是唯一发布渠道。
- **不要碰 `--no-verify` / `--no-gpg-sign`**。
