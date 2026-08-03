#!/bin/zsh
# 从已经校验的随包源码目录生成 GitHub Release 资产；本脚本不上传、不创建 Release。

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO="${SCRIPT_DIR:A:h}"
VERSION=$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' "$REPO/project.yml")
SOURCE_DIR="$REPO/compliance/corresponding-source/$VERSION"
OUT_DIR="${1:-$REPO/dist/release-v$VERSION}"
ASSET="$OUT_DIR/TrueScalePDF-${VERSION}-corresponding-source.tar.gz"

[[ -d "$SOURCE_DIR" ]] || {
  echo "缺少 $SOURCE_DIR"
  echo "请先运行 scripts/package-corresponding-source.sh '$SOURCE_DIR'"
  exit 1
}

mkdir -p "$OUT_DIR"
COPYFILE_DISABLE=1 tar -C "$REPO/compliance/corresponding-source" \
  -czf "$ASSET" "$VERSION"
cp "$REPO/THIRD-PARTY-LICENSES.md" "$OUT_DIR/THIRD-PARTY-LICENSES.md"

(
  cd "$OUT_DIR"
  shasum -a 256 \
    "TrueScalePDF-${VERSION}-corresponding-source.tar.gz" \
    THIRD-PARTY-LICENSES.md \
    > SHA256SUMS
)

echo ">>> GitHub Release v$VERSION 资产已生成：$OUT_DIR"
echo "    上传完成前，不要发布包含该版本 GitHub 链接的 App Store 构建。"
