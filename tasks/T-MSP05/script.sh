#!/bin/bash
echo "MUSE-HEARTBEAT-05"
echo "date=$(date -u +%FT%TZ)"
echo "host=$(hostname)"
echo "poller_proc=$(pgrep -fc 'muse_git_poller' 2>/dev/null || echo 0)"
echo "running_codex=$(pgrep -fc 'codex' 2>/dev/null || echo 0)"
echo "MUSE-HEARTBEAT-05-END"
