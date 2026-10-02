#!/bin/bash
# T-GIT01 — 第一条通过公开 git 通道投递的任务
echo "HELLO-via-git nonce=$TASK_NONCE task=$TASK_ID ts=$(date -u +%FT%TZ)"
echo "host=$(hostname) user=$(id -un)"
echo "repo_head=$(git -C "$HOME/.hermes-gitbus/tasks-repo" rev-parse --short HEAD 2>/dev/null)"
echo "poller_log_tail:"
tail -5 "$HOME/.hermes-gitbus/git_poller.log" 2>/dev/null || echo "(no poller log)"
echo "ALL OK"
