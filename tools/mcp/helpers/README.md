# tools/mcp/helpers/

HelmMCP 内部 CLI 基础设施（**不暴露给用户**，被 MCP server 调用）。forked from `witchan/ios-mcp` (GPL-3.0)，按 `THEOS_PACKAGE_SCHEME` 自适应 rootless / roothide。

每个 helper 自己一个 Makefile，子项目形式（抄上游 build 模式）。主 [Makefile](../../../Makefile) 的 `after-stage::` 按 scheme 把 build 好的 binary bundle 进 deb staging。

## 已 fork

| helper | 干嘛 | rootless | roothide |
|---|---|---|---|
| mcp-logreader | 连 diagnosticd 拿 unified log（NDJSON 输出）| ✅ | ✅ |
| mcp-root | setuid root 命令白名单（mcp-roothelper / mcp-appinst / mcp-ldid / chmod / launchctl / dpkg / apt-get）| ❌ sandbox 阻止 setuid | ✅ chmod 4755 |
| mcp-appsync | AppSync Unified dylibs（installd + FrontBoard）—— 注入系统进程做 fakesign 绕过 | ✅ dylib | ✅ dylib |
| mcp-appsync/appinst | 独立 IPA 安装 CLI（zip + LSApplicationWorkspace）| ✅ vendored libzip（deflate-only），CI 能 build | ✅ 同 rootless |
| mcp-roothelper | setuid IPA 安装器（读 IPA bundle id，delegate 给 trollstorehelper 或 mcp-appinst）| ❌ setuid 不可用 + roothide.h 缺失 | ✅ 本地 build + chmod 4755 |
| mcp-ldid | 独立 codesign 替代 CLI（fakesign + 真签名 + plist 签名注入）| ✅ vendored libcrypto.a + libplist-2.0.a，CI 能 build | ✅ 同 rootless |

## mcp-root 白名单（SSH 相关）

SSH 工具（`tools/mcp/SSHManager.m`）经 mcp-root 执行 root 操作，白名单规则：

- **apt-get**：只允许 `install -y <pkg>` / `remove|purge <pkg>`，包名白名单 `{dropbear, openssh-client, openssh-server}`，拒绝其他任何选项/包。对应 `ssh_install`。
- **launchctl**：只允许
  - `print system/<target>`（`ssh_get_status` 查询 daemon 状态）
  - `bootstrap system <sshd-plist>`（`ssh_start`，plist 必须是 `/Library/LaunchDaemons/com.openssh.sshd.plist`）
  - `bootout system/<target>`（`ssh_stop`）
  - `enable|disable system/<target>` + `kickstart -k <target>`（`ssh_set_autostart`）
  - `<target>` 白名单：`system/com.apple.accessibility.AccessibilityUIServer`、`system/com.apple.VoiceOverTouch`、`system/com.openssh.sshd`。
- **dpkg**：已有 install/status/remove/purge 白名单（AppManager 用）。


## Phase 2c 后续迭代（deferred）

无（Phase 2c 完成）。

## 构建

```bash
# 单独 build 一个 helper（在 helper 目录下）
cd tools/mcp/helpers/mcp-logreader
make clean && make THEOS_PACKAGE_SCHEME=rootless
# 或 roothide
make clean && make THEOS_PACKAGE_SCHEME=roothide

# 主项目 build（主 Makefile after-stage 自动 bundle helpers）
make clean && make package THEOS_PACKAGE_SCHEME=rootless
```

## CI 限制

GitHub Actions 用 `Randomblock1/theos-action@v1`，只 clone `theos/theos` + `theos/sdks`，**不包含 `libroothide` 也不带 `$(THEOS)/lib/libzip.a`**。所以：

- CI 只 build rootless，roothide 必须在 roothide 越狱设备上本地 build（roothide 设备的完整 Theos 自带 libzip.a）。
- libzip 改成 vendored 源码（[third_party/libzip/](../../../third_party/libzip/)），deflate-only build，CI 上能 build。mcp-appinst 现在跟 mcp-ldid 一样 rootless 上能 bundle。
- mcp-roothelper 仍是 roothide-only（依赖 `roothide.h` + libroothide + setuid bit）。
