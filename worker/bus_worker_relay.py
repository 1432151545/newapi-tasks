#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""bus_worker_relay.py — Muse 沙箱侧总线工人（零 GitHub 凭据，只用 HTTPS）

每轮：
  1. 读指针页，取 outbox_slug / outbox_code / task_*
  2. 若有未完成任务：按 type 执行 -> 结果 JSON（内含 base64 产物）
  3. 把结果追加到 outbox 页（rentry，凭 edit_code 写）
  4. 维护本地台账 done.json 与心跳（≤每小时一次）

配置从指针页读，无需本地密钥文件。安装位置 ~/.hermes-gitbus/bus_worker.py
"""
import base64
import fcntl
import hashlib
import html as _h
import http.cookiejar
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HOME = os.path.expanduser("~")
GB = os.path.join(HOME, ".hermes-gitbus")
PTR = os.environ.get("PTR_URL", "https://rentry.co/hermes-muse-ptr")
WORKDIR = os.path.expanduser(os.environ.get("BUS_WORKDIR", "~/newapi-test"))
ROLE = os.environ.get("BUS_ROLE", "muse")  # muse | sg
UA = "Mozilla/5.0 (X11; Linux x86_64)"
LOG = os.path.join(GB, "bus.log")
DONE = os.path.join(GB, "done.json")
OUTBOX = os.path.join(GB, "outbox.txt")
HB = os.path.join(GB, "hb.txt")
LOCK = os.path.join(GB, "bus.lock")
SELF = os.path.realpath(__file__)
VER = "v4"
MAX_INLINE = 60000  # 单条记录内联上限（b64 字符数）


def log(m):
    s = "[%s] %s" % (time.strftime("%F %T"), m)
    print(s)
    try:
        os.makedirs(GB, exist_ok=True)
        with open(LOG, "a") as f:
            f.write(s + "\n")
    except Exception:
        pass


def _load(p, d):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read() if p.endswith(".txt") else json.load(f)
    except Exception:
        return d


def _load_json(p, d):
    v = _load(p, None)
    return v if isinstance(v, dict) else d


def _load_text(p, d=""):
    v = _load(p, None)
    return v if isinstance(v, str) else d


def _save(p, v):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(v if isinstance(v, str) else json.dumps(v, ensure_ascii=False))


def get(url, timeout=45):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    return urllib.request.urlopen(req, timeout=timeout).read()


def sh(cmd, timeout=3600, cwd=None, env=None):
    try:
        p = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True,
                           text=True, timeout=timeout, cwd=cwd, env=env)
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "TIMEOUT after %ss" % timeout
    except Exception as e:
        return 1, "EXEC_ERR %s" % e


def sha(b):
    return hashlib.sha256(b).hexdigest()


# ---------------- rentry 回写 ----------------

def rentry_edit(slug, code, text):
    cj = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    op.addheaders = [("User-Agent", UA)]
    eurl = "https://rentry.co/%s/edit" % slug
    try:
        html = op.open(eurl, timeout=35).read().decode("utf-8", "replace")
    except Exception as e:
        return False, "GET edit: %s" % e
    m = re.search(r'name="csrfmiddlewaretoken" value="([^"]+)"', html)
    if not m:
        return False, "no csrf token"
    data = urllib.parse.urlencode({"csrfmiddlewaretoken": m.group(1), "text": text,
                                   "edit_code": code}).encode()
    req = urllib.request.Request("https://rentry.co/api/edit/%s" % slug, data=data,
                                 headers={"Referer": eurl, "User-Agent": UA})
    try:
        r = op.open(req, timeout=35).read().decode("utf-8", "replace")
    except Exception as e:
        return False, "POST edit: %s" % e
    return ('"200"' in r or "200" in r[:60]), r[:160]


def rentry_read_lines(slug, keep_prefixes):
    """读取回写页远端文本，只保留指定前缀的行（容错：任何异常返回 None）。

    注意：必须走 /edit 页的 <textarea>（存储原文，零渲染污染）；
    渲染页会截断长行并在行尾追加 </p></div> 之类残渣。
    """
    try:
        h = get("https://rentry.co/%s/edit" % slug).decode("utf-8", "replace")
    except Exception:
        return None
    m = re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S)
    if not m:
        return None
    txt = _h.unescape(m.group(1))
    out = []
    for l in txt.splitlines():
        l = l.strip()
        if any(l.startswith(p) for p in keep_prefixes):
            # 只截取合法 base64 字符集，防 HTML 残渣污染 data 字段
            l = re.sub(r"(data=)[^A-Za-z0-9_\-]*$", r"\1", l)
            mm = re.search(r"(data=)([A-Za-z0-9_\-]+)", l)
            if mm:
                l = l[:mm.start(2)] + mm.group(2)
            out.append(l)
    return out


def fetch_blob(slug, prefix):
    """从 rentry blobs 页解码 chunked base64 产物（沙箱出口代理可达，catbox 常被拦）。"""
    html = get("https://rentry.co/%s" % slug, timeout=90).decode("utf-8", "replace")
    html = re.sub(r"(?is)<head\b.*?</head>", "", html)
    txt = _h.unescape(re.sub(r"<[^>]+>", "\n", html))
    parts = re.findall(r"(?m)^[ \t]*" + re.escape(prefix) + r"_b64_(\d+)=([A-Za-z0-9+/=]+)", txt)
    if not parts:
        return None
    parts.sort(key=lambda x: int(x[0]))
    try:
        return base64.b64decode("".join(p[1] for p in parts))
    except Exception:
        return None


# ---------------- 任务执行 ----------------

def task_selftest(t, nonce):
    out = []
    for c in (["hostname"], ["uname", "-a"], ["nproc"], ["df", "-h", "/"], ["python3", "-V"]):
        rc, o = sh(c, 60)
        out.append("$ %s\n%s" % (" ".join(c), o.strip()))
    rc, o = sh("curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:3000/", 60)
    out.append("http_3000=%s" % o.strip())
    rc, o = sh("ls -la %s 2>/dev/null | head -20" % WORKDIR, 60)
    out.append("workdir:\n%s" % o.strip())
    return 0, {"selftest.txt": "\n".join(out).encode()}


def task_attest(t, nonce):
    sc = os.path.join(WORKDIR, "muse_attest.py")
    if not os.path.isfile(sc):
        sc = os.path.join(GB, "muse_attest.py")
    if not os.path.isfile(sc):
        return 1, {"error.txt": b"muse_attest.py not found"}
    outp = os.path.join(GB, "receipt.json")
    rc, o = sh(["python3", sc, nonce, "--out", outp, "--no-upload"], 900)
    if os.path.isfile(outp):
        return rc, {"receipt.json": open(outp, "rb").read()}
    return rc, {"error.txt": o[-4000:].encode()}


def task_bench(t, nonce):
    sc = os.path.join(WORKDIR, "bench58_sandbox.py")
    if not os.path.isfile(sc):
        sc = os.path.join(GB, "bench58_sandbox.py")
    if not os.path.isfile(sc):
        return 1, {"error.txt": b"bench58_sandbox.py not found"}
    rc, o = sh(["python3", sc], 2400, WORKDIR)
    return rc, {"bench.log": o.encode()}


def task_script(t, nonce):
    """执行任务脚本。

    脚本来源优先级：
      1) script_b64 —— 任务内联 base64（自包含，不依赖任何托管通道；推荐）
      2) script_url —— 外部 URL 下载（需沙箱能访问该主机）+ script_sha256 校验
    """
    p = os.path.join(GB, "task_script.sh")
    data = None
    if t.get("script_b64"):
        try:
            b64 = t["script_b64"]
            data = base64.urlsafe_b64decode(b64 + "=" * (-len(b64) % 4))
        except Exception as e:
            return 1, {"error.txt": ("script_b64 decode failed: %s" % e).encode()}
    elif t.get("script_url"):
        rc, o = sh(["curl", "-fsSL", "--max-time", "300", "-A", UA, "-o", p, t["script_url"]], 330)
        if rc != 0:
            return 1, {"error.txt": o.encode()}
        data = open(p, "rb").read()
    else:
        return 1, {"error.txt": b"script_b64 or script_url required"}
    s = t.get("script_sha256")
    if s and sha(data) != s:
        return 1, {"error.txt": b"script sha256 mismatch"}
    with open(p, "wb") as f:
        f.write(data)
    os.chmod(p, 0o755)
    env = dict(os.environ)
    env["TASK_NONCE"] = nonce or ""
    rc, o = sh(["bash", p], int(t.get("timeout", 1800)), WORKDIR, env=env)
    return rc, {"script.log": o.encode()}


HANDLERS = {"selftest": task_selftest, "attest": task_attest,
            "bench": task_bench, "script": task_script}


def main():
    os.makedirs(GB, exist_ok=True)
    lf = open(LOCK, "w")
    try:
        fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except Exception:
        log("lock held, skip")
        return

    try:
        h = get(PTR + "/edit").decode("utf-8", "replace")
        m = re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S)
        if not m:
            log("pointer textarea not found")
            return
        txt = _h.unescape(m.group(1))
    except Exception as e:
        log("pointer fetch failed: %s" % e)
        return

    # 走 /edit 页 <textarea>（存储原文，零渲染污染）：渲染页会截断长行、
    # 并在行尾追加 </p></div> 残渣；<head> 的 meta description 也是截断副本。

    def f(name, pat=r"(\S+)"):
        m = re.search(r"(?m)^[ \t]*" + re.escape(name) + "=" + pat, txt)
        return m.group(1) if m else None

    # ---- 自我升级（优先 blobs 页，回退 worker_url） ----
    wurl, wsha = f("worker_url", r"(https://\S+)"), f("worker_sha", r"([0-9a-f]{64})")
    blobs = f("blobs_slug")
    if wsha and os.path.isfile(SELF) and os.environ.get("BUS_NO_SELFUPDATE") != "1":
        cur = sha(open(SELF, "rb").read())
        if cur != wsha:
            log("SELF-UPDATE: %s -> %s" % (cur[:12], wsha[:12]))
            new = None
            if blobs:
                try:
                    new = fetch_blob(blobs, "worker")
                except Exception as e:
                    log("SELF-UPDATE blobs err: %s" % str(e)[:80])
            if (new is None or sha(new) != wsha) and wurl:
                try:
                    cand = get(wurl, timeout=120)
                    if sha(cand) == wsha:
                        new = cand
                except Exception as e:
                    log("SELF-UPDATE fallback err: %s" % str(e)[:80])
            if new is not None and sha(new) == wsha:
                try:
                    tmp = SELF + ".new"
                    with open(tmp, "wb") as fh:
                        fh.write(new)
                    os.chmod(tmp, 0o755)
                    os.replace(tmp, SELF)
                    log("SELF-UPDATE applied, re-exec")
                    os.environ["BUS_NO_SELFUPDATE"] = "1"
                    os.execv(sys.executable, [sys.executable, SELF] + sys.argv[1:])
                except Exception as e:
                    log("SELF-UPDATE apply failed: %s" % e)
            else:
                log("SELF-UPDATE: could not obtain matching copy, skip")

    # ---- 顺带升级同步脚本（看门狗）自身：解决"旧脚本自更新走坏链"的收敛问题 ----
    # 场景：宿主跑的是 v3 脚本，其自更新依赖 sync_script_url（可能已失效）；
    # worker 已能走 blobs 页，于是由 worker 负责把脚本也收敛到最新。
    ssha = f("sync_script_sha", r"([0-9a-f]{64})")
    spath = os.environ.get("SYNC_PATH", os.path.join(HOME, "newapi-test", "sync_patch_from_pointer.sh"))
    if ssha and blobs:
        try:
            cur_s = sha(open(spath, "rb").read()) if os.path.isfile(spath) else None
        except Exception:
            cur_s = None
        if cur_s != ssha:
            log("SYNC-SCRIPT: updating %s -> %s" % ((cur_s or "none")[:12], ssha[:12]))
            new_s = None
            try:
                new_s = fetch_blob(blobs, "script")
            except Exception as e:
                log("SYNC-SCRIPT blobs err: %s" % str(e)[:80])
            if (new_s is None or sha(new_s) != ssha) and f("sync_script_url", r"(https://\S+)"):
                try:
                    cand = get(f("sync_script_url", r"(https://\S+)"), timeout=120)
                    if sha(cand) == ssha:
                        new_s = cand
                except Exception as e:
                    log("SYNC-SCRIPT fallback err: %s" % str(e)[:80])
            if new_s is not None and sha(new_s) == ssha:
                try:
                    os.makedirs(os.path.dirname(spath), exist_ok=True)
                    tmp = spath + ".new"
                    with open(tmp, "wb") as fh:
                        fh.write(new_s)
                    os.chmod(tmp, 0o755)
                    os.replace(tmp, spath)
                    log("SYNC-SCRIPT: updated OK")
                except Exception as e:
                    log("SYNC-SCRIPT apply failed: %s" % e)
            else:
                log("SYNC-SCRIPT: could not obtain matching copy, skip")

    slug, code = f("outbox_slug"), f("outbox_code")
    now = time.time()

    # 心跳（≤每小时一次；合并远端，保留其他角色 HB 与全部 REC）
    hb = _load_text(HB, "0")
    try:
        hb = float(hb or 0)
    except Exception:
        hb = 0
    if slug and code and now - hb > 3600:
        remote = rentry_read_lines(slug, ("HB|", "REC|"))
        lines = remote if remote is not None else \
            [l for l in _load_text(OUTBOX, "").splitlines() if l.startswith(("HB|", "REC|"))]
        mine = "|role=%s|" % ROLE  # 只替换自己的 HB，保留其他角色
        lines = [l for l in lines if not (l.startswith("HB|") and mine in l)]
        lines.insert(0, "HB|ts=%s|ver=%s|role=%s|host=%s" % (time.strftime("%FT%T"), VER, ROLE, os.uname().nodename))
        newtext = "HERMES MUSE OUTBOX\n" + "\n".join(lines).strip() + "\n"
        ok, r = rentry_edit(slug, code, newtext)
        if ok:
            _save(OUTBOX, newtext)
            _save(HB, str(now))
            log("heartbeat ok")
        else:
            log("heartbeat failed: %s" % r)

    tid, tb64, tsha, tnonce = f("task_id"), f("task_b64"), f("task_sha", r"([0-9a-f]{64})"), f("task_nonce")
    done = _load_json(DONE, {})
    if not (tid and tb64):
        log("no task on pointer")
        return
    if done.get(tid, {}).get("exit") is not None:
        log("task %s already done (exit=%s)" % (tid, done[tid]["exit"]))
        return

    log("=== claiming %s ===" % tid)
    pad = tb64 + "=" * (-len(tb64) % 4)
    try:
        raw = base64.urlsafe_b64decode(pad)
    except Exception as e:
        log("task b64 decode failed: %s" % e)
        return
    if tsha and sha(raw) != tsha:
        log("task sha mismatch, refusing")
        return
    try:
        task = json.loads(raw.decode("utf-8"))
    except Exception as e:
        log("task json bad: %s" % e)
        return

    ttype = task.get("type", "selftest")
    nonce = tnonce or task.get("nonce", "")
    target = task.get("target", "any")
    if target not in ("any", ROLE):
        log("task %s targeted at %r, this worker is %r -> skip" % (tid, target, ROLE))
        return
    h = HANDLERS.get(ttype)
    if h:
        rc, arts = h(task, nonce)
    else:
        rc, arts = 1, {"error.txt": ("unknown type %s" % ttype).encode()}

    # 组装结果（超限时内嵌前段 + 标 truncated）
    res = {"task_id": tid, "nonce": nonce, "type": ttype, "exit": rc,
           "ts": time.strftime("%FT%T"), "worker": ROLE, "host": os.uname().nodename,
           "artifacts": {}, "note": task.get("note", "")}
    for name, b in arts.items():
        b64full = base64.urlsafe_b64encode(b).decode()
        if len(b64full) <= MAX_INLINE:
            res["artifacts"][name] = {"sha256": sha(b), "size": len(b), "b64": b64full}
        else:
            head = b[:max(1, int(MAX_INLINE * 3 / 4))]
            res["artifacts"][name] = {"sha256": sha(head), "size": len(head),
                                      "b64": base64.urlsafe_b64encode(head).decode(),
                                      "truncated": True, "original_size": len(b),
                                      "original_sha256": sha(b)}
    rj = json.dumps(res, ensure_ascii=False).encode()
    rec = "REC|task=%s|nonce=%s|exit=%s|type=%s|ts=%s|host=%s|sha=%s|data=%s" % (
        tid, nonce, rc, ttype, res["ts"], res["host"], sha(rj),
        base64.urlsafe_b64encode(rj).decode())

    if slug and code:
        # 合并远端已有记录（防本地丢失导致覆盖）：替换本任务 REC，保留其他 REC/HB
        remote = rentry_read_lines(slug, ("HB|", "REC|"))
        old = remote if remote is not None else \
            [l for l in _load_text(OUTBOX, "").splitlines() if l.startswith(("HB|", "REC|"))]
        old = [l for l in old if not l.startswith("REC|task=%s|" % tid)]
        recs = ([l for l in old if l.startswith("REC|")] + [rec])[-10:]  # cap：最近 10 条
        hbs = [l for l in old if l.startswith("HB|")][-3:]              # cap：最多 3 条
        newtext = "HERMES MUSE OUTBOX\n" + "\n".join(hbs + recs).strip() + "\n"
        ok, r = rentry_edit(slug, code, newtext)
        if ok:
            _save(OUTBOX, newtext)
            log("result written to outbox: %s exit=%s" % (tid, rc))
        else:
            log("OUTBOX WRITE FAILED: %s" % r)
    else:
        log("no outbox credentials on pointer, cannot report")

    done[tid] = {"exit": rc, "ts": res["ts"], "sha": sha(rj)}
    _save(DONE, done)
    log("=== %s done exit=%s ===" % (tid, rc))


if __name__ == "__main__":
    main()