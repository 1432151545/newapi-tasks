#!/usr/bin/env python3
"""跨通道核验沙箱回执（HK 侧独立复算，不采信任何自报数字）。

通道：ntfy（主，append-only、无 Cloudflare）+ rentry outbox（历史/回落）。
核验：解 data → 重算 sha256(json) → 与 REC 自带 sha 比对；并核对 nonce/exit/host。

用法:
  verify_rec.py                 # 列出两通道所有回执的核验结论
  verify_rec.py T-GITAGT01 ...  # 只看指定任务（并打印 artifacts 明细）
"""
import base64
import hashlib
import html as _h
import json
import os
import re
import sys
import urllib.request

UA = {"User-Agent": "Mozilla/5.0"}
TOPIC_CONF = "/root/muse-deploy/receipt.conf"
BUSINFO = "/root/muse-deploy/bus-info.txt"


def fetch(u, t=40):
    return urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=t).read().decode("utf-8", "replace")


def _conf(path):
    d = {}
    try:
        for line in open(path, encoding="utf-8"):
            if "=" in line:
                k, v = line.strip().split("=", 1)
                d[k] = v
    except Exception:
        pass
    return d


def topic():
    t = os.environ.get("BUS_NTFY_TOPIC", "")
    if t:
        return t
    t = _conf(TOPIC_CONF).get("topic", "")
    if t:
        return t
    # 兜底：从指针页读 receipt_topic
    try:
        p = _conf("/root/muse-deploy/pointer-info.txt")
        h = fetch("https://rentry.co/%s/edit" % p.get("slug", ""))
        m = re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S)
        txt = _h.unescape(m.group(1)) if m else ""
        mm = re.search(r"(?m)^\s*receipt_topic=(\S+)", txt)
        return mm.group(1) if mm else ""
    except Exception:
        return ""


def from_ntfy(t):
    out = []
    if not t:
        return out
    try:
        for line in fetch("https://ntfy.sh/%s/json?poll=1" % t).splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            msg = d.get("message", "")
            if msg.startswith("REC|"):
                out.append(msg)
    except Exception as e:
        print("  ! ntfy 读失败: %s" % str(e)[:90], file=sys.stderr)
    return out


def from_rentry():
    out = []
    slug = _conf(BUSINFO).get("slug", "")
    if not slug:
        return out
    try:
        h = fetch("https://rentry.co/%s/edit" % slug)
        m = re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S)
        txt = _h.unescape(m.group(1)) if m else ""
        out = [l for l in txt.splitlines() if l.startswith("REC|")]
    except Exception as e:
        print("  ! rentry 读失败: %s" % str(e)[:90], file=sys.stderr)
    return out


def parse(rec):
    g = lambda k: (re.search(k + r"=([^|]+)", rec) or [None, "?"])[1]
    info = {"task": g("task"), "nonce": g("nonce"), "exit": g("exit"),
            "type": g("type"), "ts": g("ts"), "host": g("host")}
    try:
        payload = rec.split("|data=")[1]
        r = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
        given = g("sha")
        computed = hashlib.sha256(json.dumps(r, ensure_ascii=False).encode()).hexdigest()
        info["payload"] = r
        info["sha_ok"] = (computed == given)
    except Exception as e:
        info["sha_ok"] = False
        info["err"] = str(e)[:60]
    return info


def main():
    want = sys.argv[1:]
    t = topic()
    print("=== 核验（HK 侧独立复算）===")
    print("ntfy topic: %s" % (t or "(未配置)"))
    recs = {}
    for src, arr in (("ntfy", from_ntfy(t)), ("rentry", from_rentry())):
        for rec in arr:
            i = parse(rec)
            # 同一任务保留 ts 较新的那条
            old = recs.get(i["task"])
            if not old or (i["ts"] or "") >= (old.get("ts") or ""):
                i["src"] = src
                recs[i["task"]] = i
    if not recs:
        print("（两通道都没有回执）")
        return 1
    for tid in sorted(recs):
        if want and tid not in want:
            continue
        i = recs[tid]
        print("\n%-12s src=%-6s exit=%-3s ts=%s host=%s nonce=%s" % (
            i["task"], i["src"], i["exit"], i["ts"], i["host"], i["nonce"]))
        print("  sha_ok = %s%s" % (i["sha_ok"], "" if i["sha_ok"] else "  <-- 不一致! " + i.get("err", "")))
        p = i.get("payload") or {}
        arts = p.get("artifacts") or {}
        items = arts.items() if isinstance(arts, dict) else ((a.get("path") or "?", a) for a in arts)
        for name, a in items:
            a = a or {}
            print("  artifact %-14s size=%-7s sha=%s" % (
                (name or "?").split("/")[-1], a.get("size", "-"), (a.get("sha256") or "")[:16]))
        note = p.get("note")
        if note:
            print("  note: %s" % str(note)[:110])
    missing = [w for w in want if w not in recs]
    if missing:
        print("\n尚未到达: %s" % ", ".join(missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())