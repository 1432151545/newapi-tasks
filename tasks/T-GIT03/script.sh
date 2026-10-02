#!/bin/bash
echo "=== T-GIT03 nonce=${TASK_NONCE:-none} ts=$(date -u +%FT%TZ) host=$(hostname) ==="
echo "--- 1) poller/watchdog 进程 ---"
ps -eo pid,ppid,etime,cmd 2>/dev/null | grep -E 'muse_git_poller|newapi-watchdog' | grep -v grep || echo "(none)"
echo "--- 2) poller 文件副本 ---"
find / -name 'muse_git_poller.py' -not -path '*/proc/*' 2>/dev/null | head -20
echo "--- 3) watchdog 里的 poller 行 / set -u ---"
grep -n 'muse_git_poller\|set -u' "$HOME/workspace/bin/newapi-watchdog.sh" 2>/dev/null || echo "(no match)"
echo "--- 4) 状态目录 ---"
ls -la "$HOME/.hermes-gitbus/" 2>/dev/null
echo "--- 5) git_done.json ---"
cat "$HOME/.hermes-gitbus/git_done.json" 2>/dev/null; echo
echo "--- 6) agent_inbox ---"
ls -la "$HOME/.hermes-gitbus/agent_inbox/" 2>/dev/null || echo "(no agent_inbox)"
echo "--- 7) agent-outbox-report.py 位置 ---"
find / -name 'agent-outbox-report*' -not -path '*/proc/*' 2>/dev/null | head
echo "--- 8) 每个 poller 进程的完整命令行 ---"
for p in $(pgrep -f 'muse_git_poller' 2>/dev/null); do echo "pid=$p :: $(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)"; done
echo "--- 9) poller log tail ---"
tail -18 "$HOME/.hermes-gitbus/git_poller.log" 2>/dev/null
echo "--- 10) 本机 .hermes 目录线索 ---"
ls -d "$HOME"/.hermes* "$HOME"/workspace 2>/dev/null
echo "=== END ==="