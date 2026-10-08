#!/bin/bash
# T-MUSE-PROBE01: 通道与工具链探针（只读）
echo "== HOST =="
echo "host=$(hostname) user=$(whoami) date=$(date -u +%FT%TZ)"
echo "nproc=$(nproc)"
free -m 2>/dev/null | head -2
df -h "$HOME" / 2>/dev/null | tail -2
echo
echo "== TOOLCHAIN =="
for c in go docker bun node npm python3 git curl tar unzip unshare openssl; do
  printf "  %-9s %s\n" "$c" "$(command -v "$c" 2>/dev/null || echo MISSING)"
done
echo "  go_ver=$(go version 2>/dev/null || echo none)"
echo
echo "== EGRESS (status code, max 20s each) =="
for u in \
  "https://github.com/" \
  "https://raw.githubusercontent.com/QuantumNous/new-api/main/README.md" \
  "https://codeload.github.com/QuantumNous/new-api/tar.gz/refs/tags/v1.0.0-rc.42" \
  "https://files.catbox.moe/8g7nxn.bin" \
  "https://catbox.moe/" \
  "https://litter.catbox.moe/" \
  "https://tmpfiles.org/" \
  "https://envs.sh/" \
  "https://d.uguu.se/jAEKcSpf.bin" \
  "https://rentry.co/hermes-muse-ptr/edit" \
  "https://dl.google.com/go/go1.26.1.linux-amd64.tar.gz" \
  "https://proxy.golang.org/" \
  ; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -A "Mozilla/5.0" "$u" 2>/dev/null)
  printf "  %-4s %s\n" "${code:-ERR}" "$u"
done
echo
echo "== REAL DOWNLOAD TEST =="
T=$(mktemp -d)
code=$(curl -sL --max-time 40 -A "Mozilla/5.0" -o "$T/a.bin" -w '%{http_code}' "https://files.catbox.moe/8g7nxn.bin" 2>/dev/null)
sz=$(stat -c %s "$T/a.bin" 2>/dev/null || echo 0)
echo "  catbox 200KB: http=$code bytes=$sz expect=200000"
echo "  catbox_sha=$(sha256sum "$T/a.bin" 2>/dev/null | cut -d' ' -f1)"
code2=$(curl -sL --max-time 40 -A "Mozilla/5.0" -o "$T/b.bin" -w '%{http_code}' "https://d.uguu.se/jAEKcSpf.bin" 2>/dev/null)
sz2=$(stat -c %s "$T/b.bin" 2>/dev/null || echo 0)
echo "  uguu 200KB: http=$code2 bytes=$sz2 expect=200000"
rm -rf "$T"
echo
echo "== LOCAL ENV =="
echo "  newapi_test=$(ls -d "$HOME/newapi-test" 2>/dev/null || echo none)"
echo "  disk_free=$(df -m "$HOME" | awk 'NR==2{print $4}')MB"
echo PROBE_DONE
