#!/usr/bin/env python3
# 部署 HelmTweak deb 到越狱手机：从 CI artifact（或本地路径）上传 + dpkg -i + 验证。
# 用法:
#   python scripts/deploy.py                    # 用 CI 最新 artifact
#   python scripts/deploy.py --deb <path.deb>   # 用本地 deb
# 手机信息读 repo 根 mobile.txt（gitignore），缺省 HOST=172.20.10.6 root/12345
import argparse
import json
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from device import connect, run, _load_config

cfg = _load_config()
HOST = cfg["HOST"]


def fetch_latest_artifact(dest_dir):
    """用 gh CLI 拉最新 CI artifact（HelmTweak-rootless）。"""
    os.makedirs(dest_dir, exist_ok=True)
    # 找最新一次成功 run 的 id
    import subprocess
    token_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "token.txt")
    env = dict(os.environ)
    if os.path.exists(token_file):
        env["GH_TOKEN"] = open(token_file, "r", encoding="utf-8").read().strip()
    gh = r"C:\Program Files\GitHub CLI\gh.exe" if os.name == "nt" else "gh"
    out = subprocess.run(
        [gh, "run", "list", "--repo", "2637309949/helmtweak", "--status", "success",
         "--limit", "1", "--json", "databaseId,headBranch"],
        capture_output=True, text=True, env=env).stdout
    try:
        run_id = json.loads(out)[0]["databaseId"]
    except Exception as e:
        print(f"[!] 找不到 CI run: {e}\n{out}")
        return None
    print(f"[*] 拉取 CI run {run_id} artifact...")
    subprocess.run([gh, "run", "download", str(run_id), "--repo", "2637309949/helmtweak",
                    "-D", dest_dir], check=True, env=env)
    for root, _, files in os.walk(dest_dir):
        for f in files:
            if f.endswith(".deb"):
                return os.path.join(root, f)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--deb", help="本地 deb 路径（缺省用 CI artifact）")
    ap.add_argument("--respring", action="store_true", help="安装后 sbreload")
    ap.add_argument("--remove-old", help="安装前先 dpkg -r 卸载旧包（包 ID 改名时用），失败忽略")
    args = ap.parse_args()

    deb_local = args.deb
    if not deb_local:
        deb_local = fetch_latest_artifact(os.path.join(os.path.dirname(os.path.abspath(__file__)), "_artifact"))
        if not deb_local:
            print("[!] 没找到 deb")
            sys.exit(1)
    print(f"[*] deb: {deb_local}")

    deb_remote = "/tmp/helmtweak.deb"
    c = connect()
    print(f"[*] connected {HOST}")

    if args.remove_old:
        rc, out, err = run(c, f"/var/jb/usr/bin/dpkg -r {args.remove_old} 2>&1; echo 'rc=$?'", timeout=60)
        print(f"--- dpkg -r {args.remove_old} ---\n{out}\n{err}")

    sftp = c.open_sftp()
    sftp.put(deb_local, deb_remote)
    size = sftp.stat(deb_remote).st_size
    sftp.close()
    print(f"[*] uploaded {size} bytes -> {deb_remote}")

    rc, out, err = run(c, f"/var/jb/usr/bin/dpkg -i {deb_remote}", timeout=60)
    print(f"\n--- dpkg -i rc={rc} ---\n{out}\n{err}")
    if rc != 0:
        rc, out, err = run(c, f"/var/jb/usr/bin/dpkg --force-depends -i {deb_remote}", timeout=60)
        print(f"--- dpkg --force-depends rc={rc} ---\n{out}\n{err}")

    print("\n--- bundled binaries ---")
    rc, out, err = run(c, "ls -la /var/jb/usr/bin/mcp-* /var/jb/Library/MobileSubstrate/DynamicLibraries/mcp-appsync-*.dylib /var/jb/usr/lib/HelmCore.dylib 2>&1")
    print(out, err)

    if args.respring:
        print("[*] sbreload...")
        run(c, "nohup /var/jb/usr/bin/sbreload >/dev/null 2>&1 &", timeout=5)
        c.close()
        time.sleep(15)
        c = connect()

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
    print("[*] done")


if __name__ == "__main__":
    main()
