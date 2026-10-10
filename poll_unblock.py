#!/usr/bin/env python3
"""守候解卡效果：轮询回执页/T-MSP06 + patch-sync 状态。"""
import re, html as H, urllib.request, time, sys, subprocess

UA = {"User-Agent": "Mozilla/5.0"}
V5_SHA = "225a9440335cd5777c80b41e84018ca9478322e5892b698ecd647e2f2dc64df5"


def read_edit(slug, tries=3):
    for _ in range(tries):
        try:
            h = urllib.request.urlopen(urllib.request.Request(
                f"https://rentry.co/{slug}/edit", headers=UA), timeout=40).read().decode("utf-8", "replace")
            m = re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S)
            t = H.unescape(m.group(1)) if m else ""
            if not t:
                i = h.find("<textarea")
                if i >= 0:
                    b = h[i:]; t = H.unescape(b[b.find(">") + 1:])
            if t.strip():
                return t
        except Exception:
            time.sleep(3)
    return ""


def outbox_recs():
    t = read_edit("hermes-rx-r6qytd4")
    return [l for l in t.splitlines() if l.startswith("REC|")], t


deadline = time.time() + 9 * 60
while time.time() < deadline:
    recs, t = outbox_recs()
    ids = [re.search(r"task=([^|]+)", r).group(1) for r in recs if re.search(r"task=([^|]+)", r)]
    new = [i for i in ids if i in ("T-MSP04", "T-MSP05", "T-MSP06")]
    print(time.strftime("%H:%M:%S"), "REC ids:", ids[:8])
    if "T-MSP06" in ids:
        print("\n✅ T-MSP06 已回执 → 循环复活")
        for r in recs:
            if "T-MSP06" in r:
                print(r[:200])
        break
    if "T-MSP04" in ids:
        print("… T-MSP04 出现新回执（解卡后补交付）")
    time.sleep(40)
else:
    print("\n⏳ 9 分钟内未见 T-MSP06 回执")
