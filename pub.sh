#!/bin/bash
# HK 侧：发布任务到公开库 1432151545/newapi-tasks
# 用法：pub.sh <task_id> <type> <target> <nonce> <timeout> <task_dir> [note]
#   task_dir 内含 script.sh（type=script）或 prompt.md（type=agent）；自动算 sha256 写 task.json
set -euo pipefail
REPO_DIR=/root/gitbus-tasks
TID=${1:?task id}
TYPE=${2:-script}
TARGET=${3:-any}
NONCE=${4:?nonce}
TMO=${5:-900}
SRC=${6:?task dir}
NOTE=${7:-}

cd "$REPO_DIR"
[ -d .git ] || { echo "ERR: $REPO_DIR not a git repo"; exit 1; }
git remote get-url origin >/dev/null 2>&1 || git remote add origin git@github.com:1432151545/newapi-tasks.git
DST="tasks/$TID"
mkdir -p "$DST"
FILES_JSON="{"
if [ "$TYPE" = "script" ]; then
  install -m 755 "$SRC/script.sh" "$DST/script.sh"
  H=$(sha256sum "$DST/script.sh" | cut -d' ' -f1)
  FILES_JSON="$FILES_JSON\"script.sh\": \"$H\""
elif [ "$TYPE" = "agent" ]; then
  install -m 644 "$SRC/prompt.md" "$DST/prompt.md"
  H=$(sha256sum "$DST/prompt.md" | cut -d' ' -f1)
  FILES_JSON="$FILES_JSON\"prompt.md\": \"$H\""
fi
FILES_JSON="$FILES_JSON}"
cat > "$DST/task.json" <<EOF
{
  "id": "$TID",
  "type": "$TYPE",
  "target": "$TARGET",
  "nonce": "$NONCE",
  "timeout": $TMO,
  "created": "$(date -u +%FT%TZ)",
  "note": "$NOTE",
  "files": $FILES_JSON
}
EOF
git add -A "$DST" README.md worker 2>/dev/null || git add -A
git -c user.name=hermes -c user.email=hermes@local commit -q -m "task $TID ($TYPE/$TARGET)" || echo "(nothing to commit)"
git push -q origin main
echo "PUBLISHED $TID $(git rev-parse --short HEAD)"
