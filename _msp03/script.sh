#!/bin/bash
# 决定性探针：codex 全参数 + 认证状态 + 一次真实最小执行
set -u
CX=/opt/hatch-image/bin/codex
echo "MUSE-CODEX-PROBE2"
echo "date=$(date -u +%FT%TZ)"
echo "=== full exec help (approval/sandbox flags) ==="
timeout 30 "$CX" exec --help 2>&1 | grep -iE 'full-auto|approval|sandbox|dangerous|skip|yes|json|cd |output|ephemeral|color' | head -30
echo "=== login status ==="
timeout 30 "$CX" login --help 2>&1 | head -20
echo "--- auth files ---"
ls -la "$HOME/.codex" 2>/dev/null | head -10
[ -f "$HOME/.codex/auth.json" ] && echo "auth.json EXISTS" || echo "no auth.json"
echo "=== minimal real run (no repo needed) ==="
cd /tmp && mkdir -p codprobe && cd codprobe
printf 'Reply with exactly: CODEX_EXEC_OK\n' > p.txt
timeout 180 "$CX" exec --full-auto - < p.txt 2>&1 | tail -25
echo "rc=$?"
echo "MUSE-CODEX-PROBE2-END"