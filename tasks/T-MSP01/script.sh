#!/bin/bash
# Muse 能力探针（只读，无副作用；用于决定 agent 执行器与产物回传通道）
set -u
echo "MUSE-PROBE-01"
echo "host=$(hostname)"
echo "user=$(whoami)"
echo "role=${BUS_ROLE:-unset}"
echo "date=$(date -u +%FT%TZ)"
echo "kernel=$(uname -sr)"
echo "nproc=$(nproc 2>/dev/null)"
echo "mem_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
echo "home=$(echo $HOME)"
echo "disk_home=$(df -h "$HOME" 2>/dev/null | awk 'NR==2{print $2" total / "$4" avail"}')"
echo "--- tools ---"
for t in codex go docker node npm npx python3 git curl wget tar gzip unzip jq openssl; do
  p=$(command -v "$t" 2>/dev/null)
  echo "tool.$t=${p:-NONE}"
done
echo "--- codex candidates ---"
for c in /opt/hatch-image/bin/codex /usr/local/bin/codex "$HOME/.local/bin/codex" /opt/codex/bin/codex; do
  [ -x "$c" ] && echo "codex.cand=$c"
done
echo "--- egress ---"
for u in https://github.com https://rentry.co https://catbox.moe https://litterbox.catbox.moe https://transfer.sh https://0x0.st https://file.io https://tmpfiles.org https://dl.google.com https://proxy.golang.org https://api.github.com; do
  code=$(curl -s -o /dev/null -m 8 -w '%{http_code}' "$u" 2>/dev/null || echo ERR)
  echo "egress.$u=$code"
done
echo "--- write test ---"
if echo "probe-$(date +%s)" > "$HOME/.muse_probe_write_test" 2>/dev/null; then
  echo "home_write=OK"
  rm -f "$HOME/.muse_probe_write_test"
else
  echo "home_write=FAIL"
fi
echo "MUSE-PROBE-01-END"
