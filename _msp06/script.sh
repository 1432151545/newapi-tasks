#!/usr/bin/env bash
# T-MSP06 验证探针（只读）：解卡后 Muse 60s poller 循环是否复活？
echo "host=$(hostname)"
echo "utc=$(date -u +%FT%TZ)"
echo "uptime_sec=$(cut -d' ' -f1 /proc/uptime)"
echo "poller_procs=$(pgrep -fc 'muse_git_poller.py' 2>/dev/null || echo 0)"
echo "codex_procs=$(pgrep -fc 'codex' 2>/dev/null || echo 0)"
echo "loop_procs=$(pgrep -fc 'while true' 2>/dev/null || echo 0)"
echo "self_ver=$(grep -m1 -o 'gitpoller-[0-9]*' "$HOME/.hermes-gitbus/muse_git_poller.py" 2>/dev/null || echo none)"
echo "self_sha=$(sha256sum "$HOME/.hermes-gitbus/muse_git_poller.py" 2>/dev/null | cut -d' ' -f1)"
echo "sync_sh_sha=$(sha256sum "$HOME/newapi-test/sync_patch_from_pointer.sh" 2>/dev/null | cut -d' ' -f1)"
echo "--- patch-sync.log (tail 10) ---"
tail -10 "$HOME/newapi-test/patch-sync.log" 2>/dev/null || echo "(none)"
echo "--- git_poller.log (tail 10) ---"
tail -10 "$HOME/.hermes-gitbus/git_poller.log" 2>/dev/null || echo "(none)"
echo "--- git_poller.log 最后一行时间戳 ---"
tail -1 "$HOME/.hermes-gitbus/git_poller.log" 2>/dev/null | cut -c1-24
