#!/bin/bash
# repair.sh — 恢复 watchdog 原状 + 以【独立常驻循环】运行 git 轮询器（60s 一拍）
# 幂等，可反复运行。用法（沙箱内）：
#   git clone -q --depth 1 https://github.com/1432151545/newapi-tasks.git /tmp/gt && bash /tmp/gt/repair.sh
set -u
B=$HOME/.hermes-gitbus
W=${BUS_WATCHDOG:-$HOME/workspace/bin/newapi-watchdog.sh}
echo "=== repair $(date -u +%FT%TZ) host=$(hostname) ==="

echo "--- 1) 从 watchdog 里摘掉之前插入的 poller 行（恢复原状）---"
if [ -f "$W" ]; then
  ls -l "$W"
  cp -a "$W" "$W.pre-repair.$(date +%s)"
  python3 - "$W" <<'PY'
import re, sys
w = sys.argv[1]
lines = open(w, encoding='utf-8', errors='replace').read().split('\n')
out = [l for l in lines if not re.search(r'muse_git_poller', l)]
open(w, 'w', encoding='utf-8').write('\n'.join(out))
print("removed %d poller line(s) from watchdog" % (len(lines) - len(out)))
PY
  echo "--- 2) watchdog 语法检查（坏了就从备份回退）---"
  if ! bash -n "$W"; then
    echo "SYNTAX BROKEN -> 回退"
    for L in $(ls -tr "$W".pre-repair.* "$W".bak.* 2>/dev/null); do
      cp -a "$L" "$W"
      if bash -n "$W"; then echo "restored from $L"; break; fi
    done
  fi
  bash -n "$W" && echo "watchdog syntax OK" || echo "watchdog syntax STILL BROKEN"
else
  echo "WARN: no watchdog at $W"
fi

echo "--- 3) 重启 watchdog（恢复原有 5 分钟节拍/心跳）---"
pkill -f 'newapi-watchdog.sh' 2>/dev/null && echo "(killed stale watchdog)" || echo "(no stale watchdog)"
sleep 1
if [ -f "$W" ]; then
  setsid nohup bash "$W" >> "$B/watchdog.out" 2>&1 </dev/null &
  sleep 3
  echo "watchdog pid(s): $(pgrep -f newapi-watchdog.sh | tr '\n' ' ')"
fi

echo "--- 4) 启动【独立】git 轮询循环（60s，不动 watchdog）---"
pkill -f 'muse_git_poller_loop' 2>/dev/null || true
pkill -f 'while true; do python3.*muse_git_poller' 2>/dev/null || true
sleep 1
setsid nohup bash -c 'while true; do python3 "$HOME/.hermes-gitbus/muse_git_poller.py" >> "$HOME/.hermes-gitbus/git_poller.log" 2>&1; sleep 60; done' \
  >/dev/null 2>&1 </dev/null &
sleep 2
echo "poller loop pid(s): $(pgrep -f 'muse_git_poller' | tr '\n' ' ')"

echo "--- 5) 立即跑一轮 poller ---"
timeout 300 python3 "$B/muse_git_poller.py" 2>&1 | tail -25
echo "--- poller log tail ---"; tail -10 "$B/git_poller.log" 2>/dev/null || echo "(no log)"

echo "--- 6) 立即跑一轮 sync（恢复心跳/既有通道）---"
S="$B/sync_patch_from_pointer.sh"
if [ -f "$S" ]; then timeout 400 bash "$S" 2>&1 | tail -20; else echo "(no $S)"; fi

echo "--- 7) 收尾核对 ---"
echo "watchdog: $(pgrep -f newapi-watchdog.sh | tr '\n' ' ')"
echo "poller:   $(pgrep -f muse_git_poller | tr '\n' ' ')"
echo "=== repair done ==="