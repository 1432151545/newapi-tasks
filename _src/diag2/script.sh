#!/bin/bash
# T-GITDIAG2 — 经 rentry 通道（仍活）诊断 git 轮询器为何不回执
B=$HOME/.hermes-gitbus
echo "=== T-GITDIAG2 nonce=${TASK_NONCE:-none} ts=$(date -u +%FT%TZ) host=$(hostname) ==="

echo "--- 1) poller/watchdog 进程 ---"
ps -eo pid,ppid,etime,cmd 2>/dev/null | grep -E 'muse_git_poller|newapi-watchdog' | grep -v grep || echo "(none)"

echo "--- 2) 所有 poller 副本 ---"
find / -name 'muse_git_poller.py' -not -path '*/proc/*' 2>/dev/null | head -20

echo "--- 3) lock 文件状态 ---"
ls -la "$B"/*.lock 2>/dev/null || echo "(no lock files)"

echo "--- 4) git_done.json ---"
cat "$B/git_done.json" 2>/dev/null; echo

echo "--- 5) repo 内任务 ---"
ls "$B/tasks-repo/tasks" 2>/dev/null || echo "(no repo tasks dir)"

echo "--- 6) agent_inbox ---"
ls -la "$B/agent_inbox" 2>/dev/null || echo "(NO agent_inbox)"

echo "--- 7) agent-outbox-report.py 是否存在 ---"
R=$(find / -name 'agent-outbox-report*' -not -path '*/proc/*' 2>/dev/null | head -5)
echo "${R:-（本机不存在该文件）}"

echo "--- 8) 手动跑一次 poller（捕获全部输出）---"
timeout 300 python3 "$B/muse_git_poller.py" 2>&1 | tail -45
echo "   poller rc=$?"

echo "--- 9) poller log tail ---"
tail -25 "$B/git_poller.log" 2>/dev/null || echo "(no log)"

echo "--- 10) 手动跑一次 sync（既有通道）---"
S="$B/sync_patch_from_pointer.sh"
if [ -f "$S" ]; then timeout 300 bash "$S" 2>&1 | tail -25; else echo "(no sync script)"; fi

echo "--- 11) 出网自检 ---"
timeout 20 curl -s -o /dev/null -w "github raw http=%{http_code}\n" https://raw.githubusercontent.com/1432151545/newapi-tasks/main/README.md
echo "=== END ==="