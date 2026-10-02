#!/bin/bash
# T-GITBOOT — 引导 git 任务通道：clone 公开任务库并安装轮询器（幂等）
# 之后所有任务都走 git（匿名 HTTPS 只读），本引导只需跑这一次。
set -u
R=${BUS_REPO:-https://github.com/1432151545/newapi-tasks.git}
B=$HOME/.hermes-gitbus
D=$B/tasks-repo
mkdir -p "$B"

echo "=== T-GITBOOT nonce=$TASK_NONCE ts=$(date -u +%FT%TZ) host=$(hostname) ==="
echo "--- 1) clone/pull public task repo (anonymous HTTPS) ---"
if [ -d "$D/.git" ]; then
  git -C "$D" pull -q --ff-only || { git -C "$D" fetch -q --depth 1 origin main && git -C "$D" reset -q --hard FETCH_HEAD; }
else
  git clone -q --depth 1 "$R" "$D"
fi
echo "repo head: $(git -C "$D" rev-parse --short HEAD 2>/dev/null)"
echo "tasks: $(ls "$D/tasks" 2>/dev/null | tr '\n' ' ')"

echo "--- 2) install poller ---"
bash "$D/worker/install.sh" 2>&1 | tail -60

echo "--- 3) verify ---"
ls -l "$B/muse_git_poller.py" 2>/dev/null || echo "MISS poller"
grep -c 'poller' "$HOME/workspace/bin/newapi-watchdog.sh" 2>/dev/null | sed 's/^/watchdog poller lines: /'
echo "=== BOOT DONE ==="
