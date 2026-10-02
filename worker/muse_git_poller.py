#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Muse/SG 侧 git 任务轮询器（零凭据；结果回写 rentry outbox）。

流程：
  1) git fetch/pull 公共任务库（匿名 HTTPS；本地无 clone 则 clone）
  2) 自我更新：repo 内 worker/muse_git_poller.py 与本机副本比对，不同则替换并 re-exec
  3) 加锁，扫描 tasks/*/task.json：跳过已完成（done）、target 不匹配、已过期
  4) 执行：type=script → bash script.sh（先校验 sha256）；type=agent → 入队 / BUS_EXEC
  5) 组装 REC（与 HK bus_ctl verify 契约一致）→ 合并写回 outbox → 记 done

环境变量（全有默认值，可不设）：
  BUS_ROLE      本机角色（默认 muse）        BUS_REPO     任务库 URL
  BUS_REPO_DIR  本地 clone 目录              BUS_STATE_DIR 状态目录（默认 ~/.hermes-gitbus）
  BUS_OUT_SLUG / BUS_OUT_CODE   直接指定回写页（默认从指针页运行时获取，本地缓存兜底）
  BUS_EXEC      type=agent 的执行器命令模板（{prompt_file} 占位）；不设则仅入队
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

VER = "gitpoller-1"
UA = "Mozilla/5.0 (X11; Linux x86_64)"
ROLE = os.environ.get("BUS_ROLE", "muse")
REPO = os.environ.get("BUS_REPO", "https://github.com/1432151545/newapi-tasks.git")
STATE = os.path.expanduser(os.environ.get("BUS_STATE_DIR", "~/.hermes-gitbus"))
REPODIR = os.path.expanduser(os.environ.get("BUS_REPO_DIR", os.path.join(STATE, "tasks-repo")))
PTR_SLUG = os.environ.get("BUS_PTR_SLUG", "hermes-muse-ptr")
SELF = os.path.realpath(__file__)
DONE_P = os.path.join(STATE, "git_done.json")
LOG_P = os.path.join(STATE, "git_poller.log")
CONF_P = os.path.join(STATE, "outbox.conf")
LOCK_P = os.path.join(STATE, "git_poller.lock")
MAX_INLINE = 60000
HOST = os.uname().nodename


def log(m):
    s = "[%s][%s] %s" % (time.strftime("%F %T"), VER, m)
    print(s, flush=True)
    try:
        os.makedirs(STATE, exist_ok=True)
        with open(LOG_P, "a") as f:
            f.write(s + "\n")
    except Exception:
        pass


def sh(cmd, timeout=600, cwd=None, env=None):
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


def fetch(url, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    return urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", "replace")


def textarea(slug):
    """取 rentry /edit 页 <textarea>（存储原文，零渲染污染）。"""
    h = fetch("https://rentry.co/%s/edit" % slug)
    m = re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S)
    return _h.unescape(m.group(1)) if m else ""


def field(txt, name, pat=r"(\S+)"):
    m = re.search(r"(?m)^[ \t]*" + re.escape(name) + "=" + pat, txt)
    return m.group(1) if m else None


def rentry_edit(slug, code, text):
    """与 HK 侧 worker 同款：GET /edit 取 csrf → POST /api/edit/<slug>。"""
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


def get_creds():
    slug = os.environ.get("BUS_OUT_SLUG")
    code = os.environ.get("BUS_OUT_CODE")
    if slug and code:
        return slug, code
    try:
        txt = textarea(PTR_SLUG)
        s2, c2 = field(txt, "outbox_slug"), field(txt, "outbox_code")
        if s2 and c2:
            try:
                os.makedirs(STATE, exist_ok=True)
                with open(CONF_P, "w") as f:
                    f.write("slug=%s\ncode=%s\n" % (s2, c2))
                os.chmod(CONF_P, 0o600)
            except Exception:
                pass
            return s2, c2
    except Exception as e:
        log("pointer creds read failed: %s" % str(e)[:100])
    if os.path.isfile(CONF_P):
        d = {}
        try:
            for line in open(CONF_P):
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    d[k] = v
        except Exception:
            pass
        if d.get("slug") and d.get("code"):
            return d["slug"], d["code"]
    return None, None


def pull_repo():
    if not os.path.isdir(os.path.join(REPODIR, ".git")):
        rc, o = sh(["git", "clone", "-q", "--depth", "1", REPO, REPODIR], 300)
        return rc == 0, o
    rc, o = sh(["git", "-C", REPODIR, "pull", "-q", "--ff-only"], 180)
    if rc == 0:
        return True, o
    rc2, o2 = sh(["git", "-C", REPODIR, "fetch", "-q", "--depth", "1", "origin", "main"], 180)
    rc3, o3 = sh(["git", "-C", REPODIR, "reset", "-q", "--hard", "FETCH_HEAD"], 60)
    if rc2 == 0 and rc3 == 0:
        return True, ""
    return False, (o + "\n" + o2 + "\n" + o3)[-400:]


def self_update():
    """repo 内副本 != 本机 → 替换并 re-exec（应在加锁之前调用）。"""
    src = os.path.join(REPODIR, "worker", "muse_git_poller.py")
    if not os.path.isfile(src):
        return
    try:
        new = open(src, "rb").read()
        cur = open(SELF, "rb").read()
    except Exception as e:
        log("self-update read err: %s" % str(e)[:100])
        return
    if sha(new) == sha(cur):
        return
    try:
        tmp = SELF + ".new"
        with open(tmp, "wb") as f:
            f.write(new)
        os.chmod(tmp, 0o755)
        os.replace(tmp, SELF)
        log("SELF-UPDATE applied, re-exec")
        os.execv(sys.executable, [sys.executable, SELF] + sys.argv[1:])
    except Exception as e:
        log("SELF-UPDATE failed: %s" % str(e)[:120])


def run_task(t):
    td = os.path.join(REPODIR, "tasks", t["id"])
    files = t.get("files") or {}
    for name, want in files.items():
        p = os.path.join(td, name)
        if not os.path.isfile(p):
            return 1, {"error.txt": ("missing file: %s" % name).encode()}
        if sha(open(p, "rb").read()) != want:
            return 1, {"error.txt": ("sha mismatch: %s" % name).encode()}
    ttype = t.get("type", "script")
    if ttype == "script":
        sp = os.path.join(td, "script.sh")
        if not os.path.isfile(sp):
            return 1, {"error.txt": b"script.sh missing"}
        env = dict(os.environ)
        env["TASK_NONCE"] = t.get("nonce", "")
        env["TASK_ID"] = t.get("id", "")
        rc, o = sh(["bash", sp], int(t.get("timeout", 900)), td, env=env)
        return rc, {"script.log": o.encode()}
    if ttype == "agent":
        pf = os.path.join(td, "prompt.md")
        prompt = open(pf, encoding="utf-8").read() if os.path.isfile(pf) else t.get("prompt", "")
        q = os.path.join(STATE, "agent_inbox")
        pfq = os.path.join(q, "%s.md" % t["id"])
        try:
            os.makedirs(q, exist_ok=True)
            with open(pfq, "w", encoding="utf-8") as f:
                f.write(prompt)
        except Exception:
            pass
        tmpl = os.environ.get("BUS_EXEC", "")
        if not tmpl:
            return 0, {"agent.log": ("prompt queued: %s (BUS_EXEC not configured, no executor run)" % pfq).encode()}
        cmd = tmpl.replace("{prompt_file}", pfq).replace("{task_id}", t["id"])
        rc, o = sh(cmd, int(t.get("timeout", 1800)))
        return rc, {"agent.log": o.encode()}
    return 1, {"error.txt": ("unknown type %s" % ttype).encode()}


def build_rec(tid, nonce, ttype, rc, artifacts, note=""):
    res = {"task_id": tid, "nonce": nonce, "type": ttype, "exit": rc,
           "ts": time.strftime("%FT%T"), "worker": ROLE, "host": HOST,
           "artifacts": {}, "note": note}
    for name, b in artifacts.items():
        b64 = base64.urlsafe_b64encode(b).decode()
        if len(b64) <= MAX_INLINE:
            res["artifacts"][name] = {"sha256": sha(b), "size": len(b), "b64": b64}
        else:
            head = b[:max(1, int(MAX_INLINE * 3 / 4))]
            res["artifacts"][name] = {"sha256": sha(head), "size": len(head),
                                      "b64": base64.urlsafe_b64encode(head).decode(),
                                      "truncated": True, "original_size": len(b),
                                      "original_sha256": sha(b)}
    rj = json.dumps(res, ensure_ascii=False).encode()
    return "REC|task=%s|nonce=%s|exit=%s|type=%s|ts=%s|host=%s|sha=%s|data=%s" % (
        tid, nonce, rc, ttype, res["ts"], res["host"], sha(rj),
        base64.urlsafe_b64encode(rj).decode().rstrip("="))


def write_outbox(slug, code, rec, tid):
    try:
        remote = [l.strip() for l in textarea(slug).splitlines()
                  if l.strip().startswith(("HB|", "REC|"))]
    except Exception as e:
        log("outbox read failed (write without merge): %s" % str(e)[:80])
        remote = []
    remote = [l for l in remote if not l.startswith("REC|task=%s|" % tid)]
    recs = ([l for l in remote if l.startswith("REC|")] + [rec])[-10:]
    hbs = [l for l in remote if l.startswith("HB|")][-3:]
    text = "HERMES MUSE OUTBOX\n" + "\n".join(hbs + recs).strip() + "\n"
    ok, r = rentry_edit(slug, code, text)
    log("outbox write %s: %s" % ("OK" if ok else "FAIL", str(r)[:80]))
    return ok


def main():
    os.makedirs(STATE, exist_ok=True)

    # 1) 拉取任务库
    ok, o = pull_repo()
    if not ok:
        log("repo pull failed: %s" % o[-300:])
        return 1

    # 2) 自我更新（加锁前；re-exec 后新进程继续）
    self_update()

    # 3) 加锁
    lf = open(LOCK_P, "w")
    try:
        fcntl.flock(lf, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except Exception:
        log("lock held, skip")
        return 0

    # 4) 扫描任务
    done = {}
    try:
        with open(DONE_P, encoding="utf-8") as f:
            done = json.load(f)
    except Exception:
        done = {}
    tdir = os.path.join(REPODIR, "tasks")
    claimed = 0
    if os.path.isdir(tdir):
        for tid in sorted(os.listdir(tdir)):
            td = os.path.join(tdir, tid)
            tj = os.path.join(td, "task.json")
            if not os.path.isfile(tj):
                continue
            try:
                with open(tj, encoding="utf-8") as f:
                    t = json.load(f)
            except Exception as e:
                log("task.json bad in %s: %s" % (tid, str(e)[:80]))
                continue
            t.setdefault("id", tid)
            if done.get(t["id"], {}).get("exit") is not None:
                continue
            target = t.get("target", "any")
            if target not in ("any", ROLE):
                continue
            exp = t.get("expires")
            if exp:
                try:
                    if time.strptime(exp, "%Y-%m-%dT%H:%M:%SZ") < time.gmtime():
                        log("task %s expired, skip" % t["id"])
                        continue
                except Exception:
                    pass
            log("=== claiming %s (type=%s target=%s) ===" % (t["id"], t.get("type"), target))
            rc, arts = run_task(t)
            rec = build_rec(t["id"], t.get("nonce", ""), t.get("type", "script"), rc, arts,
                            note=t.get("note", ""))
            slug, code = get_creds()
            if slug and code:
                if write_outbox(slug, code, rec, t["id"]):
                    done[t["id"]] = {"exit": rc, "ts": time.strftime("%FT%T")}
                    claimed += 1
            else:
                log("no outbox creds; cannot report %s" % t["id"])
            break  # 一轮只做一个，避免超时叠加
    try:
        with open(DONE_P, "w", encoding="utf-8") as f:
            json.dump(done, f, ensure_ascii=False)
    except Exception:
        pass
    if not claimed:
        log("no new tasks for role=%s" % ROLE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
