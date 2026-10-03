#!/usr/bin/env python3
"""打印指定任务回执的 artifact 全文（HK 侧核验用）。
用法: show_rec.py T-MSP04 [--full]"""
import base64
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("vr", "/root/gitbus-tasks/verify_rec.py")
vr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vr)

want = sys.argv[1] if len(sys.argv) > 1 else None
limit = 4000 if "--full" not in sys.argv else 200000

hit = [vr.parse(r) for r in vr.from_rentry()]
print("回写页 task 列表:", [h.get("task") for h in hit])
sel = [h for h in hit if (want is None or h.get("task") == want)]
for i in sel:
    print("\n=== %s exit=%s host=%s ts=%s sha_ok=%s ===" % (
        i.get("task"), i.get("exit"), i.get("host"), i.get("ts"), i.get("sha_ok")))
    p = i.get("payload") or {}
    for name, a in vr._norm_arts(p.get("artifacts")):
        b = a.get("b64") or ""
        if not b:
            print("--- artifact %s (no inline payload; path=%s sha=%s) ---" % (
                (name or "?").split("/")[-1], a.get("path", "-"), (a.get("sha256") or "")[:16]))
            continue
        raw = base64.urlsafe_b64decode(b + "=" * (-len(b) % 4)).decode("utf-8", "replace")
        print("--- artifact %s (%s B) ---" % (name, a.get("size")))
        print(raw[:limit])