#!/bin/bash
# 探测 codex CLI 的非交互用法（决定 BUS_EXEC 模板）；只读
set -u
CX=/opt/hatch-image/bin/codex
echo "MUSE-CODEX-PROBE"
echo "date=$(date -u +%FT%TZ)"
echo "--- version ---"
timeout 30 "$CX" --version 2>&1 | head -3
echo "--- top-level help ---"
timeout 30 "$CX" --help 2>&1 | head -40
echo "--- exec subcommand help ---"
timeout 30 "$CX" exec --help 2>&1 | head -45
echo "--- auth/model config hints ---"
env | grep -iE 'codex|openai|anthropic|model|api_key|token' | sed -E 's/=(.{0,6}).*/=\1***/' | head -12
ls -la /opt/hatch-image/ 2>/dev/null | head -12
echo "MUSE-CODEX-PROBE-END"
