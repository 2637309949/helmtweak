# CLAUDE.md — HelmTweak

Project memory for fast pickup. Read this before touching the build.

## 协作规则（硬约束，优先级最高）

- **不要写设计文档 / spec 文档**：brainstorming 到「present design」一步为止，口述方案给用户，用户说 OK 就直接开始 code。跳过 writing-plans / executing-plans / spec 文档落盘这些步骤。
- 例外：用户明确说「写文档」才写。

## What this project IS (and is NOT)

- A **Theos jailbreak tweak** (Logos) for **Dopamine rootless / ElleKit**.
- Behavior: inject into **SpringBoard**, print `hello` to syslog on respring. No UI. Minimal demo.
- Target devices: A12–A17 (iPhone XS → iPhone 13 Pro Max). Fat **arm64 + arm64e**.
- **NOT** the future `Helm` MCP-smart-terminal project. They share only a naming stem. This repo = `HelmTweak`; the MCP terminal = a separate `helm` repo. Don't conflate.

## Build & run

- Build system: **Theos** (`make`). Requires the iPhoneOS SDK (CI installs 16.5 via theos-action).
- Local macOS build (optional): `brew install ldid dpkg`, have Theos on `$THEOS`, then `make clean && make package`.
- Output: `packages/com.example.helmtweak_<version>_iphoneos-arm64.deb`.
- **CI is the only distribution path.** No phone-side build scripts, no WSL/Linux cross-compile scripts. Don't add them.

## File map

- [Makefile](Makefile) — `TARGET := iphone:clang:16.5:15.0`, `ARCHS = arm64 arm64e`, `THEOS_PACKAGE_SCHEME = rootless` (default; can override to `roothide` for local build on roothide device), `INSTALL_TARGET_PROCESSES = SpringBoard`, `TWEAK_NAME = HelmTweak HelmMCP`, `HelmTweak_ENTITLEMENTS = entitlements.plist`. HelmMCP scheme 自适应段（`ifeq ($(THEOS_PACKAGE_SCHEME),roothide) ... HelmMCP_LIBRARIES = roothide + -DMCP_ROOTHIDE=1`）。`after-stage::` 段把 build 好的 helpers bundle 进 deb staging（rootless 只 bundle mcp-logreader，roothide 还加 mcp-root + chmod 4755）。
- [Tweak.x](Tweak.x) — `%hook SpringBoard` on `applicationDidFinishLaunching:`, `NSLog` hello. ARC on.
- [HelmTweak.plist](HelmTweak.plist) — **filter plist**, `Filter.Bundles = [com.apple.springboard]`. Name MUST equal `TWEAK_NAME`.
- [control](control) — `Package: com.example.helmtweak`, `Architecture: iphoneos-arm64` (rootless fixed field), `Depends: mobilesubstrate`. **Filename is lowercase `control`** (see gotchas).
- [entitlements.plist](entitlements.plist) — `no-sandbox`, `no-container`, `platform-application`. Embedded via `*_ENTITLEMENTS`.
- [.github/workflows/build.yml](.github/workflows/build.yml) — macos-latest, `Randomblock1/theos-action@v1` for env+SDK, helper pre-build step (`make` in each `tools/helpers/<name>/`), then `make clean && make package` at root, then `upload-artifact` of `packages/*.deb`. **Only builds rootless** (theos-action doesn't ship libroothide).
- [tools/mcp/](tools/mcp/) — HelmMCP dylib source（forked from `witchan/ios-mcp`, GPL-3.0）: Tweak.x / MCPServer / 各 Manager / 私有 header / `roothide_shim.h` (rootless 下提供 `rootfs()`/`jbroot()` fallback) / `IOSMCPPreferences.h` (默认端口 8686)。
- [tools/helpers/](tools/helpers/) — 通用 CLI helpers 子项目（每个自己 Makefile，scheme 自适应）：`mcp-logreader/` (连 diagnosticd 拿 unified log，rootless + roothide 都 build)、`mcp-root/` (setuid root 命令白名单，只 roothide build + chmod 4755)。`README.md` 列出 Phase 2c 后续要 fork 的 helper（mcp-roothelper / mcp-appsync / mcp-ldid）+ 各自卡点。
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

- **Filter plist is mandatory.** Theos stage fails with `missing a filter property list` if `HelmTweak.plist` (or `Filter.plist`) is absent. `INSTALL_TARGET_PROCESSES` does NOT replace it — that var only affects the install step.
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

## How to iterate

- **Change behavior:** edit [Tweak.x](Tweak.x) (add `%hook`s on SpringBoard methods). Keep ARC, keep `NSLog` for visibility.
- **Bump version:** edit [control](control) `Version:` (e.g. `1.0.1`). Commit + push → CI re-runs → new deb.
- **Add entitlements:** edit [entitlements.plist](entitlements.plist); Theos embeds automatically.
- **Target another process:** add its bundle id to `Filter.Bundles` in [HelmTweak.plist](HelmTweak.plist), and update `INSTALL_TARGET_PROCESSES` in [Makefile](Makefile).
- After any change: `git add -A && git commit && git push`, then watch https://github.com/2637309949/helmtweak/actions. Red run? paste the failing step's log and fix the offending file.

## CI failure triage (known patterns)

- `missing a filter property list` → filter plist missing/misnamed (see Gotchas).
- `brew install ldid dpkg` fails on macos-latest → tap changed; pin or use `ldid` from theos-action if it pre-installs. Newer theos-action already `brew install ldid make` itself, so the workflow step can be just `brew install dpkg`.
- `Unexpected input(s) 'theos-ref', 'sdk-version', 'sdk-type', 'tweak-package'` → upstream `Randomblock1/theos-action@v1` changed its input contract. New valid inputs are `theos-dir`/`theos-src`/`theos-sdks`/`theos-sdks-branch`/`orion`, all with working defaults (sdks repo default includes iPhoneOS16.5.sdk). Just drop the `with:` block entirely.
- SDK fetch fails → theos-action's sdks repo; check theos/sdks availability.
- deb not found in `packages/*.deb` → build step failed earlier; read full log, not just the upload step.
