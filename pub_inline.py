#!/usr/bin/env python3
"""发布内联脚本任务（通用）：pub_inline.py <id> <script_path> <nonce> <target> [note] [timeout]"""
import base64, hashlib, os, subprocess, sys

tid, spath, nonce = sys.argv[1], sys.argv[2], sys.argv[3]
target = sys.argv[4] if len(sys.argv) > 4 else "muse"
note = sys.argv[5] if len(sys.argv) > 5 else ""
tmo = sys.argv[6] if len(sys.argv) > 6 else "900"

data = open(spath, "rb").read()
b64 = base64.urlsafe_b64encode(data).decode()
sha = hashlib.sha256(data).hexdigest()
print("script sha256=%s bytes=%d b64len=%d" % (sha, len(data), len(b64)))

D = "/root/ops-bus/agent"
args = ["python3", os.path.join(D, "bus_ctl.py"), "task", "script", "id=%s" % tid,
        "script_b64=%s" % b64, "script_sha256=%s" % sha, "timeout=%s" % tmo,
        "nonce=%s" % nonce, "target=%s" % target, "note=%s" % note]
r = subprocess.run(args, capture_output=True, text=True, cwd="/root/ops-bus")
print(r.stdout)
if r.stderr:
    print("STDERR:", r.stderr[:1500])
sys.exit(r.returncode)