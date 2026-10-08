#!/bin/bash
# 实测 25MB 源码包在各通道的可下载性（含重试）
set -u
W=/home/hatch/dlchan; mkdir -p "$W"; cd "$W"
WANT=25411226
try(){ # name url
  n="$1"; u="$2"
  for i in 1 2 3; do
    rm -f f.bin
    code=$(curl -sL --max-time 300 -o f.bin -w '%{http_code}' -A "Mozilla/5.0" "$u" 2>/dev/null)
    sz=$(stat -c %s f.bin 2>/dev/null || echo 0)
    if [ "$sz" = "$WANT" ]; then
      sha=$(sha256sum f.bin | cut -d" " -f1)
      echo "  OK   $n try=$i http=$code bytes=$sz sha=$sha"
      return 0
    fi
    echo "  retry $n try=$i http=$code bytes=$sz"
    sleep 5
  done
  echo "  FAIL $n  last_http=$code last_bytes=$sz"
  return 1
}
echo "== 25MB 通道实测 =="
try catbox_perm "https://files.catbox.moe/sulpe4.gz"
try uguu_d      "https://d.uguu.se/zfbDllzX.tar.gz"
try uguu_n      "https://n.uguu.se/whecJVQD.tar.gz"
try tmpfiles    "https://tmpfiles.org/dl/whA6g0nI2wsi/napatch42.tar.gz"
echo "== 备用：codeload（公开源，测大文件通道）=="
code=$(curl -sL --max-time 180 -o cl.tgz -w '%{http_code}' "https://codeload.github.com/QuantumNous/new-api/tar.gz/refs/tags/v1.0.0-rc.42" 2>/dev/null)
echo "  codeload rc42: http=$code bytes=$(stat -c %s cl.tgz 2>/dev/null || echo 0)"
echo "== 备用：github release 资产 =="
code=$(curl -sL --max-time 180 -o gh.bin -w '%{http_code}' "https://github.com/git/git/archive/refs/tags/v2.43.0.tar.gz" 2>/dev/null)
echo "  github archive: http=$code bytes=$(stat -c %s gh.bin 2>/dev/null || echo 0)"
echo DLCHAN_DONE
