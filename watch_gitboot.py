#!/usr/bin/env python3
"""守候 T-GITBOOT / T-GIT01 回执（轮询 outbox），打印解码结果。"""
import base64, hashlib, json, os, re, sys, time, urllib.request, html as _h

PTR = "hermes-muse-ptr"
TMPART = "/tmp/outbox_tmp_%d.txt"


def fetch(url, timeout=45):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", "replace")


def outbox():
    info = open("/root/muse-deploy/bus-info.txt").read()
    slug = re.search(r"outbox_slug=(\S+)", info).group(1)
    h = fetch("https://rentry.co/%s/edit" % slug)
    m = re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S)
    return _h.unescape(m.group(1)) if m else ""


def dec(rec):
    m = re.search(r"data=(\S+)", rec)
    if not m:
        return None
    d = m.group(1)
    raw = base64.urlsafe_b64decode(d + "=" * (-len(d) % 4))
    ok = hashlib.sha256(raw).hexdigest() == (re.search(r"sha=([0-9a-f]+)", rec).group(1))
    return ok, json.loads(raw.decode())


def main():
    want = sys.argv[1:] or ["T-GITBOOT", "T-GIT01"]
    start = time.time()
    seen = set()
    while time.time() - start < 2400:
        try:
            txt = outbox()
        except Exception as e:
            print("poll err", e, flush=True)
            time.sleep(30)
            continue
        for rec in [l for l in txt.splitlines() if l.startswith("REC|")]:
            tid = re.search(r"task=([^|]+)", rec)
            tid = tid.group(1) if tid else "?"
            if tid in want and tid not in seen:
                seen.add(tid)
                print("=" * 60, flush=True)
                print("REC: %s" % tid, flush=True)
                r = dec(rec)
                if r:
                    ok, res = r
                    print("sha_ok=%s exit=%s host=%s ts=%s" % (ok, res.get("exit"), res.get("host"), res.get("ts")), flush=True)
                    for name, a in (res.get("artifacts") or {}).items():
                        b = base64.urlsafe_b64decode(a["b64"] + "=" * (-len(a["b64"]) % 4))
                        print("--- %s (sha_ok=%s, %d bytes) ---" % (name, hashlib.sha256(b).hexdigest() == a["sha256"], len(b)), flush=True)
                        print(b.decode("utf-8", "replace")[-4000:], flush=True)
        if set(want) <= seen:
            print("ALL WANTED RECEIVED", flush=True)
            return 0
        time.sleep(30)
    print("TIMEOUT waiting for %s (seen=%s)" % (set(want) - seen, seen), flush=True)
    return 1


if __name__ == "__main__":
    sys.exit(main())