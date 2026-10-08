#!/bin/bash
# T-MUSE-BUILD42B: rc.42+v59 构建（分片交付 + 统一配方）
set -u
W=/home/hatch/b42; mkdir -p "$W"; cd "$W"
echo "== 1) 分片下载 =="
PARTS="$W/parts.txt"
cat > "$PARTS" <<'PARTSEOF'
0a1cfb3cf67c4795f170b910ab2301b15cffec19867f8c3bf67910395c3a919f https://files.catbox.moe/1k591w.bin
d3758d292a387dfe57e72571463bf6edbccaa84761c22c5f40edc60e307f806a https://files.catbox.moe/exi5rz.bin
4809aa3620c09403add7cbc43a475c4b3b7cdeecf3aa810111cdc8ebbea78aff https://files.catbox.moe/lok84p.bin
aa201bfb270c7fed34936bbbae70297a86e6251e592c79dffac0dca8e36b235f https://files.catbox.moe/swwr8w.bin
35da3c0d1711a0c78f91e4236e0803a4644680de7220da42c5da63b2a2461371 https://files.catbox.moe/o1udkv.bin
3b81d9da1a288969926731debbfa422c2ea6eaa124fedce40e7d17847c7bd1d7 https://files.catbox.moe/k5vjhu.bin
4e006c53ead6e2c2f05ae243cfc2bdfbc78868311a0b029f0ee8efb3f47df8e6 https://files.catbox.moe/ehibv3.bin
19913d0691a70288fe2a4a7928e051e0ef2ea3aea955f2bb6f48ce99d1d03be6 https://files.catbox.moe/8hpkiv.bin
3860123fa923ed64a48cbff29beaa6a2ce9ecff6e878c540cb4271d8dd75cd53 https://files.catbox.moe/xexsam.bin
PARTSEOF
: > src.tgz
n=0
while read -r sha url; do
  [ -n "$sha" ] || continue
  n=$((n+1))
  f=$(printf "p%02d.bin" "$n")
  got=""
  for i in 1 2 3; do
    rm -f "$f"
    curl -sL --max-time 300 -o "$f" -A "Mozilla/5.0" "$url" 2>/dev/null
    got=$(sha256sum "$f" 2>/dev/null | cut -d" " -f1)
    [ "$got" = "$sha" ] && break
    echo "  retry part$n try$i got=${got:0:16} want=${sha:0:16}"
    sleep 4
  done
  if [ "$got" = "$sha" ]; then
    echo "  part$n OK $(stat -c %s "$f") B"
    cat "$f" >> src.tgz
  else
    echo "FATAL part$n sha mismatch"; exit 2
  fi
done < "$PARTS"
W_SHA=$(sha256sum src.tgz | cut -d" " -f1)
echo "  src.tgz bytes=$(stat -c %s src.tgz) sha=$W_SHA"
echo "  want             bytes=25411226 sha=bb8f322fa583709553516e3420450f3747297454ad9df2118b03e1d634a4352d"
[ "$W_SHA" = "bb8f322fa583709553516e3420450f3747297454ad9df2118b03e1d634a4352d" ] || { echo "FATAL whole sha mismatch"; exit 3; }
echo "== 2) 配方 + 工具链 =="
curl -fsSL --max-time 300 -o recipe.sh "https://files.catbox.moe/s5felr.sh" || { echo "FATAL recipe"; exit 4; }
R=$(sha256sum recipe.sh | cut -d" " -f1); echo "  recipe_sha=$R ok=$([ "$R" = "30595cf4209bc425db92c2c10ea9e19ec1b84820708ee4129e159c8423c5a8a8" ] && echo YES || echo NO)"
[ "$R" = "30595cf4209bc425db92c2c10ea9e19ec1b84820708ee4129e159c8423c5a8a8" ] || { echo "FATAL recipe sha"; exit 4; }
curl -fsSL --max-time 900 -o go.tgz "https://dl.google.com/go/go1.26.1.linux-amd64.tar.gz" || { echo "FATAL go dl"; exit 5; }
G=$(sha256sum go.tgz | cut -d" " -f1); echo "  go_sha=$G ok=$([ "$G" = "031f088e5d955bab8657ede27ad4e3bc5b7c1ba281f05f245bcc304f327c987a" ] && echo YES || echo NO)"
[ "$G" = "031f088e5d955bab8657ede27ad4e3bc5b7c1ba281f05f245bcc304f327c987a" ] || { echo "FATAL go sha"; exit 5; }
echo "== 3) 统一配方构建（含 PGO）=="
export WORK="$W" SRC_TGZ="$W/src.tgz" GO_TGZ="$W/go.tgz"
bash "$W/recipe.sh" 2>&1
echo "RECIPE_EXIT=$?"
echo "== 4) 交付判据 =="
B="$W/out/new-api-rc42-v59"
if [ -f "$B" ]; then
  echo "BIN_BYTES=$(stat -c %s "$B")"
  echo "BIN_SHA256=$(sha256sum "$B" | cut -d" " -f1)"
  echo "BIN_VERSION=$("$B" --version 2>&1 | head -1)"
else
  echo "BIN_MISSING"
fi
echo "MUSE_BUILD42B_DONE"
