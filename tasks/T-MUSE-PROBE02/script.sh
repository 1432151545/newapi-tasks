#!/bin/bash
# T-MUSE-PROBE02: muse1 liveness + bus E2E probe (read-only, safe)
echo "== HOST =="
echo "host=$(hostname) user=$(whoami) role=${BUS_ROLE:-muse} date=$(date -u +%FT%TZ)"
echo "nproc=$(nproc)"
free -m 2>/dev/null | head -2
df -h "$HOME" / 2>/dev/null | tail -2
echo
echo "== BUS STATE DIR =="
S="$HOME/.hermes-gitbus"
echo "state_dir=$S exists=$([ -d "$S" ] && echo yes || echo no)"
ls -la "$S" 2>/dev/null | head -20
echo "  poller_sha=$(sha256sum "$S/muse_git_poller.py" 2>/dev/null | cut -c1-16)"
echo "  worker_sha=$(sha256sum "$S/bus_worker_relay.py" 2>/dev/null | cut -c1-16)"
echo
echo "== POLLER / WATCHDOG RUNNING? =="
ps -eo pid,etimes,args 2>/dev/null | grep -E "muse_git_poller|bus_worker_relay|newapi-watchdog" | grep -v grep | head -10
echo "  (empty above = no poller process)"
echo
echo "== POLLER LOG TAIL =="
tail -25 "$S/git_poller.log" 2>/dev/null || echo "  (no git_poller.log)"
echo
echo "== DONE / PENDING LEDGER =="
echo "  git_done.json: $(head -c 500 "$S/git_done.json" 2>/dev/null || echo none)"
echo "  pending_recs.json: $(head -c 500 "$S/pending_recs.json" 2>/dev/null || echo none)"
echo
echo "== TASK REPO =="
R="$S/tasks-repo"
if [ -d "$R/.git" ]; then
  echo "  head=$(git -C "$R" log -1 --format='%H %ad %s' --date=iso 2>/dev/null)"
  echo "  remote=$(git -C "$R" remote get-url origin 2>/dev/null)"
  echo "  newest task dirs:"; ls -t "$R/tasks" 2>/dev/null | head -5 | sed 's/^/    /'
else
  echo "  NO tasks-repo at $R"
fi
echo
echo "== EGRESS =="
for u in "https://github.com/" "https://codeload.github.com/QuantumNous/new-api/tar.gz/refs/tags/v1.0.0-rc.43" "https://rentry.co/hermes-muse-ptr/edit"; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -A "Mozilla/5.0" "$u" 2>/dev/null)
  printf "  %-4s %s\n" "${code:-ERR}" "$u"
done
echo
echo "== SANDBOX TEST SERVICE =="
echo "  tunnel-url.txt: $(cat "$HOME/newapi-test/tunnel-url.txt" 2>/dev/null || echo none)"
curl -s -o /dev/null -w '  local:3000 http=%{http_code}\n' --max-time 5 "http://127.0.0.1:3000/api/status" 2>/dev/null || echo "  local:3000 unreachable"
echo
echo "PROBE02_DONE"