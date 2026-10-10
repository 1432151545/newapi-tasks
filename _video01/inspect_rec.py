#!/usr/bin/env python3
"""Inspect the T-MUSE-VIDEO01 REC: status/exit/sha_ok/nonce/payload shape (no b64 dump)."""
import importlib.util, json, pathlib, base64, hashlib

root = pathlib.Path('/root/gitbus-tasks')
spec = importlib.util.spec_from_file_location('vr', str(root / 'verify_rec.py'))
vr = importlib.util.module_from_spec(spec); spec.loader.exec_module(vr)

parsed = [vr.parse(r) for r in vr.from_rentry()]
print("all tasks:", sorted([(p.get('task'), p.get('status'), p.get('sha_ok')) for p in parsed], key=lambda x: str(x)))
for p in parsed:
    if p.get('task') != 'T-MUSE-VIDEO01':
        continue
    print("\n===== VIDEO01 entry =====")
    for k in ('task', 'exit', 'status', 'host', 'ts', 'nonce', 'sha_ok'):
        print("  %s = %r" % (k, p.get(k)))
    pl = p.get('payload') or {}
    print("  payload keys:", list(pl.keys()))
    arts = pl.get('artifacts')
    if isinstance(arts, dict):
        for name, a in arts.items():
            a = a or {}
            b = a.get('b64') or ''
            raw = base64.urlsafe_b64decode(b + '=' * (-len(b) % 4)) if b else b''
            print("  artifact %s size=%s sha=%s b64_len=%s recomputed_sha=%s recomputed_bytes=%s" % (
                name, a.get('size'), (a.get('sha256') or '')[:16], len(b), hashlib.sha256(raw).hexdigest()[:16], len(raw)))
    elif isinstance(arts, list):
        print("  artifacts(list):", json.dumps(arts)[:400])
    files = pl.get('files')
    if files:
        print("  files:", json.dumps(files)[:400])
    # nonce vs local task.json
    local = json.loads((root / 'tasks/T-MUSE-VIDEO01/task.json').read_text())
    print("  nonce_match_local =", p.get('nonce') == local.get('nonce'))