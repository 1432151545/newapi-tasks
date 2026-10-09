#!/bin/bash
# git 任务轮询器安装/更新 v2（2026-10-02 修订）
# 调度策略：单一 60s nohup 循环为唯一调度器。绝不杀已有循环、绝不改 watchdog、绝不用 systemd
# （本容器 systemd 是空壳：timer active 但 service 必 failed——2026-10-01 实测）。
set -u
REPO=${BUS_REPO:-https://github.com/1432151545/newapi-tasks.git}
# 角色：决定本机认领哪些任务（target == BUS_ROLE 或 any）。默认 muse（单账号旧行为不变）。
# 第二台沙箱必须显式传 BUS_ROLE=muse2，否则会退化成第二个 "muse"，与 muse1 抢同一批任务。
ROLE=${BUS_ROLE:-muse}
B=${BUS_STATE_DIR:-$HOME/.hermes-gitbus}
D=${BUS_REPO_DIR:-$B/tasks-repo}
mkdir -p "$B"

echo "== role = $ROLE =="

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
# 关键：角色与回写页凭据必须烧进循环体。只 export 到本脚本是不够的——setsid nohup bash -c
# 起的是新 shell，不继承非导出的变量；更稳妥的是用 `env` 前缀显式传进循环里的每一次 python3。
# ⚠️ 路径必须用 \$B 而不是 \$HOME/.hermes-gitbus：muse2 用独立状态目录，写死 HOME 会装错位置。
# ⚠️ BUS_OUT_SLUG/BUS_OUT_CODE 也要烧进循环：否则 muse2 每轮都从共享指针页取凭据，
#    回写到 muse1 的 outbox 上（多账号必须各自一页，见 README「多账号」）。
OUTENV="BUS_ROLE='$ROLE'"
[ -n "${BUS_OUT_SLUG:-}" ] && OUTENV="$OUTENV BUS_OUT_SLUG='$BUS_OUT_SLUG'"
[ -n "${BUS_OUT_CODE:-}" ] && OUTENV="$OUTENV BUS_OUT_CODE='$BUS_OUT_CODE'"
N=$(pgrep -af 'muse_git_poller.py' | grep -c 'while true' || true)
if [ "${N:-0}" -eq 0 ]; then
  setsid nohup bash -c "while true; do env $OUTENV python3 \"\$B/muse_git_poller.py\" >> \"\$B/git_poller.log\" 2>&1; sleep 60; done" </dev/null >/dev/null 2>&1 &
  echo "60s loop started ($OUTENV, state=$B)"
else
  echo "60s loop already running ($N), left alone"
fi

echo "== 4) first run (echo) =="
env $OUTENV BUS_LOG_ECHO=1 timeout 240 python3 "$B/muse_git_poller.py" 2>&1 | tail -30
echo "== install done (role=$ROLE) =="