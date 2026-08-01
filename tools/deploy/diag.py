#!/usr/bin/env python3
# 诊断工具：日志、prefs bundle、进程、拉取设备二进制。
#   python tools/deploy/diag.py log              # 看 /var/mobile/*.log
#   python tools/deploy/diag.py prefs            # dump prefs bundle + plist
#   python tools/deploy/diag.py ps               # 看关键进程
#   python tools/deploy/diag.py prep             # 清日志 + kill Settings/cfprefsd
#   python tools/deploy/diag.py fetch --out DIR  # 拉 HelmTweakPrefs 二进制
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from device import connect, run


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["log", "prefs", "ps", "prep", "fetch"])
    ap.add_argument("--out", default="_diag_binary", help="fetch 输出目录")
    args = ap.parse_args()

    c = connect()

    if args.cmd == "log":
        rc, out, err = run(c, "ls -la /var/mobile/helmtweak_prefs.log /var/mobile/helmtweak.log /var/mobile/Library/Logs/HelmCore/helmcore.log 2>&1; echo '---'; tail -n 50 /var/mobile/helmtweak_prefs.log /var/mobile/helmtweak.log /var/mobile/Library/Logs/HelmCore/helmcore.log 2>&1")
        print(out, err)

    elif args.cmd == "prefs":
        rc, out, err = run(c, "ls -la /var/jb/Library/PreferenceBundles/HelmTweakPrefs.bundle/ 2>&1; echo '--- MCP.plist ---'; cat /var/jb/Library/PreferenceBundles/HelmTweakPrefs.bundle/MCP.plist 2>&1; echo '--- entry ---'; cat /var/jb/Library/PreferenceLoader/Preferences/HelmTweakPrefs.plist 2>&1")
        print(out, err)

    elif args.cmd == "ps":
        rc, out, err = run(c, "ps ax 2>&1 | grep -iE 'SpringBoard|installd|backboard|runningboard|Preferences' | grep -v grep")
        print(out, err)

    elif args.cmd == "prep":
        rc, out, err = run(c, "rm -f /var/mobile/helmtweak_prefs.log /var/mobile/helmtweak.log; rm -f /var/mobile/Library/Logs/HelmCore/helmcore.log; killall -9 Preferences 2>&1; killall -9 cfprefsd 2>&1; sleep 1; echo done")
        print(out, err)

    elif args.cmd == "fetch":
        os.makedirs(args.out, exist_ok=True)
        sftp = c.open_sftp()
        remote = "/var/jb/Library/PreferenceBundles/HelmTweakPrefs.bundle/HelmTweakPrefs"
        local = os.path.join(args.out, "HelmTweakPrefs")
        try:
            sftp.get(remote, local)
            print(f"[*] fetched {remote} -> {local} ({os.path.getsize(local)} bytes)")
        except Exception as e:
            print(f"[!] fetch failed: {e}")
        sftp.close()

    c.close()


if __name__ == "__main__":
    main()
