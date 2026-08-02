#!/usr/bin/env python3
# Settings UI 自动化测试工具（走 MCP）。
# 用法:
#   python scripts/ui_test.py open-settings          # 启动 Settings 并确认前台
#   python scripts/ui_test.py scroll <dir> <n>       # 滚动：up=往下看列表上面，down=往列表下面
#   python scripts/ui_test.py find <text> [max_pages]
#                                                     # 逐屏滚动找文本，找到返回坐标
#   python scripts/ui_test.py tap <x> <y>            # 点坐标
#   python scripts/ui_test.py ui                     # 打印当前 UI 树（结构化 label）
#   python scripts/ui_test.py ocr                    # 打印当前 OCR 文本
#   python scripts/ui_test.py frontmost              # 前台 app
#   python scripts/ui_test.py mcp-up                 # MCP server 是否在线
#
# 经验（PROGRESS.md 有记录）：
#   - Settings 列表滚动一次一屏(~300点)，不要连滚到底会滑过目标
#   - OCR 中文识别弱，用 ui 拿结构化 label 更可靠
#   - get_ui_elements 偶发超时(AX inactive)，重试 2-3 次
import json
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from device import _load_config

cfg = _load_config()
HOST = cfg["HOST"]


def call(method, params, timeout=60):
    req = urllib.request.Request(
        f"http://{HOST}:8686/mcp",
        data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def tool(name, args, timeout=60):
    d = call("tools/call", {"name": name, "arguments": args}, timeout=timeout)
    r = d.get("result", {})
    if r.get("isError"):
        print(f"[!] {name} ERROR:", json.dumps(r, ensure_ascii=False)[:200])
        return None
    return r


def text(r):
    return r.get("content", [{}])[0].get("text", "") if r else ""


def ocr_items():
    r = tool("ocr_screen", {}, timeout=40)
    if not r:
        return []
    try:
        j = json.loads(text(r))
        return [(t.get("text", ""), t.get("tap", {})) for t in j.get("texts", [])]
    except Exception:
        return []


def ui_items():
    for _ in range(3):
        try:
            r = tool("get_ui_elements", {"maxElements": 80}, timeout=30)
        except Exception:
            r = None
        if r:
            try:
                j = json.loads(text(r))
                return [(e.get("text") or e.get("label") or "", e.get("tap", {}))
                        for e in j.get("elements", [])]
            except Exception:
                pass
        time.sleep(1)
    return []


def frontmost():
    r = tool("get_frontmost_app", {}, timeout=20)
    if not r:
        return "?"
    try:
        return json.loads(text(r)).get("bundleId", "?")
    except Exception:
        return text(r)[:60]


def mcp_up():
    try:
        call("tools/list", {})
        return True
    except Exception:
        return False


def swipe(x1, y1, x2, y2, dur=200):
    tool("swipe_screen", {"fromX": x1, "fromY": y1, "toX": x2, "toY": y2, "duration": dur}, timeout=20)


def find_text(target, max_pages=10, scroll_down=True):
    """逐屏滚动找文本。UI 树优先，OCR 兜底。scroll_down=True 从当前往下滚(看到列表下面)，False 往上滚。"""
    for i in range(max_pages):
        items = ui_items()
        if not items:
            items = ocr_items()
        for t, tap in items:
            if target in t:
                return t, tap, i
        swipe(187, 650 if scroll_down else 300, 187, 300 if scroll_down else 650)
        time.sleep(0.8)
    return None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    cmd = sys.argv[1]

    if cmd == "open-settings":
        tool("launch_app", {"bundle_id": "com.apple.Preferences"}, timeout=30)
        time.sleep(2)
        print("frontmost:", frontmost())
    elif cmd == "scroll":
        # scroll <up|down> <n>
        direction = sys.argv[2] if len(sys.argv) > 2 else "down"
        n = int(sys.argv[3]) if len(sys.argv) > 3 else 1
        for _ in range(n):
            if direction == "up":
                swipe(187, 300, 187, 650)
            else:
                swipe(187, 650, 187, 300)
            time.sleep(0.8)
    elif cmd == "find":
        # find <text> [pages] [up|down]  逐屏滚动查找，默认向下
        target = sys.argv[2]
        pages = int(sys.argv[3]) if len(sys.argv) > 3 else 10
        down = not (len(sys.argv) > 4 and sys.argv[4] == "up")
        found = find_text(target, pages, scroll_down=down)
        if found:
            t, tap, page = found
            print(f"FOUND '{t}' tap=({tap.get('x')},{tap.get('y')}) page={page}")
        else:
            print(f"NOT FOUND '{target}'")
    elif cmd == "tap":
        x, y = float(sys.argv[2]), float(sys.argv[3])
        tool("tap_screen", {"x": x, "y": y})
        print(f"tapped ({x},{y})")
    elif cmd == "ui":
        for t, tap in ui_items():
            if t.strip():
                print(f"  '{t}' tap=({tap.get('x')},{tap.get('y')})")
    elif cmd == "ocr":
        for t, _ in ocr_items():
            if t.strip():
                print(" ", t)
    elif cmd == "frontmost":
        print(frontmost())
    elif cmd == "mcp-up":
        print("MCP up" if mcp_up() else "MCP down")
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
