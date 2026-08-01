#!/usr/bin/env python3
# MCP server 客户端 helper：调 tools/call / tools/list，带 base64 图片解码到本地。
# 用法:
#   python scripts/mcp.py tools/list
#   python scripts/mcp.py tools/call --name screenshot
#   python scripts/mcp.py tools/call --name tap_screen --args '{"x":100,"y":100}'
#   python scripts/mcp.py tools/call --name ocr_screen
import argparse
import base64
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from device import _load_config

cfg = _load_config()
HOST = cfg["HOST"]
PORT = 8686


def call(method, params, timeout=60):
    req = urllib.request.Request(
        f"http://{HOST}:{PORT}/mcp",
        data=json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def extract_text_content(result):
    """把 content 数组里的 text + base64 image 提取出来，图片存本地返回路径。"""
    out = []
    saved = []
    content = result.get("content", [])
    for item in content:
        if item.get("type") == "text":
            out.append(item["text"])
        elif item.get("mimeType", "").startswith("image/"):
            data = item.get("data")
            if data:
                ext = "jpg" if "jpeg" in item["mimeType"] else "png"
                path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_shots", f"shot_{len(saved)}.{ext}")
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(base64.b64decode(data))
                saved.append(path)
    return "\n".join(out), saved


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("method", choices=["tools/list", "tools/call"])
    ap.add_argument("--name", help="tools/call 的工具名")
    ap.add_argument("--args", default="{}", help="tools/call 的 JSON 参数")
    args = ap.parse_args()

    if args.method == "tools/list":
        d = call("tools/list", {})
        tools = d.get("result", {}).get("tools", [])
        for t in tools:
            print(t["name"])
        return

    if args.method == "tools/call":
        params = json.loads(args.args)
        d = call("tools/call", {"name": args.name, "arguments": params})
        result = d.get("result", {})
        if "isError" in result and result["isError"]:
            print("ERROR:", json.dumps(result, ensure_ascii=False)[:500])
            return
        text, shots = extract_text_content(result)
        if text.strip():
            print(text)
        for s in shots:
            print(f"\n[img] {s}")
        structured = result.get("structuredContent")
        if structured:
            print("\n[structured]", json.dumps(structured, ensure_ascii=False)[:800])


if __name__ == "__main__":
    main()
