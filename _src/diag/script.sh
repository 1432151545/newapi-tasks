#!/bin/bash
# T-GITDIAG — 自愈：修 watchdog 里轮询器调用的变量（$B 未定义）并报告状态
B=$HOME/.hermes-gitbus
W=$HOME/workspace/bin/newapi-watchdog.sh
echo "=== T-GITDIAG nonce=${TASK_NONCE:-none} ts=$(date -u +%FT%TZ) host=$(hostname) ==="

echo "--- 1) watchdog 进程 ---"
ps -eo pid,etime,cmd 2>/dev/null | grep -E 'newapi-watchdog' | grep -v grep || echo "WATCHDOG NOT RUNNING"

echo "--- 2) watchdog 文件 ---"
ls -l "$W" 2>/dev/null || echo "NO FILE $W"

echo "--- 3) 现有 poller 行 ---"
grep -n 'muse_git_poller' "$W" 2>/dev/null || echo "(none)"

echo "--- 4) 是否 set -u ---"
grep -n 'set -u\|set -eu\|set -euo' "$W" 2>/dev/null || echo "(no set -u)"

echo "--- 5) 修复：把 \$B/ 换成绝对路径 ---"
if [ -f "$W" ]; then
  cp "$W" "$W.bak.$(date +%s)" 2>/dev/null
  python3 - "$W" "$B" <<'PY'
import sys
w, b = sys.argv[1], sys.argv[2]
s = open(w, encoding='utf-8', errors='replace').read()
n = s.count('"$B/')
s = s.replace('"$B/', '"' + b + '/')
open(w, 'w', encoding='utf-8').write(s)
print("replaced %d occurrence(s) of \"$B/" % n)
PY
  grep -n 'muse_git_poller' "$W"
else
  echo "skip (no file)"
fi

echo "--- 6) 若未运行则拉起 ---"
if ! pgrep -f 'newapi-watchdog.sh' >/dev/null 2>&1; then
  setsid nohup bash "$W" >> "$B/watchdog.out" 2>&1 < /dev/null &
  sleep 3
  echo "restarted pid(s): $(pgrep -f newapi-watchdog.sh | tr '\n' ' ')"
else
  echo "already running (bash 会重读脚本文件，修复对下一轮生效)"
fi

echo "--- 7) 手动跑一次 poller（自愈后立即验证）---"
python3 "$B/muse_git_poller.py" 2>&1 | tail -25

echo "--- 8) poller log tail ---"
tail -12 "$B/git_poller.log" 2>/dev/null || echo "(no log)"
echo "=== DIAG DONE ==="