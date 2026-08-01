#!/usr/bin/env python3
# 手机连接共享配置。所有 deploy/verify/probe/diag 脚本从这里拿手机信息。
# 手机信息放在 repo 根 mobile.txt（已 gitignore，不提交），格式：
#   每行 key=value，支持 HOST / USER / PW
import os
import paramiko

CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "mobile.txt")


def _load_config():
    cfg = {}
    path = CONFIG_PATH
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                cfg[k.strip().upper()] = v.strip()
    required = {"HOST", "USER", "PW"}
    missing = required - set(cfg.keys())
    if missing:
        raise RuntimeError(
            f"mobile.txt 缺失/不全: {sorted(missing)}。请创建 repo 根 mobile.txt:\n"
            "  HOST=<手机 IP>\n  USER=root\n  PW=<密码>")
    return cfg


def connect():
    cfg = _load_config()
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(cfg["HOST"], 22, cfg["USER"], cfg["PW"], timeout=10,
              allow_agent=False, look_for_keys=False)
    return c


def run(c, cmd, timeout=60):
    _, o, e = c.exec_command(cmd, timeout=timeout)
    out = o.read().decode(errors="replace")
    err = e.read().decode(errors="replace")
    rc = o.channel.recv_exit_status()
    return rc, out, err
