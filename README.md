# HelmTweak

Minimal **Dopamine rootless (ElleKit)** jailbreak tweak demo. Injects into **SpringBoard** and prints a `hello` line to the system log on every respring. No UI. Builds as a fat **arm64 + arm64e** deb covering A12–A17 (iPhone XS → iPhone 13 Pro Max).

> The deb is built entirely in GitHub Actions (macOS cloud) — no local toolchain, no phone-side build scripts. CI output is the **only** distribution channel.

## What it does

On respring, SpringBoard's `applicationDidFinishLaunching:` fires; the Logos hook logs:

```
[HelmTweak] hello! SpringBoard injected on respring (pid=<pid>).
```

View it with `idevicesyslog | grep HelmTweak` (mac, libimobiledevice) or `cat /var/log/syslog` on-device.

## Repo layout

| File | Purpose |
|---|---|
| [Makefile](Makefile) | Theos build config: `TARGET`, `ARCHS=arm64 arm64e`, `THEOS_PACKAGE_SCHEME=rootless`, `INSTALL_TARGET_PROCESSES=SpringBoard`, entitlements binding |
| [Tweak.x](Tweak.x) | Logos source — hooks `-[SpringBoard applicationDidFinishLaunching:]` |
| [HelmTweak.plist](HelmTweak.plist) | **MobileSubstrate filter** — injects the dylib into `com.apple.springboard` |
| [control](control) | deb metadata: package `com.example.helmtweak`, version, description |
| [entitlements.plist](entitlements.plist) | `no-sandbox` / `no-container` / `platform-application`, ldid-embedded into the dylib |
| [.github/workflows/build.yml](.github/workflows/build.yml) | CI: theos-action setup → `make clean && make package` → upload deb artifact |

## Build (local, optional)

macOS with [Theos](https://theos.dev) installed + `brew install ldid dpkg`:

```sh
make clean && make package      # → packages/com.example.helmtweak_*.deb
```

## Build (CI — default path)

1. Push to `main`/`master` → [Actions](https://github.com/2637309949/helmtweak/actions) auto-runs `make clean && make package`.
2. Open the latest `Build Tweak` run → **Artifacts** → download `HelmTweak-rootless` → unzip → `com.example.helmtweak_1.0.0_iphoneos-arm64.deb`.

## Install on device

Dopamine rootless jailbroken iPhone (A12–A17):

1. Transfer the `.deb` to the device.
2. Install via **Filza** or `dpkg -i com.example.helmtweak_*.deb`.
3. `sbreload` (respring) → inject triggers.
4. `idevicesyslog | grep HelmTweak` to see the hello log.

## Notes

- Same deb works across XS → 13 Pro Max. arm64e PAC signing is handled at build time via ldid + the embedded entitlements; no per-device "玄学".
- This is a jailbreak demo repo, **not** the future `Helm` MCP-smart-terminal project — they share a naming stem only.

## License

MIT (demo). Third-party tooling (Theos, ElleKit, Dopamine, theos-action) under their own licenses.
