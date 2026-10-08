#!/bin/bash
# T-MUSE-BUILD42: rc.42 + v59 补丁 构建（统一配方）
set -u
W=/home/hatch/b42; mkdir -p "$W"; cd "$W"
echo "== 1) 取物料 =="
curl -fsSL --max-time 900 -o src.tgz "https://files.catbox.moe/sulpe4.gz"    || { echo "FATAL src download"; exit 1; }
curl -fsSL --max-time 300 -o recipe.sh "https://files.catbox.moe/s5felr.sh" || { echo "FATAL recipe download"; exit 1; }
curl -fsSL --max-time 900 -o go.tgz "https://dl.google.com/go/go1.26.1.linux-amd64.tar.gz"      || { echo "FATAL go download"; exit 1; }
ls -la src.tgz recipe.sh go.tgz
echo "== 2) 校验 sha256 =="
S=$(sha256sum src.tgz | cut -d" " -f1);    echo "src_sha=$S  want=bb8f322fa583709553516e3420450f3747297454ad9df2118b03e1d634a4352d  ok=$([ "$S" = "bb8f322fa583709553516e3420450f3747297454ad9df2118b03e1d634a4352d" ] && echo YES || echo NO)"
R=$(sha256sum recipe.sh | cut -d" " -f1);  echo "recipe_sha=$R  want=30595cf4209bc425db92c2c10ea9e19ec1b84820708ee4129e159c8423c5a8a8  ok=$([ "$R" = "30595cf4209bc425db92c2c10ea9e19ec1b84820708ee4129e159c8423c5a8a8" ] && echo YES || echo NO)"
G=$(sha256sum go.tgz | cut -d" " -f1);     echo "go_sha=$G  want=031f088e5d955bab8657ede27ad4e3bc5b7c1ba281f05f245bcc304f327c987a  ok=$([ "$G" = "031f088e5d955bab8657ede27ad4e3bc5b7c1ba281f05f245bcc304f327c987a" ] && echo YES || echo NO)"
[ "$S" = "bb8f322fa583709553516e3420450f3747297454ad9df2118b03e1d634a4352d" ] || { echo "FATAL src sha mismatch"; exit 2; }
[ "$R" = "30595cf4209bc425db92c2c10ea9e19ec1b84820708ee4129e159c8423c5a8a8" ] || { echo "FATAL recipe sha mismatch"; exit 2; }
[ "$G" = "031f088e5d955bab8657ede27ad4e3bc5b7c1ba281f05f245bcc304f327c987a" ] || { echo "FATAL go sha mismatch"; exit 2; }
echo "== 3) 构建（统一配方，含 PGO）=="
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
echo "MUSE_BUILD42_DONE"
