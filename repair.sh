#!/bin/bash
# repair.sh — 修复 git 轮询器接入点，重启 watchdog，立即跑一轮（幂等，可反复运行）
# 用法（沙箱内）：
#   git clone -q --depth 1 https://github.com/1432151545/newapi-tasks.git /tmp/gt && bash /tmp/gt/repair.sh
set -u
B=$HOME/.hermes-gitbus
W=${BUS_WATCHDOG:-$HOME/workspace/bin/newapi-watchdog.sh}
echo "=== repair $(date -u +%FT%TZ) host=$(hostname) ==="

if [ ! -f "$W" ]; then echo "ERR: no watchdog at $W"; exit 1; fi
ls -l "$W"
cp -a "$W" "$W.pre-repair.$(date +%s)"

echo "--- 1) 归一化 poller 调用行（只留一行，绝对路径）---"
python3 - "$W" "$B" <<'PY'
import re, sys
w, b = sys.argv[1], sys.argv[2]
lines = open(w, encoding='utf-8', errors='replace').read().split('\n')
good = 'python3 "%s/muse_git_poller.py" >> "%s/git_poller.log" 2>&1 || true' % (b, b)
out, seen = [], False
for ln in lines:
    if re.search(r'muse_git_poller', ln):
        if not seen:
            out.append(good); seen = True
    else:
        out.append(ln)
if not seen:
    out.append(good)
open(w, 'w', encoding='utf-8').write('\n'.join(out))
print("poller invocation lines: %d" % (1 if seen else 1))
PY

echo "--- 2) 语法检查 ---"
if ! bash -n "$W"; then
  echo "SYNTAX BROKEN -> 回退到旧备份"
  L=$(ls -t "$W".bak.* "$W".pre-repair.* 2>/dev/null | head -1)
  echo "restore from: ${L:-none}"
  [ -n "$L" ] && cp -a "$L" "$W"
  if ! bash -n "$W"; then
    echo "回退后仍坏 -> 从最旧备份再试"
    L2=$(ls -tr "$W".bak.* "$W".pre-repair.* 2>/dev/null | head -1)
    [ -n "$L2" ] && cp -a "$L2" "$W"
  fi
fi
bash -n "$W" && echo "syntax OK" || echo "syntax STILL BROKEN"
echo "--- 当前 poller 行 ---"; grep -n 'muse_git_poller' "$W"

echo "--- 3) 重启 watchdog ---"
pkill -f 'newapi-watchdog.sh' 2>/dev/null && echo "(killed stale)" || echo "(none running)"
sleep 1
setsid nohup bash "$W" >> "$B/watchdog.out" 2>&1 </dev/null &
sleep 3
echo "watchdog pid(s): $(pgrep -f newapi-watchdog.sh | tr '\n' ' ')"

echo "--- 4) 立即跑一轮 poller ---"
python3 "$B/muse_git_poller.py" 2>&1 | tail -25
echo "--- poller log tail ---"; tail -8 "$B/git_poller.log" 2>/dev/null || echo "(no log)"

echo "--- 5) 立即跑一轮 sync（恢复心跳）---"
S="$B/sync_patch_from_pointer.sh"
if [ -f "$S" ]; then timeout 300 bash "$S" 2>&1 | tail -20; else echo "(no $S)"; fi

echo "=== repair done ==="