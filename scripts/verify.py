#!/usr/bin/env python3
# 装机验证：检查 dylib 注入 + MCP server + helpers。
#   python scripts/verify.py
#   python scripts/verify.py --probe-only
import argparse
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from device import connect, run, _load_config

cfg = _load_config()
HOST = cfg["HOST"]


def pidof(c, name):
    rc, out, err = run(c, f"ps ax | grep -E '/{name}( |$)' | grep -v grep | head -1 | sed 's/^ *//' | cut -d' ' -f1", timeout=15)
    return out.strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--probe-only", action="store_true", help="只 probe MCP server")
    args = ap.parse_args()

    c = connect()
    print(f"[*] connected {HOST}")

    if not args.probe_only:
        print("--- /var/jb/usr/bin/mcp-* + HelmCore ---")
        rc, out, err = run(c, "ls -la /var/jb/usr/bin/mcp-* /var/jb/usr/lib/HelmCore.dylib 2>&1")
        print(out, err)

        print("\n--- mcp-logreader run (1s test) ---")
        rc, out, err = run(c, "/var/jb/usr/bin/mcp-logreader --seconds 1 --max-lines 3 2>&1 | head -10")
        print(out, err)

        print("\n--- dyld injection (launchctl procinfo) ---")
        for proc in ["SpringBoard", "installd", "backboardd", "runningboardd"]:
            pid = pidof(c, proc)
            if not pid:
                print(f"{proc}: not running")
                continue
            rc, out, err = run(c, f"/var/jb/usr/bin/launchctl procinfo {pid} 2>&1", timeout=20)
            lines = [l for l in out.splitlines() if any(k in l.lower() for k in ["mcp-appsync", "helmtweak", "helmmcp", "helmcore"])]
            if lines:
                print(f"=== {proc} pid={pid} ===")
                for l in lines[:10]:
                    print("  ", l)
            else:
                print(f"{proc} pid={pid}: (no helm dylib lines)")

    print("\n--- MCP :8686 probe ---")
    try:
        req = urllib.request.Request(
            f"http://{HOST}:8686/mcp",
            data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}).encode(),
            headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=8) as r:
            d = json.loads(r.read())
            tools = d.get("result", {}).get("tools", [])
            install = [t for t in tools if "install" in t.get("name", "").lower()]
            print(f"[*] MCP server up, {len(tools)} tools")
            print(f"    install-related: {[t['name'] for t in install]}")
    except Exception as e:
        print(f"[!] MCP probe failed: {e}")

    c.close()


if __name__ == "__main__":
    main()
