#!/usr/bin/env python3
"""HK: 把回写页 REC 结果归档进 /root/gitbus-tasks/results/ 并 push（保持 git 历史完整）。"""
import base64, hashlib, json, os, re, subprocess, sys, time, urllib.request, html as _h

REPO = "/root/gitbus-tasks"
RESULTS = os.path.join(REPO, "results")
WANT = sys.argv[1:]  # 留空 = 全部新任务


def fetch(url, timeout=45):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", "replace")


def main():
    info = open("/root/muse-deploy/bus-info.txt").read()
    slug = re.search(r"slug=(\S+)", info).group(1)
    h = fetch("https://rentry.co/%s/edit" % slug)
    t = _h.unescape(re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S).group(1))
    os.makedirs(RESULTS, exist_ok=True)
    written = []
    for line in t.splitlines():
        if not line.startswith("REC|"):
            continue
        tid = (re.search(r"task=([^|]+)", line) or [None, None])[1] if re.search(r"task=([^|]+)", line) else None
        if not tid:
            continue
        if WANT and tid not in WANT:
            continue
        rp = os.path.join(RESULTS, "%s.json" % tid)
        if os.path.isfile(rp):
            continue
        m = re.search(r"data=(\S+)", line)
        msha = re.search(r"sha=([0-9a-f]+)", line)
        if not m or not msha:
            continue
        d = m.group(1)
        raw = base64.urlsafe_b64decode(d + "=" * (-len(d) % 4))
        ok = hashlib.sha256(raw).hexdigest() == msha.group(1)
        out = {"task": tid, "sha_ok": ok, "verified_at": time.strftime("%FT%TZ", time.gmtime()),
               "rec": line, "result": json.loads(raw.decode())}
        with open(rp, "w", encoding="utf-8") as f:
            json.dump(out, f, ensure_ascii=False, indent=2)
        written.append(tid)
    print("archived:", written or "(none new)")
    if written:
        git = lambda *a: subprocess.run(["git", "-C", REPO] + list(a), capture_output=True, text=True)
        git("add", "-A", "results")
        r = git("commit", "-q", "-m", "results: %s" % ", ".join(written))
        if r.returncode == 0:
            p = git("push", "-q", "origin", "main")
            print("pushed" if p.returncode == 0 else "PUSH FAIL: %s" % p.stderr[:200])


if __name__ == "__main__":
    main()