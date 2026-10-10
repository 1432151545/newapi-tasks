#!/usr/bin/env python3
"""Second live read: HB ts advancement + VIDEO01 receipt watch (read-only)."""
import hashlib, re, html, urllib.request, datetime, json, pathlib

def read_page():
    h = urllib.request.urlopen(urllib.request.Request(
        'https://rentry.co/hermes-rx-r6qytd4/edit',
        headers={'User-Agent': 'Mozilla/5.0'}), timeout=30).read().decode()
    m = re.search(r'<textarea[^>]*>(.*?)</textarea>', h, re.S)
    return html.unescape(m.group(1)) if m else ''

now = datetime.datetime.now(datetime.timezone.utc)
text = read_page()
hb_lines = [l for l in text.splitlines() if l.startswith('HB|') and 'role=muse-native-agent' in l]
print("now_utc:", now.strftime('%Y-%m-%dT%H:%M:%SZ'))
for l in hb_lines[:2]:
    ts = re.search(r'(?:^|\|)ts=([^|]+)', l)
    ok = None
    if '|sha=' in l:
        body, _, claim = l.rpartition('|sha=')
        ok = hashlib.sha256(body.encode()).hexdigest() == claim.strip()
    age = None
    if ts:
        try:
            t = datetime.datetime.strptime(ts.group(1), '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
            age = round((now - t).total_seconds())
        except ValueError:
            pass
    print("HB ts=%s self_sha_ok=%s age_s=%s" % (ts.group(1) if ts else '?', ok, age))
print("VIDEO01 REC present?", 'T-MUSE-VIDEO01' in text and 'REC|' in text and bool(re.search(r'REC\|[^\n]*T-MUSE-VIDEO01', text)))