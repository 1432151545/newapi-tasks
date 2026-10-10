#!/usr/bin/env python3
"""Dump T-MUSE-VIDEO01 REC payload structure (truncate long values)."""
import importlib.util, json, pathlib

root = pathlib.Path('/root/gitbus-tasks')
spec = importlib.util.spec_from_file_location('vr', str(root / 'verify_rec.py'))
vr = importlib.util.module_from_spec(spec); spec.loader.exec_module(vr)

def trunc(v, n=600):
    s = json.dumps(v, ensure_ascii=False, indent=1, default=str)
    return s if len(s) <= n else s[:n] + " ...<%d chars>" % len(s)

for p in [vr.parse(r) for r in vr.from_rentry()]:
    if p.get('task') != 'T-MUSE-VIDEO01':
        continue
    raw_line = None
    for r in vr.from_rentry():
        if vr.parse(r).get('task') == 'T-MUSE-VIDEO01':
            raw_line = r
    print("REC line length:", len(raw_line))
    print("REC line head:", raw_line[:400])
    print()
    pl = p.get('payload') or {}
    for k, v in pl.items():
        if k in ('artifacts',):
            continue
        print("[%s] %s" % (k, trunc(v)))
    print()
    arts = pl.get('artifacts') or {}
    print("[artifacts] type=%s" % type(arts).__name__)
    items = arts.items() if isinstance(arts, dict) else enumerate(arts)
    for name, a in items:
        print("--- artifact: %r ---" % (name,))
        print(trunc(a, 800))
    breaks = raw_line.count('\n') if raw_line else 0
    print("\n(raw line has %d newlines; total %d chars)" % (breaks, len(raw_line)))