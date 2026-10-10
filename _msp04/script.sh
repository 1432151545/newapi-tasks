#!/bin/bash
# 决定性：codex 能否真调通模型（认证 + 非交互执行）
set -u
CX=/opt/hatch-image/bin/codex
echo "MUSE-CODEX-PROBE3"
echo "date=$(date -u +%FT%TZ)"
echo "=== login status ==="
timeout 40 "$CX" login status 2>&1 | head -8
echo "=== attempt A: bypass approvals, workspace-write sandbox ==="
cd /tmp && mkdir -p codprobe && cd codprobe
printf 'Reply with exactly this token and nothing else: CODEX_EXEC_OK\n' > p.txt
timeout 240 "$CX" exec --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox - < p.txt 2>&1 | tail -30
echo "=== attempt B: output-last-message probe ==="
timeout 240 "$CX" exec --skip-git-repo-check -s workspace-write -o /tmp/codprobe/last.txt "Write the token CODEX_EXEC_OK to the file out.txt in the current directory" 2>&1 | tail -20
echo "--- last.txt ---"; cat /tmp/codprobe/last.txt 2>/dev/null | head -10
echo "--- out.txt ---"; cat /tmp/codprobe/out.txt 2>/dev/null | head -5
echo "MUSE-CODEX-PROBE3-END"