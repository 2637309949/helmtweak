# CLAUDE.md — HelmTweak

Project memory for fast pickup. Read this before touching the build.

## 协作规则（硬约束，优先级最高）

- **不要写设计文档 / spec 文档**：brainstorming 到「present design」一步为止，口述方案给用户，用户说 OK 就直接开始 code。跳过 writing-plans / executing-plans / spec 文档落盘这些步骤。
- 例外：用户明确说「写文档」才写。
- **手机/截图/OCR/部署/诊断一律优先用 `scripts/` 下现有脚本**（`deploy.py`/`verify.py`/`diag.py`/`mcp.py`/`ui_test.py`/`ocr.bat`）。没有对应脚本就新建到 `scripts/`，不要每次临时写内联 python/ps1（PowerShell 引号转义坑多、且无法复用）。

## What this project IS (and is NOT)

- A **Theos jailbreak tweak** (Logos) for **Dopamine rootless / ElleKit**.
- Behavior: inject **HelmMCP** into **SpringBoard**, runs an MCP server (`:8686`) that lets AI control the phone (screenshot/OCR/touch/text/app mgmt/filesystem).
- Target devices: A12–A17 (iPhone XS → iPhone 13 Pro Max). Fat **arm64 + arm64e**.
- **NOT** the future `Helm` MCP-smart-terminal project. They share only a naming stem. This repo = `HelmTweak`; the MCP terminal = a separate `helm` repo. Don't conflate.

## Directory layering (新文件别放错层)

- `SDK/HelmCore/` = **SDK 层**（跨应用复用 dylib + 私有 header 集中声明）。
- `tools/` = **应用层**。目前有 `tools/mcp/`（用户可用的 MCP 工具）和其内部 `tools/mcp/helpers/`（MCP 的后端 CLI，不暴露给用户），以及 `tools/ssh/`（独立系统工具：OpenSSH 生命周期管理，经 Settings -> SSH 面板 + darwin 事件驱动，不注册为 MCP 工具）。
- `scripts/` = **开发工具链**（部署/验证/诊断，不进 deb）。不参与打包。
- `third_party/` = **vendored 构建依赖**（第三方源码/静态库，如 ldid/libzip/procursus-sdk，只被 helpers 链接，参与编译不进 deb 安装）。
- **新增规则**：用户可见的"工具"出现在 `tools/` 下各自独立目录（`tools/mcp/`、`tools/ssh/`），**MCP server 只注册 AI 可操作的工具，系统管理类工具（如 SSH）独立成 `tools/<name>/`，不混进 MCP tools 列表**；CLI helper 一律放 `tools/mcp/helpers/`；部署/诊断脚本放 `scripts/`；跨应用能力放 `SDK/HelmCore/`；第三方 vendored 依赖放 `third_party/`。

## Build & run

- Build system: **Theos** (`make`). Requires the iPhoneOS SDK (CI installs 16.5 via theos-action).
- Local macOS build (optional): `brew install ldid dpkg`, have Theos on `$THEOS`, then `make clean && make package`.
- Output: `packages/com.example.helmtweak_<version>_iphoneos-arm64.deb`.
- **CI is the only distribution path.** No phone-side build scripts, no WSL/Linux cross-compile scripts. Don't add them.

## Deploy to phone (装机)

- Phone: root SSH. **Connection info lives in `mobile.txt`** (gitignored, never commit): `HOST=…`, `USER=root`, `PW=…`. `scripts/device.py` 读取（缺失即报错，无默认密码）。
- Deploy scripts are in `scripts/`（已纳入 git；`mobile.txt` 和 `scripts/_artifact|_shots|__pycache__` gitignored）:
  - `python scripts/deploy.py` — pull latest CI artifact (needs `gh` + `token.txt`) OR `--deb <path>` to use a local deb; upload via SFTP, `dpkg -i` (with `--force-depends` fallback), list bundled binaries, probe MCP `:8686`; `--respring` to `sbreload` after install.
  - `python scripts/verify.py` — check dylib injection (`launchctl procinfo` on SpringBoard/installd/backboardd), mcp-logreader smoke run, MCP probe.
  - `python scripts/diag.py <log|prefs|ps|prep|fetch>` — read `/var/mobile/*.log` + `HelmCore/helmcore.log`, dump prefs bundle/plist, list processes, clear logs + `killall Preferences/cfprefsd`, fetch device binary.
  - `python scripts/mcp.py tools/call --name <tool> [--args '{"k":v}']` — 直接调手机 MCP server 工具（截图/OCR/UI 树等），图片存 `scripts/_shots/`。
  - `python scripts/ui_test.py <open-settings|scroll|find|tap|ui|ocr|frontmost|mcp-up>` — Settings 界面自动化测试（走 MCP），**UI 操作优先用它，不要每次新建临时脚本**。
- All deploy scripts read phone info from `mobile.txt` via `scripts/device.py` — no hardcoded IP/pw in scripts.

## File map

- [Makefile](Makefile) — `TARGET := iphone:clang:16.5:15.0`, `ARCHS = arm64 arm64e`, `THEOS_PACKAGE_SCHEME = rootless` (default; can override to `roothide` for local build on roothide device), `INSTALL_TARGET_PROCESSES = SpringBoard`, `TWEAK_NAME = HelmMCP`, `HelmMCP_ENTITLEMENTS = tools/mcp/entitlements.plist`. HelmMCP scheme 自适应段（`ifeq ($(THEOS_PACKAGE_SCHEME),roothide) ... HelmMCP_LIBRARIES = roothide + -DMCP_ROOTHIDE=1`）。`after-stage::` 段把 build 好的 helpers bundle 进 deb staging（rootless 只 bundle mcp-logreader，roothide 还加 mcp-root + chmod 4755）。
- [tools/mcp/Tweak.x](tools/mcp/Tweak.x) — HelmMCP 入口：`%hook SpringBoard` autostart MCP server + 监听 darwin notification（Settings 开关）。ARC on.
- [HelmMCP.plist](HelmMCP.plist) — **filter plist**, `Filter.Bundles = [com.apple.springboard]`. Name MUST equal `TWEAK_NAME`.
- [control](control) — `Package: com.example.helmtweak`, `Architecture: iphoneos-arm64` (rootless fixed field), `Depends: mobilesubstrate`. **Filename is lowercase `control`** (see gotchas).
- [.github/workflows/build.yml](.github/workflows/build.yml) — macos-latest, `Randomblock1/theos-action@v1` for env+SDK, helper pre-build step (`make` in each `tools/mcp/helpers/<name>/`), then `make clean && make package` at root, then `upload-artifact` of `packages/*.deb`. **Only builds rootless** (theos-action doesn't ship libroothide).
- [tools/mcp/](tools/mcp/) — **应用层**。HelmMCP dylib source（forked from `witchan/ios-mcp`, GPL-3.0）: Tweak.x / MCPServer / 各 Manager / `IOSMCPPreferences.h` (默认端口 8686)。**用户可用的"工具"就是这里的 MCP**。
- [tools/mcp/helpers/](tools/mcp/helpers/) — **MCP 内部 CLI 工具**（不暴露给用户，被 MCP server 调用）：每个自己 Makefile，scheme 自适应。`mcp-logreader/` (连 diagnosticd 拿 unified log，rootless + roothide 都 build)、`mcp-root/` (setuid root 命令白名单，只 roothide build + chmod 4755)、`mcp-roothelper/`、`mcp-ldid/`、`mcp-appsync/`。`README.md` 列出 Phase 2c 后续要 fork 的 helper + 各自卡点。
- [tools/ssh/](tools/ssh/) — **独立系统工具**（不注册为 MCP 工具）。OpenSSH 生命周期管理（install/start/stop/autostart），被 Tweak.x 的 darwin SSH 事件 handler 调用（Settings -> SSH 面板驱动）。rootless 下只读可查，roothide 下经 setuid mcp-root 全量可操作。
- [SDK/HelmCore/](SDK/HelmCore/) — **SDK 层**（跨应用复用的 dylib）。私有 header 集中声明 + HelmSystemInfo（路径/版本/scheme）+ Screen/OCR/HID 等 Manager。应用层（tools/*）只经 HelmCore 高层 API 接触系统能力。
- [scripts/](scripts/) — **开发工具链**（部署/验证/诊断/MCP 客户端），不参与打包。
- [HelmTweakPrefs.mm](HelmTweakPrefs.mm) — PreferenceBundle binary; `PSListController` subclass, override `specifiers` with `[self loadSpecifiersFromPlistName:@"Root" target:self]` (see gotchas — two-arg form is load-bearing).
- [MCPPrefsListController.mm](MCPPrefsListController.mm) — MCP 子面板 controller。PSButtonCell + `[spec setName:]` + `[self reload]` 刷新 button title（见 gotchas）。
- [HelmTweakPrefs/Info.plist](HelmTweakPrefs/Info.plist) — bundle metadata, `CFBundleIdentifier = com.example.helmtweakprefs`, `NSPrincipalClass = HelmTweakPrefsListController`. The whole `HelmTweakPrefs/` folder is the bundle resource dir (mapped via `HelmTweakPrefs_RESOURCE_DIRS` in Makefile).
- [HelmTweakPrefs/Root.plist](HelmTweakPrefs/Root.plist) — root panel spec, one `PSGroupCell` + one `PSLinkCell` (`detail = MCPPrefsListController`) routing to MCP subpanel.
- [HelmTweakPrefs/MCP.plist](HelmTweakPrefs/MCP.plist) — MCP subpanel spec: `PSButtonCell` (`action = toggleServer:`, `id = mcpToggleButton`) + port edit + debug switch.
- [layout/Library/PreferenceLoader/Preferences/HelmTweakPrefs.plist](layout/Library/PreferenceLoader/Preferences/HelmTweakPrefs.plist) — Settings root entry; wrapped in `entry` dict with `detail = HelmTweakPrefsListController`.

## Hard constraints (do not regress)

1. `ARCHS = arm64 arm64e` both — never drop one.
2. `THEOS_PACKAGE_SCHEME = rootless | roothide` (dual-scheme support, never rootful) — source + Makefile 自适应，CI 只 ship rootless（theos-action 不带 libroothide），roothide build 在 roothide 设备本地跑。
3. `INSTALL_TARGET_PROCESSES = SpringBoard`.
4. CI runs on **macos-latest**; build command is literally `make clean && make package` (with a pre-step that builds CLI helpers in `tools/helpers/*/`); deb uploaded as a downloadable artifact. CI only ships rootless — roothide build must run on a roothide device (`make clean && make package THEOS_PACKAGE_SCHEME=roothide`).
5. CI-built deb is the sole distribution. No manual `cp dylib/plist` deploy scripts.

### HelmCore SDK 层铁律（跨 iOS 版本支持，不可妥协）

工具层（`tools/*`、`HelmTweakPrefs/`）**绝不直接**接触以下任一项，必须经 HelmCore 暴露的高层 API：

- **私有 header**（`SpringBoardPrivate.h` 等任何 `_` 开头类或 SB 类的私有 selector）→ 经 `SDK/HelmCore/Private/HelmPrivateHeaders.h` 集中声明，由 HelmCore 各 Manager 内部调用。
- **iOS 版本号硬编码**（`if (iOSVersion == 17)` 之类）→ 经 `HelmCore/System/HelmSystemInfo.h` 暴露的 `iOSMajorVersion`/`isRootless`/`jbRootPath` 等查询。所有写死 `/var/jb/...` 路径必须改成 `[HelmSystemInfo pathFor:HelmPathMobileSubstrate]` 之类。
- **私有 class/selector 直接调**（`[SBIconController ...]`）→ 一律走 `NSClassFromString` + `NSSelectorFromString` + `dlsym` 软引用，找不到时走 capability query 返回 nil/fallback，**绝不 crash**。
- **版本分支写死**（`#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 170000` 之类编译期分支单独使用）→ 必须配合 runtime `@available(iOS X, *)` 分派到不同实现方法。SDK 编译目标是多版本 SDK 矩阵（CI 跑 `[15.0, 16.5, 17.0]`），任一 SDK 编译通过即可，但运行时分派必须由 runtime `@available` 决定。

每个 HelmCore Manager 必须暴露 `+ (BOOL)isSupportedOnCurrentIOS`，工具启动先问再做：

```objc
if (![HelmOCRManager isSupportedOnCurrentIOS]) { /* 显示降级提示 */ return; }
UIImage *img = [HelmScreenManager captureScreen];
NSString *text = [HelmOCRManager recognizeTextInImage:img];
```

工具 manifest 字段（每个工具 bundle 的 Info.plist + 远程商店 JSON）必须带 `minIOS` / `maxIOS`，工具箱列表里不兼容当前系统的 cell 灰掉 + 标注"需要 iOS X.Y+"，不可点击。

工具 dylib/bundle 必须能跨 arm64 + arm64e fat，rootless 路径自动从 `HelmSystemInfo` 拿，不假设固定 `/var/jb`。

## Gotchas (we hit these)

- **Filter plist is mandatory.** Theos stage fails with `missing a filter property list` if `HelmMCP.plist` (or `Filter.plist`) is absent. `INSTALL_TARGET_PROCESSES` does NOT replace it — that var only affects the install step.
- Filter plist filename **must equal `TWEAK_NAME`**. If you rename the tweak, rename the plist too.
- `*_ENTITLEMENTS` is a real Theos var — it ldid-signs the dylib with the entitlements at build time. Don't remove it or the dylib won't carry the entitlements.
- **Control file must be lowercase `control`** at project root (or `layout/DEBIAN/control`). Theos `deb.mk` does `$(wildcard $(THEOS_PROJECT_DIR)/control)` — case-sensitive. We shipped `Control` (capital) and it built fine on case-insensitive Windows/local macOS but failed on GitHub's **case-sensitive** macos runner with "requires you to have a control file". If you rename it back to capital C, CI breaks again.
- Rootless deb `Architecture` field is `iphoneos-arm64` regardless of arm64/arm64e fat. Don't "fix" it to arm64e.
- Tweak name `HelmTweak` must stay consistent across: Makefile `TWEAK_NAME`, the `*_FILES`/`*_CFLAGS`/`*_FRAMEWORKS`/`*_ENTITLEMENTS` var prefixes, the filter plist filename, and the Control `Name`. CI artifact name (`HelmTweak-rootless`) is cosmetic and can differ.

### PreferenceBundle gotchas (when adding a Settings panel)

These all bit us on 2026-07-31 while building `HelmTweakPrefs`. Re-deriving them by trial-and-error costs ~6 CI cycles. Just read this first.

- **Theos `bundle.mk` defaults are wrong for PreferenceBundle.** Without overrides, bundle installs to `/var/jb/<Name>.bundle/` (root) and copies no resources. Set both:
  ```makefile
  <BUNDLE_NAME>_INSTALL_PATH = /Library/PreferenceBundles
  <BUNDLE_NAME>_RESOURCE_DIRS = <BUNDLE_NAME>
  ```
  The default `_RESOURCE_DIRS` auto-detect only matches a folder named **`Resources/`**, NOT a folder named after the bundle. We named the resource folder `<BUNDLE_NAME>/` and Theos silently copied nothing → bundle on device had only the binary, no Info.plist, no spec.
- **PSListController `_specifiers` ivar is already declared in the parent header.** Declaring it again in your subclass `@interface { ... }` block triggers `duplicate member '_specifiers'`. Use the inherited ivar directly.
- **`loadSpecifiersFromPlistName:` (single-arg) does NOT exist at runtime** on modern Preferences.framework (iOS 15+). Only the **two-arg** form works:
  ```objc
  _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
  ```
  Declare it via a category on PSListController to satisfy the compiler (the method is private, not in the public header). Velvet2's `Velvet2RootListController.m` uses exactly this pattern — copy-paste it.
- **A category declaration only satisfies the compiler, not the runtime.** If you declare a method that doesn't exist at runtime, expect `doesNotRecognizeSelector:` → `SIGABRT` at the call site. Verify the method exists (check a working open-source tweak like Velvet2 / Choicy) before trusting a category stub.
- **Spec plist filename must be `Root.plist`.** Not `<BundleName>.plist`. PSListController + working bundles (Velvet2/Shadow/SpeedyPref) all use `Root.plist`. Naming it `<BundleName>.plist` results in a blank panel (no spec loaded).
- **Specifier cell type is `PSGroupCell`, not `PSGroupSpecifier`.** The old `PSGroupSpecifier` name is silently ignored on iOS 15+ and renders as nothing → blank section. Use `PSGroupCell`. Other cell types also follow the modern `*Cell` suffix (`PSLinkCell`, `PSSwitchCell`, etc.).
- **PreferenceLoader entry plist (in `layout/Library/PreferenceLoader/Preferences/`) must wrap spec inside an `entry` top-level dict key**, and include `detail` pointing at the PSListController subclass name. Compare with on-device working entries (e.g. `/var/jb/Library/PreferenceLoader/Preferences/ChoicyPrefs.plist` — read with `plistlib`/python; it's binary). Unwrapped spec is invisible to PreferenceLoader 2.2.7.
  ```xml
  <dict>
    <key>entry</key>
    <dict>
      <key>cell</key><string>PSLinkCell</string>
      <key>bundle</key><string>HelmTweakPrefs</string>
      <key>detail</key><string>HelmTweakPrefsListController</string>
      <key>label</key><string>HelmTweak</string>
      <key>isController</key><true/>
    </dict>
  </dict>
  ```
- **iOS device has no `/usr/bin/log` CLI.** Don't put `log show` in deploy scripts or expect to read NSLog output on-device. Use a visible PreferenceBundle panel as the verification surface, or pipe to a file via the dylib (`/var/mobile/helmtweak.log` with no-sandbox entitlement). For prefs controller code, write traces to `/var/mobile/helmtweak_prefs.log` via `NSFileHandle` — same trick, since `NSLog` goes to unified log which has no on-device reader.
- **Settings.app caches specifier list.** After reinstalling a prefs bundle, `killall -9 Preferences` (and optionally `killall -9 cfprefsd`) to force re-scan. `sbreload` alone doesn't always kill Settings. **Critically: if you deployed a new controller class with new action selectors but Settings is still running with the OLD controller cached, taps will silently fail** (action selector doesn't resolve, no crash, no visible response). Always kill Settings after deploying a prefs bundle change.
- **PSSwitchCell on iOS 15+ does NOT call its `action:` selector reliably.** We tried `setMCPEnabled:` (1.0.13), `setEnabled:` auto-derive (1.0.16) — neither fired. Switch to **PSButtonCell with `action: toggleServer:`** which reliably fires. This is the witchan/ios-mcp working pattern.
- **PSButtonCell title refresh: use `[spec setName:]` + `[self reload]`, NOT `setProperty:forKey:@"label"`.** `setProperty:forKey:@"label"` writes to the specifier's internal properties dict, but PSButtonCell reads its title from `specifier.name`. `[self reloadSpecifier:spec animated:YES]` also doesn't force the title to redraw on iOS 15+. Result: `toggleServer:` fires, darwin notification posts, server actually starts (probe confirms), but button text visually stays at the plist default forever. Fix: declare `- (void)setName:(NSString *)name` on PSSpecifier via private category, call `[spec setName:@"新文字"]` then `[self reload]` (whole-table rebuild). Verified working in 1.0.19.
- **Don't dynamically construct PSSpecifier at all — Settings crashes.** `[PSSpecifier preferenceSpecifierNamed:target:set:get:detail:cell:edit:]`, `[PSSpecifier groupSpecifierWithName:]`, and `[spec propertyForKey:]` are private APIs that trigger `___forwarding___` → `_copyDescription` → `SIGABRT` on iOS 15+ (hit 2026-08-01: two Preferences crash loops, both `-[HelmTweakPrefsListController …]` in `lastExceptionBacktrace`). Even calling them inside `specifiers`/`viewDidLoad` crashes. **Only `[self loadSpecifiersFromPlistName:target:]` + plist-defined cells are safe.** `[spec setName:]` and `[spec setEnabled:]` work (setName: verified in 1.0.19), but reading specifier identity back (id/property) crashes — instead, encode all state statically in the plist (`isEnabled`, label text).

## How to iterate

- **Change behavior:** edit [tools/mcp/Tweak.x](tools/mcp/Tweak.x) (add `%hook`s on SpringBoard methods) or [MCPServer.m](tools/mcp/MCPServer.m) (add MCP tools). Keep ARC, keep `NSLog` for visibility.
- **Bump version:** edit [control](control) `Version:` (e.g. `1.0.1`). Commit + push → CI re-runs → new deb.
- **Add entitlements:** edit [entitlements.plist](entitlements.plist); Theos embeds automatically.
- **Target another process:** add its bundle id to `Filter.Bundles` in [HelmMCP.plist](HelmMCP.plist), and update `INSTALL_TARGET_PROCESSES` in [Makefile](Makefile).
- After any change: `git add -A && git commit && git push`, then watch https://github.com/2637309949/helmtweak/actions. Red run? paste the failing step's log and fix the offending file.

## CI failure triage (known patterns)

- `missing a filter property list` → filter plist missing/misnamed (see Gotchas).
- `brew install ldid dpkg` fails on macos-latest → tap changed; pin or use `ldid` from theos-action if it pre-installs. Newer theos-action already `brew install ldid make` itself, so the workflow step can be just `brew install dpkg`.
- `Unexpected input(s) 'theos-ref', 'sdk-version', 'sdk-type', 'tweak-package'` → upstream `Randomblock1/theos-action@v1` changed its input contract. New valid inputs are `theos-dir`/`theos-src`/`theos-sdks`/`theos-sdks-branch`/`orion`, all with working defaults (sdks repo default includes iPhoneOS16.5.sdk). Just drop the `with:` block entirely.
- SDK fetch fails → theos-action's sdks repo; check theos/sdks availability.
- deb not found in `packages/*.deb` → build step failed earlier; read full log, not just the upload step.
