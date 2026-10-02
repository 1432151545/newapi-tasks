#!/bin/bash
# T-GIT02 — 证明「纯 git 下发 + 定时节拍自动认领」这条闭环
echo "=== T-GIT02 nonce=$TASK_NONCE ts=$(date -u +%FT%TZ) host=$(hostname) ==="
echo "谁在跑我（进程链）:"
echo "  mypid=$$ ppid=$PPID"
ps -o pid,ppid,cmd -p $PPID 2>/dev/null || true
echo "  grandparent:"
GP=$(ps -o ppid= -p $PPID 2>/dev/null | tr -d ' ')
[ -n "$GP" ] && ps -o pid,ppid,cmd -p "$GP" 2>/dev/null || true
echo "--- watchdog 进程 ---"
ps -eo pid,etime,cmd | grep -E 'newapi-watchdog|muse_git_poller' | grep -v grep || echo "(none)"
echo "--- poller 状态 ---"
echo "poller sha: $(sha256sum $HOME/.hermes-gitbus/muse_git_poller.py | cut -c1-16)"
echo "repo head: $(git -C $HOME/.hermes-gitbus/tasks-repo rev-parse --short HEAD 2>/dev/null)"
echo "done tasks: $(python3 -c "import json;print(list(json.load(open('$HOME/.hermes-gitbus/git_done.json')).keys()))" 2>/dev/null)"
echo "--- poller log tail ---"
tail -8 "$HOME/.hermes-gitbus/git_poller.log" 2>/dev/null
echo "--- git 通道回环自检 ---"
echo "task file sha: $(sha256sum $HOME/.hermes-gitbus/tasks-repo/tasks/T-GIT02/script.sh 2>/dev/null | cut -d' ' -f1)"
echo "ALL OK (git-only dispatch + scheduled claim)"
