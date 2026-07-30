# PROGRESS — 2026-07-31 截止点

明天打开先看这个 + [CLAUDE.md](CLAUDE.md)，直接接着干。

## 已完成 ✅

- **工程**：Theos rootless (ElleKit) tweak demo `HelmTweak`，5 文件 + filter plist + README/CLAUDE。
- **CI**：GitHub Actions (`theos-action@v1`, macos-latest) 全绿，产出 deb 作为 artifact `HelmTweak-rootless`。
- **命名坑修复**：`Control` → 小写 `control`（Theos `deb.mk` 大小写敏感 + GitHub macos runner 大小写敏感 FS）。已沉淀进 [CLAUDE.md](CLAUDE.md) Gotchas。
- **远程**：https://github.com/2637309949/helmtweak （`main`，commit `edd82c4` 起的工程文件已推；`.gitignore`/本进度待提交）。
- **装机**：deb 已装到 iPhone XS（机型 `iPhone11,2` = A12，目标范围内）。
  - 安装：`dpkg -i` rc=0，包 `com.example.helmtweak 1.0.0-1+debug` setup 成功，Sileo triggers 跑了。
  - 文件就位：`/var/jb/Library/MobileSubstrate/DynamicLibraries/HelmTweak.dylib`(166KB) + `HelmTweak.plist`(420B)。
  - respring：`sbreload` 成功，SpringBoard 重启（pid 2752，as mobile）。

## 当前卡点 ⚠️（明天第一件事）

**hello log 没在设备上读到——但不是 hook 没触发，是 iOS 没有 `log` CLI。**

- iOS 没有 macOS 的 `/usr/bin/log`（`log` 在设备 zsh 里是 shell 内建，不是那个工具），`log show` 在设备上不存在。
- NSLog 走 unified logging，设备端默认读不到；常规做法是 **Mac 端 `idevicesyslog`**（本机未装）。
- 当前 deb 只 `NSLog`，没有写文件，所以设备上没法 `cat` 验证。

## 明天的下一步（二选一，推荐 A）

### A. 改 tweak 写文件（推荐，最稳、可复现）
1. 改 [Tweak.x](Tweak.x)：`applicationDidFinishLaunching:` 里除了 `NSLog`，再 append 一行到 `/var/mobile/helmtweak.log`（dylib 带 no-sandbox/no-container，能写）。
2. `git push` → CI 重建 → 用 [token.txt](token.txt) 拉 artifact → 跑 [deploy.py](deploy.py) → `cat /var/mobile/helmtweak.log` 见 hello。闭环。

### B. Mac 端读 unified log
- 装 `idevicesyslog`（libimobiledevice）或 `pymobiledevice3`（`pip install pymobiledevice3`），连手机抓 syslog 过滤 `HelmTweak`。不用改 deb，但跨网络（手机在热点 172.20.10.6）抓 lockdown/syslog_relay 不一定通，可能要 USB。

## 本地机密文件（均已 .gitignore，别提交）

| 文件 | 内容 |
|---|---|
| `token.txt` | GitHub fine-grained PAT（Actions/Contents read on helmtweak）|
| `mobile.txt` | 手机 ssh 指令 |
| `deploy.py` | 部署脚本（硬编码 172.20.10.6 root/12345）|
| `helmtweak.deb` | 本机下载的 deb 副本 |

手机：`root@172.20.10.6` 密码 `12345`（也 `mobile/12345`，但 dpkg 要 root）。

## 复现部署（明天直接跑）

```sh
# 拉 artifact（artifact id 会变，先 list 再下）
TOKEN=$(cat token.txt)
curl -sL -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/repos/2637309949/helmtweak/actions/artifacts"   # 取最新 id
# 下 zip → 解出 deb → cp 到 ./helmtweak.deb → python deploy.py
```

`deploy.py` 流程：SFTP 推 deb → `dpkg -i` → `sbreload` → 重连读 log（**注意：当前 deploy.py 用 `/usr/bin/log show`，设备上不存在，明天按方案 A 改成 `cat /var/mobile/helmtweak.log`**）。
