#!/bin/bash
# git 任务轮询器安装/更新 v2（2026-10-02 修订）
# 调度策略：单一 60s nohup 循环为唯一调度器。绝不杀已有循环、绝不改 watchdog、绝不用 systemd
# （本容器 systemd 是空壳：timer active 但 service 必 failed——2026-10-01 实测）。
set -u
REPO=${BUS_REPO:-https://github.com/1432151545/newapi-tasks.git}
B=${BUS_STATE_DIR:-$HOME/.hermes-gitbus}
D=${BUS_REPO_DIR:-$B/tasks-repo}
mkdir -p "$B"

echo "== 1) fetch repo =="
if [ -d "$D/.git" ]; then
  git -C "$D" pull -q --ff-only || { git -C "$D" fetch -q --depth 1 origin main && git -C "$D" reset -q --hard FETCH_HEAD; }
else
  git clone -q --depth 1 "$REPO" "$D"
fi
echo "repo head: $(git -C "$D" rev-parse --short HEAD 2>/dev/null)"
echo "tasks: $(ls "$D/tasks" 2>/dev/null | tr '\n' ' ')"

echo "== 2) install poller =="
install -m 755 "$D/worker/muse_git_poller.py" "$B/muse_git_poller.py"
python3 - "$B/muse_git_poller.py" <<'PYEOF'
import ast, sys
ast.parse(open(sys.argv[1], encoding='utf-8').read())
print("syntax OK")
PYEOF

echo "== 3) ensure single 60s loop (never kill existing, never touch watchdog) =="
N=$(pgrep -af 'muse_git_poller.py' | grep -c 'while true' || true)
if [ "${N:-0}" -eq 0 ]; then
  setsid nohup bash -c 'while true; do python3 "$HOME/.hermes-gitbus/muse_git_poller.py" >> "$HOME/.hermes-gitbus/git_poller.log" 2>&1; sleep 60; done' </dev/null >/dev/null 2>&1 &
  echo "60s loop started"
else
  echo "60s loop already running ($N), left alone"
fi

echo "== 4) first run (echo) =="
BUS_LOG_ECHO=1 timeout 240 python3 "$B/muse_git_poller.py" 2>&1 | tail -30
echo "== install done =="