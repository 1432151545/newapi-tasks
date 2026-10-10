#!/usr/bin/env python3
"""Independent read: HB liveness + receipt list + VIDEO01 presence."""
import importlib.util, json, hashlib, re, html, urllib.request, datetime, pathlib

root = pathlib.Path('/root/gitbus-tasks')
spec = importlib.util.spec_from_file_location('vr', str(root / 'verify_rec.py'))
vr = importlib.util.module_from_spec(spec); spec.loader.exec_module(vr)

recs = vr.from_rentry()
parsed = [vr.parse(r) for r in recs]
print("receipt tasks:", sorted([p.get('task') for p in parsed]))
for p in parsed:
    if p.get('task') == 'T-MUSE-VIDEO01':
        print("VIDEO01 REC PRESENT:", json.dumps(p, default=str)[:800])
print("VIDEO01 receipt present?", any(p.get('task') == 'T-MUSE-VIDEO01' for p in parsed))

# live HB read
h = urllib.request.urlopen(urllib.request.Request(
    'https://rentry.co/hermes-rx-r6qytd4/edit',
    headers={'User-Agent': 'Mozilla/5.0'}), timeout=30).read().decode()
m = re.search(r'<textarea[^>]*>(.*?)</textarea>', h, re.S)
text = html.unescape(m.group(1)) if m else ''
hb_lines = [l for l in text.splitlines() if l.startswith('HB|') and 'role=muse-native-agent' in l]
now = datetime.datetime.now(datetime.timezone.utc)
print("now_utc:", now.strftime('%Y-%m-%dT%H:%M:%SZ'))
for l in hb_lines[:3]:
    ts = re.search(r'(?:^|\|)ts=([^|]+)', l)
    ok = None
    if '|sha=' in l:
        body, _, claim = l.rpartition('|sha=')
        ok = hashlib.sha256(body.encode()).hexdigest() == claim.strip()
    age = None
    if ts:
        try:
            t = datetime.datetime.strptime(ts.group(1), '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
            age = (now - t).total_seconds()
        except ValueError:
            pass
    print("HB ts=%s self_sha_ok=%s age_s=%s" % (ts.group(1) if ts else '?', ok, age))