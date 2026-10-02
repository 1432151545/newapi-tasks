#!/usr/bin/env python3
"""守候指定任务的回执到达（ntfy 主 + rentry 回落），到齐或超时退出。
用法: watch_rec.py T-GITAGT01 [T-GIT01 ...] [--max-min 60]
"""
import importlib.util
import sys
import time

spec = importlib.util.spec_from_file_location("vr", "/root/gitbus-tasks/verify_rec.py")
vr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vr)

args = [a for a in sys.argv[1:] if not a.startswith("--")]
maxmin = 60
for a in sys.argv[1:]:
    if a.startswith("--max-min"):
        maxmin = int(a.split("=")[-1]) if "=" in a else maxmin
want = set(args) or {"T-GITAGT01"}
deadline = time.time() + maxmin * 60
seen = {}

while time.time() < deadline:
    topic = vr.topic()
    recs = {}
    for src, arr in (("ntfy", vr.from_ntfy(topic)), ("rentry", vr.from_rentry())):
        for rec in arr:
            i = vr.parse(rec)
            old = recs.get(i["task"])
            if not old or (i["ts"] or "") >= (old.get("ts") or ""):
                i["src"] = src
                recs[i["task"]] = i
    for w in want:
        if w in recs and w not in seen:
            i = recs[w]
            seen[w] = i
            print("ARRIVED %s src=%s exit=%s ts=%s host=%s sha_ok=%s" % (
                w, i["src"], i["exit"], i["ts"], i["host"], i["sha_ok"]), flush=True)
    if want <= set(seen):
        print("ALL RECEIVED: %s" % ", ".join(sorted(seen)), flush=True)
        sys.exit(0)
    time.sleep(30)

print("TIMEOUT after %dmin; arrived=%s; missing=%s" % (
    maxmin, sorted(seen), sorted(want - set(seen))), flush=True)
sys.exit(1)