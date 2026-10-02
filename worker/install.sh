#!/bin/bash
# git 任务轮询器安装/更新（幂等，可反复运行）
# 调度策略：优先挂进沙箱已有的 newapi-watchdog.sh 常驻循环（复用现有 5 分钟节拍，
# 不新建任何定时器）；watchdog 不存在时回退 systemd timer / nohup 循环。
set -u
REPO=${BUS_REPO:-https://github.com/1432151545/newapi-tasks.git}
B=${BUS_STATE_DIR:-$HOME/.hermes-gitbus}
D=${BUS_REPO_DIR:-$B/tasks-repo}
WATCHDOG=${BUS_WATCHDOG:-$HOME/workspace/bin/newapi-watchdog.sh}
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
python3 - <<'PYEOF'
import ast, os
ast.parse(open(os.path.expanduser('~/.hermes-gitbus/muse_git_poller.py'), encoding='utf-8').read())
print("syntax OK")
PYEOF

echo "== 3) schedule =="
POLL_LINE="python3 \"$HOME/.hermes-gitbus/muse_git_poller.py\" >> \"$HOME/.hermes-gitbus/git_poller.log\" 2>&1 || true"
if [ -f "$WATCHDOG" ] && grep -q 'sync_patch_from_pointer' "$WATCHDOG"; then
  # watchdog 存在：在 sync 调用行后插入 poller 调用（幂等）
  if grep -q 'muse_git_poller.py' "$WATCHDOG"; then
    echo "watchdog already wired: $WATCHDOG"
  else
    cp "$WATCHDOG" "$WATCHDOG.bak.$(date +%s)"
    # 找到 sync 调用行，在其后追加 poller 行
    sed -i '/sync_patch_from_pointer/ a\'"$POLL_LINE" "$WATCHDOG"
    echo "watchdog wired: $WATCHDOG"
  fi
  grep -n 'muse_git_poller\|sync_patch_from_pointer' "$WATCHDOG" | head -5
elif command -v systemctl >/dev/null 2>&1 && S=$(systemctl is-system-running 2>/dev/null || true) && { [ "$S" = "running" ] || [ "$S" = "degraded" ]; }; then
  ENVF="$B/poller.env"
  { echo "PATH=$PATH"; env | grep -i proxy; } > "$ENVF" 2>/dev/null || true
  cat > /etc/systemd/system/git-task-poller.service <<EOF
[Unit]
Description=Git task poller (newapi-tasks)
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 $B/muse_git_poller.py
EOF
  cat > /etc/systemd/system/git-task-poller.timer <<EOF
[Unit]
Description=Run git task poller every 5 min

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF
  timeout 30 systemctl daemon-reload && timeout 30 systemctl enable --now git-task-poller.timer \
    && echo "systemd timer installed" && timeout 20 systemctl list-timers git-task-poller.timer --no-pager | head -3
else
  echo "watchdog/systemd 均不可用，使用 nohup 循环（重启后需重跑本脚本）"
  if ! pgrep -f "muse_git_poller.py" >/dev/null 2>&1; then
    setsid nohup bash -c "while true; do python3 $B/muse_git_poller.py >> $B/git_poller.log 2>&1; sleep 300; done" >/dev/null 2>&1 < /dev/null &
    echo "nohup loop started"
  else
    echo "poller already running"
  fi
fi

echo "== 4) first run =="
timeout 240 python3 "$B/muse_git_poller.py" 2>&1 | tail -40
echo "== install done =="
