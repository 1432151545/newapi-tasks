#!/usr/bin/env python3
"""HK 侧独立核验 + 归档 Muse 回执到私库 1432151545/newapi-receipts (Contents API)。

用法: archive_receipts.py T-MUSE-XXX [T-MUSE-YYY ...]
流程: 读回写页 REC → 整体 sha_ok → nonce 对本地 task.json → 解 artifacts
      → 复算每文件 sha256/bytes → 写 receipts/<id>.json|.rec + verification/<id>.json
      → GET 回读逐字节确认。已归档(verification/<id>.json 在库内)则跳过。
"""
import base64
import hashlib
import json
import os
import sys
import time
import urllib.request

sys.path.insert(0, "/root/gitbus-tasks")
import verify_rec as vr

TOKEN = open("/root/.hermes-gitbus/token").read().strip()
API = "https://api.github.com/repos/1432151545/newapi-receipts"
TASKDIR = "/root/gitbus-tasks/tasks"
UAH = {"User-Agent": "hermes-archive", "Authorization": "token " + TOKEN}


def gh(method, path, body=None, raw=False):
    url = path if path.startswith("http") else API + path
    data = body if isinstance(body, bytes) else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, headers=UAH, method=method)
    with urllib.request.urlopen(req, timeout=60) as r:
        b = r.read()
    return b if raw else json.loads(b.decode())


def main():
    want = sys.argv[1:]
    tree = gh("GET", "/git/trees/HEAD?recursive=1")
    existing = {x["path"]: x for x in tree.get("tree", [])}

    recs = {}
    for line in vr.from_rentry():
        i = vr.parse(line)
        old = recs.get(i["task"])
        if not old or (i["ts"] or "") >= (old.get("ts") or ""):
            i["raw"] = line.rstrip("\n")
            recs[i["task"]] = i

    report = []
    for tid in want:
        r = recs.get(tid)
        if not r:
            report.append((tid, "NO_RECEIPT", "回执页上没有该任务的 REC"))
            continue
        if "verification/%s.json" % tid in existing:
            report.append((tid, "ALREADY_ARCHIVED", "私库已有 verification/%s.json" % tid))
            continue

        payload = r.get("payload") or {}
        checks = {}

        # nonce 必须匹配本地 task.json
        tj = os.path.join(TASKDIR, tid, "task.json")
        local_nonce = None
        if os.path.exists(tj):
            local_nonce = json.load(open(tj)).get("nonce")
        checks["sha_ok"] = bool(r.get("sha_ok"))
        checks["nonce"] = r.get("nonce")
        checks["nonce_match"] = (local_nonce is not None and local_nonce == r.get("nonce"))
        checks["host"] = r.get("host")
        checks["ts"] = r.get("ts")
        checks["exit"] = r.get("exit")
        checks["note"] = payload.get("note")

        # 逐 artifact 复算
        arts = []
        ok_all = checks["sha_ok"] and checks["nonce_match"]
        for name, a in vr._norm_arts(payload.get("artifacts")):
            base = os.path.basename(str(name))
            b64 = a.get("b64") or a.get("data") or ""
            if not b64:
                arts.append({"name": base, "inline_bytes": False,
                             "declared_sha256": a.get("sha256"), "note": "仅路径/哈希，无内联字节，沙箱无入站无法独立复算"})
                continue
            raw_b = base64.urlsafe_b64decode(b64 + "=" * (-len(b64) % 4))
            sha = hashlib.sha256(raw_b).hexdigest()
            match = (sha == a.get("sha256") and len(raw_b) == a.get("size"))
            ok_all = ok_all and match
            outdir = "/root/.hermes/cache/scratch/muse-receipts/%s" % tid
            os.makedirs(outdir, exist_ok=True)
            with open(os.path.join(outdir, base), "wb") as fh:
                fh.write(raw_b)
            arts.append({"name": base, "inline_bytes": True, "bytes": len(raw_b), "sha256": sha,
                         "declared_sha256": a.get("sha256"), "match": match,
                         "local_path": os.path.join(outdir, base)})
        checks["artifacts"] = arts
        checks["verdict"] = "VERIFIED" if ok_all else "FAILED"

        ver = {
            "task": tid,
            "verified_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "verified_by": "hermes-cron muse-receipt-monitor (HK side, independent recompute)",
            "source": "rentry writeback page %s" % vr._conf(vr.BUSINFO).get("slug", "?"),
            "sha_ok": checks["sha_ok"],
            "nonce_match": checks["nonce_match"],
            "host": checks["host"],
            "ts": checks["ts"],
            "exit": checks["exit"],
            "note": checks["note"],
            "artifacts": arts,
            "verdict": checks["verdict"],
            "raw_rec_sha256": hashlib.sha256(r["raw"].encode()).hexdigest(),
        }

        files = {
            "receipts/%s.json" % tid: json.dumps(payload, ensure_ascii=False, indent=2).encode(),
            "receipts/%s.rec" % tid: r["raw"].encode(),
            "verification/%s.json" % tid: json.dumps(ver, ensure_ascii=False, indent=2).encode(),
        }
        problems = []
        for path, data in files.items():
            try:
                body = {"message": "archive %s" % path, "content": base64.b64encode(data).decode()}
                if path in existing and existing[path].get("sha"):
                    body["sha"] = existing[path]["sha"]
                gh("PUT", "/contents/" + path, body)
                back = gh("GET", "/contents/" + path, raw=True)
                import base64 as _b
                got = _b.b64decode(json.loads(back.decode())["content"].replace("\n", ""))
                if got != data:
                    problems.append("%s readback mismatch" % path)
            except Exception as e:
                problems.append("%s put failed: %s" % (path, str(e)[:120]))

        status = "ARCHIVED" if not problems else "ARCHIVE_PARTIAL"
        if problems:
            status += " :: " + "; ".join(problems)
        report.append((tid, status, checks["verdict"] + " sha_ok=%s nonce_match=%s arts=%d" % (
            checks["sha_ok"], checks["nonce_match"], len(arts))))

    for tid, status, note in report:
        print("%-18s %-18s %s" % (tid, status, note))
    return 0


if __name__ == "__main__":
    sys.exit(main())