#!/usr/bin/env python3
"""发布 T-GITBOOT（内联脚本）给 Muse —— 引导 git 任务通道。"""
import base64, hashlib, json, os, subprocess, sys

S = "/root/gitbus-tasks/bootstrap.sh"
data = open(S, "rb").read()
b64 = base64.urlsafe_b64encode(data).decode()
sha = hashlib.sha256(data).hexdigest()
print("bootstrap sha256=%s bytes=%d b64len=%d" % (sha, len(data), len(b64)))

task = {
    "script_b64": b64,
    "script_sha256": sha,
    "timeout": "900",
    "nonce": "NONCE-GIT-BOOT-100",
    "target": "muse",
    "note": "bootstrap git task channel: clone newapi-tasks + install poller",
}
D = "/root/ops-bus/agent"
args = ["python3", os.path.join(D, "bus_ctl.py"), "task", "script", "id=T-GITBOOT"]
for k, v in task.items():
    args.append("%s=%s" % (k, v))
r = subprocess.run(args, capture_output=True, text=True, cwd="/root/ops-bus")
print(r.stdout)
if r.stderr:
    print("STDERR:", r.stderr[:2000])
sys.exit(r.returncode)
