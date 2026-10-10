#!/usr/bin/env python3
"""Append an audit entry to muse-liveness-notified.json hk_actions (preserve all fields).
Does NOT alter liveness/notification semantics (no notification was sent this run)."""
import json, io, datetime, pathlib, tempfile, os

p = pathlib.Path('/root/.hermes/cache/muse-liveness-notified.json')
d = json.loads(p.read_text(encoding='utf-8'))
note = ("2026-10-03T12:15Z monitor diff = new pending T-MUSE-VIDEO01:fresh (published 12:01:17Z, "
        "commit 725b621). NOT a success/defect/health-change -> no user notification (waiting state). "
        "VIDEO01 REC arrived 12:09:30Z exit=0 sha_ok nonce-match, but status=executed_transport_pending "
        "with artifacts path+sha256 only (report 7857B / test mp4 7007436B) -> no inline b64, HK cannot "
        "recompute bytes; nothing archivable. A concurrent live session already published the correct "
        "follow-up T-MUSE-VIDEO02 (12:10:01Z, commit ca1d4ff; inline report + host mp4) and is awaiting "
        "its receipt -> cron published NO duplicate rework. Liveness healthy + unchanged "
        "(HB 11:49:05Z -> 12:07:22Z, self-sha OK). No archive, no production/Muse config change.")
acts = d.get('hk_actions')
if not isinstance(acts, list):
    acts = []
acts.append(note)
d['hk_actions'] = acts
d['reviewed_at_utc'] = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
# atomic write, preserve 0600-ish
fd, tmp = tempfile.mkstemp(dir=str(p.parent))
with os.fdopen(fd, 'w', encoding='utf-8') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
os.replace(tmp, str(p))
print("hk_actions entries:", len(d['hk_actions']))
print("liveness field:", d.get('liveness'))
print("notified_at_utc (unchanged):", d.get('notified_at_utc'))