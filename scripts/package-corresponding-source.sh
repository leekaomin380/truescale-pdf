#!/bin/zsh
# 显式生成随发布二进制对应的 GPL/LGPL 源码包。
# 正常 app 构建不会下载源码；每个候选发布版本必须单独运行本脚本并发布其产物。

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO="${SCRIPT_DIR:A:h}"
OUT_DIR="${1:-$REPO/dist/corresponding-source}"

command -v pandoc >/dev/null || { echo "未找到 pandoc"; exit 1; }
command -v brew >/dev/null || { echo "未找到 Homebrew"; exit 1; }

PANDOC_VERSION=$(pandoc --version | head -1 | awk '{print $2}')
GMP_PREFIX=$(brew --prefix gmp)
GMP_VERSION=$(basename "$(readlink -f "$GMP_PREFIX")")
PANDOC_PREFIX=$(brew --prefix pandoc)

mkdir -p "$OUT_DIR"

PANDOC_ARCHIVE="$OUT_DIR/pandoc-${PANDOC_VERSION}-source.tar.gz"
GMP_ARCHIVE="$OUT_DIR/gmp-${GMP_VERSION}-source.tar.xz"

if [[ -s "$PANDOC_ARCHIVE" ]]; then
  echo ">>> 复用已有 pandoc ${PANDOC_VERSION} 源码归档"
else
  echo ">>> 下载 pandoc ${PANDOC_VERSION} 对应源码"
  curl --fail --location --retry 3 --retry-all-errors \
    "https://github.com/jgm/pandoc/archive/refs/tags/${PANDOC_VERSION}.tar.gz" \
    --output "$PANDOC_ARCHIVE"
fi

if [[ -s "$GMP_ARCHIVE" ]]; then
  echo ">>> 复用已有 GNU MP ${GMP_VERSION} 源码归档"
else
  echo ">>> 下载 GNU MP ${GMP_VERSION} 对应源码"
  curl --fail --location --retry 3 --retry-all-errors \
    "https://gmplib.org/download/gmp/gmp-${GMP_VERSION}.tar.xz" \
    --output "$GMP_ARCHIVE"
fi

cp "$PANDOC_PREFIX/INSTALL_RECEIPT.json" "$OUT_DIR/pandoc-INSTALL_RECEIPT.json"
cp "$GMP_PREFIX/INSTALL_RECEIPT.json" "$OUT_DIR/gmp-INSTALL_RECEIPT.json"
# Homebrew 回执会写入构建用户的绝对缓存路径；路径不影响配方可复现性，
# 发布前只匿名用户目录，保留配方、版本、Bottle 与 SHA 等字段原样。
perl -pi -e 's#/Users/[^/]+/#/Users/BUILD_USER/#g' \
  "$OUT_DIR/pandoc-INSTALL_RECEIPT.json" \
  "$OUT_DIR/gmp-INSTALL_RECEIPT.json"
cp "$REPO/gui/package-runtime.sh" "$OUT_DIR/package-runtime.sh"
cp "$REPO/gui/build-app.sh" "$OUT_DIR/build-app.sh"
cp "$REPO/project.yml" "$OUT_DIR/project.yml"
cp "$REPO/gui/mac/Info.plist" "$OUT_DIR/Info.plist"
cp "$REPO/gui/mac/PrivacyInfo.xcprivacy" "$OUT_DIR/PrivacyInfo.xcprivacy"
cp "$REPO/gui/mac/TrueScalePDF.entitlements" "$OUT_DIR/TrueScalePDF.entitlements"
cp "$REPO/gui/mac/TrueScalePDFChild.entitlements" "$OUT_DIR/TrueScalePDFChild.entitlements"
cp "$REPO/THIRD-PARTY-LICENSES.md" "$OUT_DIR/THIRD-PARTY-LICENSES.md"

(
  cd "$OUT_DIR"
  shasum -a 256 \
    "pandoc-${PANDOC_VERSION}-source.tar.gz" \
    "gmp-${GMP_VERSION}-source.tar.xz" \
    pandoc-INSTALL_RECEIPT.json \
    gmp-INSTALL_RECEIPT.json \
    package-runtime.sh \
    build-app.sh \
    project.yml \
    Info.plist \
    PrivacyInfo.xcprivacy \
    TrueScalePDF.entitlements \
    TrueScalePDFChild.entitlements \
    > SHA256SUMS
)

cat > "$OUT_DIR/MANIFEST.txt" <<EOF
TrueScale PDF corresponding source package
Generated (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Architecture: $(uname -m)
Pandoc: ${PANDOC_VERSION}
Pandoc binary: ${PANDOC_PREFIX}/bin/pandoc
GNU MP: ${GMP_VERSION}
GNU MP prefix: ${GMP_PREFIX}

The app modifies only Mach-O load paths and signatures after copying the
Homebrew binaries. package-runtime.sh records those reproducible operations.
SHA256SUMS authenticates every source and build-material file in this folder.
EOF

echo ">>> 完成: $OUT_DIR"
echo "    发布二进制时，请从同一下载页面提供此目录或其归档。"
