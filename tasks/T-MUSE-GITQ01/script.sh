#!/bin/bash
# T-MUSE-GITQ01: git 侧只读取证 —— 回答「推到哪个仓/分支、push 返回什么、是否推错库」
echo "== HOST =="
echo "host=$(hostname) user=$(whoami) date=$(date -u +%FT%TZ)"
echo
echo "== GIT REPOS FOUND =="
repos=$(find "$HOME" /opt /srv /data /tmp /var -maxdepth 5 -name .git -type d 2>/dev/null | head -15)
[ -z "$repos" ] && echo "  NONE (no git repo on this box)"
for g in $repos; do
  r=$(dirname "$g")
  echo "[$r]"
  echo "  remote : $(git -C "$r" remote -v 2>/dev/null | tr '\n' ' ')"
  echo "  branch : $(git -C "$r" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "  head   : $(git -C "$r" log -1 --format='%H %ad %s' --date=iso 2>/dev/null)"
  echo "  dirty  : $(git -C "$r" status --porcelain 2>/dev/null | wc -l) files"
  echo "  reflog :"
  git -C "$r" reflog --date=iso 2>/dev/null | head -6 | sed 's/^/    /'
  echo "  branches:"
  git -C "$r" branch -a 2>/dev/null | head -6 | sed 's/^/    /'
done
echo
echo "== PUSH CREDENTIALS (existence only, no values) =="
ls -1 "$HOME/.ssh" 2>/dev/null | head -6 | sed 's/^/  ssh: /'
echo "  git-credentials: $(ls "$HOME/.git-credentials" 2>/dev/null || echo none)"
echo "  env vars: $(env | grep -oE '^(GIT[A-Z_]*|GITHUB[A-Z_]*)' | sort -u | tr '\n' ' ')"
echo
echo "== GLOBAL GITCONFIG (values masked) =="
git config --global --list 2>/dev/null | sed -E 's/(token|password|pat)=[^ ]*/\1=<REDACTED>/Ig' | head -8 | sed 's/^/  /'
echo
echo "== GIT IN SHELL HISTORY =="
found=0
for h in "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.sh_history"; do
  if [ -f "$h" ]; then
    grep -a 'git ' "$h" 2>/dev/null | tail -12 | sed "s|^|  |"
    found=1
  fi
done
[ "$found" = "0" ] && echo "  (no shell history file)"
echo
echo "== WORKER TRACES =="
find "$HOME" -maxdepth 4 \( -name '*outbox*' -o -name '*receipt*' -o -name '*worker*.log' -o -name '*task*.log' \) 2>/dev/null | head -10 | sed 's/^/  /'
echo
echo "== FILES TOUCHED SINCE 2026-10-08 14:00Z =="
find "$HOME" -maxdepth 4 -newermt '2026-10-08 14:00' -type f 2>/dev/null | grep -vE '/\.git/' | head -12 | sed 's/^/  /'
echo GITQ_DONE
