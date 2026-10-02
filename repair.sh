#!/bin/bash
# repair.sh v4（2026-10-02 修订）—— 只诊断 + 保活单一 60s 循环。
# 铁律：绝不杀进程、绝不改 watchdog、绝不用 systemd（本容器 systemd 是空壳：
#       timer active 但 service 必 failed，2026-10-01 实测）。
# 幂等，可反复运行。用法（沙箱内）：
#   rm -rf /tmp/gt && git clone -q --depth 1 https://github.com/1432151545/newapi-tasks.git /tmp/gt && bash /tmp/gt/repair.sh 2>&1
set -u
B=${BUS_STATE_DIR:-$HOME/.hermes-gitbus}
D=${BUS_REPO_DIR:-$B/tasks-repo}
REPO=${BUS_REPO:-https://github.com/1432151545/newapi-tasks.git}
W=${BUS_WATCHDOG:-$HOME/workspace/bin/newapi-watchdog.sh}
SLUG=${BUS_OUT_SLUG:-hermes-rx-r6qytd4}
echo "=== repair4 $(date -u +%FT%TZ) host=$(hostname) home=$HOME ==="

echo; echo "== A) 现状取证（只读）=="
echo "--- 相关进程（loop / watchdog / sync）---"
ps -eo pid,ppid,etime,cmd 2>/dev/null | grep -E 'muse_git_poller|newapi-watchdog|sync_patch' | grep -v grep | head -10 || echo "(none)"
echo "--- watchdog 文件（只读，不动）---"
ls -la "$W" 2>/dev/null || echo "(no watchdog)"
grep -n 'muse_git_poller\|set -u' "$W" 2>/dev/null | head -5 || true
echo "--- gitbus 状态目录 ---"
ls -la "$B" 2>/dev/null | head -15
echo "--- done 台账 ---"
python3 -c "import json,os;p=os.path.join('$B','git_done.json');d=json.load(open(p)) if os.path.exists(p) else {};print(sorted(d.keys()))" 2>/dev/null || echo "(none)"
echo "--- pending 待发回执 ---"
python3 -c "import json,os;p=os.path.join('$B','pending_recs.json');d=json.load(open(p)) if os.path.exists(p) else {};print(len(d), sorted(d.keys()))" 2>/dev/null || echo "(none)"

echo; echo "== B) 更新轮询器（自更新链：pull → 替换文件 → 下一轮 re-exec）=="
if [ -d "$D/.git" ]; then
  git -C "$D" pull -q --ff-only 2>/dev/null || { git -C "$D" fetch -q --depth 1 origin main && git -C "$D" reset -q --hard FETCH_HEAD; }
else
  git clone -q --depth 1 "$REPO" "$D"
fi
echo "repo head=$(git -C "$D" rev-parse --short HEAD 2>/dev/null)"
install -m 755 "$D/worker/muse_git_poller.py" "$B/muse_git_poller.py" && echo "poller installed"
grep -m1 '^VER = ' "$B/muse_git_poller.py"

echo; echo "== C) 保活单一 60s 循环（已有则不动，不杀）=="
N=$(pgrep -af 'muse_git_poller.py' 2>/dev/null | grep -c 'while true' || true)
if [ "${N:-0}" -eq 0 ]; then
  setsid nohup bash -c 'while true; do python3 "$HOME/.hermes-gitbus/muse_git_poller.py" >> "$HOME/.hermes-gitbus/git_poller.log" 2>&1; sleep 60; done' </dev/null >/dev/null 2>&1 &
  echo "60s loop started"
else
  echo "60s loop already running ($N), left alone"
fi

echo; echo "== D) 跑一轮（先补发 pending 回执，再认领一个任务）=="
BUS_LOG_ECHO=1 timeout 240 python3 "$B/muse_git_poller.py" 2>&1 | tail -30

echo; echo "== E) 收尾状态 =="
echo "pending=$(python3 -c "import json,os;p=os.path.join('$B','pending_recs.json');print(len(json.load(open(p))) if os.path.exists(p) else 0)" 2>/dev/null)"
echo "loops=$(pgrep -af 'muse_git_poller.py' 2>/dev/null | grep -c 'while true' || true)"
echo "--- poller log tail(12) ---"
tail -12 "$B/git_poller.log" 2>/dev/null || echo "(no log)"
echo "=== repair4 done ==="