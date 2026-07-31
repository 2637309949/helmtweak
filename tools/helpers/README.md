# tools/helpers/

通用 HelmTweak CLI 基础设施。forked from `witchan/ios-mcp` (GPL-3.0)，按 `THEOS_PACKAGE_SCHEME` 自适应 rootless / roothide。

每个 helper 自己一个 Makefile，子项目形式（抄上游 build 模式）。主 [Makefile](../../Makefile) 的 `after-stage::` 按 scheme 把 build 好的 binary bundle 进 deb staging。

## 已 fork

| helper | 干嘛 | rootless | roothide |
|---|---|---|---|
| mcp-logreader | 连 diagnosticd 拿 unified log（NDJSON 输出）| ✅ | ✅ |
| mcp-root | setuid root 命令白名单（mcp-roothelper / mcp-appinst / mcp-ldid / chmod / launchctl）| ❌ sandbox 阻止 setuid | ✅ chmod 4755 |

## Phase 2c 后续迭代（deferred）

| helper | 卡在哪 |
|---|---|
| mcp-roothelper | Makefile 引 `../AppSync/appinst/zip.h` + `$(THEOS)/lib/libzip.a`，需先 fork AppSync/appinst 子目录 + 验证 Theos toolchain 是否带 libzip.a |
| mcp-appsync | 26 个文件跨 4 子目录（AppSyncUnified-FrontBoard / AppSyncUnified-installd / appinst / asu_inject）|
| mcp-ldid | Makefile 引 `../third_party/ldid/` (git submodule) + `../third_party/procursus-sdk/` vendored OpenSSL + libplist — 太重 |

## 构建

```bash
# 单独 build 一个 helper（在 helper 目录下）
cd tools/helpers/mcp-logreader
make clean && make THEOS_PACKAGE_SCHEME=rootless
# 或 roothide
make clean && make THEOS_PACKAGE_SCHEME=roothide

# 主项目 build（主 Makefile after-stage 自动 bundle helpers）
make clean && make package THEOS_PACKAGE_SCHEME=rootless
```

## CI 限制

GitHub Actions 用 `Randomblock1/theos-action@v1`，只 clone `theos/theos` + `theos/sdks`，**不包含 `libroothide`**。所以 CI 只 build rootless，roothide 必须在 roothide 越狱设备上本地 build。
