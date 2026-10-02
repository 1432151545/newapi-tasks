#!/bin/bash
# 验证「回传到 git」通道：任务走 git 下发 → 沙箱执行 → 回执 push 回独立回执库
set -e
echo "RECEIPT-VIA-GIT E2E"
echo "host=$(hostname)"
echo "user=$(whoami)"
echo "date=$(date -u +%FT%TZ)"
echo "git_version=$(git --version)"
echo "poller_role=${BUS_ROLE:-unknown}"
echo "nonce=NONCE-GIT-RECEIPT-001"
echo "receipts_repo_live_probe=http_$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 https://github.com/1432151545/newapi-receipts)"