#!/bin/bash
# T-GITBOOT — 引导 git 任务通道：clone 公开任务库并安装轮询器（幂等）
# 之后所有任务都走 git（匿名 HTTPS 只读），本引导只需跑这一次。
#
# 多账号（2026-10-09）：本脚本是**角色感知**的。第二台沙箱（muse2）必须显式传角色：
#     BUS_ROLE=muse2 bash bootstrap.sh
# 不传则默认 muse（= 单账号旧行为，muse1 现状不变）。
# 角色决定该机认领哪些任务（target==角色 或 any），且写入心跳的 role 字段。
# 若 muse2 误用默认值，它会变成**第二个 muse**、与 muse1 抢同一批任务——所以下面有硬断言。
set -u
R=${BUS_REPO:-https://github.com/1432151545/newapi-tasks.git}
ROLE=${BUS_ROLE:-muse}
# 必须与 install.sh 用同一套状态目录解析，否则守卫会检查错目录（实测过）。
B=${BUS_STATE_DIR:-$HOME/.hermes-gitbus}
D=${BUS_REPO_DIR:-$B/tasks-repo}
mkdir -p "$B"

echo "=== T-GITBOOT nonce=${TASK_NONCE:-manual} ts=$(date -u +%FT%TZ) host=$(hostname) role=$ROLE ==="

# 硬断言：muse2 这台机器上如果已经存在 muse1 的状态目录（说明是同一台机跑第二份），
# 或者角色为空/非法，一律停下，避免静默变成第二个 muse。
case "$ROLE" in
  muse|muse2|sg) : ;;
  *) echo "FATAL: BUS_ROLE='$ROLE' 不是已知角色（muse|muse2|sg）"; exit 2 ;;
esac
if [ "$ROLE" = "muse2" ] && [ -f "$B/git_done.json" ] && [ ! -f "$B/.role-muse2" ]; then
  echo "FATAL: $B 已存在任务台账（疑似 muse1 的状态目录）。"
  echo "       muse2 请用独立的 BUS_STATE_DIR，例如："
  echo "       BUS_ROLE=muse2 BUS_STATE_DIR=\$HOME/.hermes-gitbus2 bash bootstrap.sh"
  exit 3
fi
touch "$B/.role-$ROLE"

echo "--- 1) clone/pull public task repo (anonymous HTTPS) ---"
if [ -d "$D/.git" ]; then
  git -C "$D" pull -q --ff-only || { git -C "$D" fetch -q --depth 1 origin main && git -C "$D" reset -q --hard FETCH_HEAD; }
else
  git clone -q --depth 1 "$R" "$D"
fi
echo "repo head: $(git -C "$D" rev-parse --short HEAD 2>/dev/null)"
echo "tasks: $(ls "$D/tasks" 2>/dev/null | tr '\n' ' ')"

echo "--- 2) install poller (role=$ROLE) ---"
# BUS_OUT_SLUG / BUS_OUT_CODE 由调用方传入（多账号必须各用独立回写页）。
# 不传也可：poller 会退回指针页（单账号旧行为）。
BUS_ROLE="$ROLE" ${BUS_OUT_SLUG:+BUS_OUT_SLUG="$BUS_OUT_SLUG" BUS_OUT_CODE="$BUS_OUT_CODE"} bash "$D/worker/install.sh" 2>&1 | tail -60

echo "--- 3) verify ---"
ls -l "$B/muse_git_poller.py" 2>/dev/null || echo "MISS poller"
grep -c 'poller' "$HOME/workspace/bin/newapi-watchdog.sh" 2>/dev/null | sed 's/^/watchdog poller lines: /'
echo "--- 4) role routing self-check (which tasks THIS box will claim) ---"
python3 - "$ROLE" "$D" <<'PYEOF'
import json, os, sys, datetime
role, d = sys.argv[1], sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc)
mine, skipped = [], 0
td = os.path.join(d, "tasks")
for tid in sorted(os.listdir(td)):
    f = os.path.join(td, tid, "task.json")
    if not os.path.isfile(f):
        continue
    t = json.load(open(f))
    tgt = t.get("target", "any")
    if tgt not in ("any", role):
        skipped += 1
        continue
    exp = t.get("expires")
    live = True
    if exp:
        try:
            live = datetime.datetime.strptime(exp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc) > now
        except Exception:
            live = "BAD_FORMAT(would still run!)"
    if live:
        mine.append("%s(target=%s)" % (tid, tgt))
print("CLAIMABLE by role=%s: %s" % (role, ", ".join(mine) if mine else "(none)"))
print("skipped (other role): %d" % skipped)
PYEOF
echo "=== BOOT DONE (role=$ROLE) ==="
