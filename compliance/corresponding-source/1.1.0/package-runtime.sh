#!/bin/zsh
# 将 Pandoc / Typst 及许可材料装入指定的 .app Resources 目录。
# 用法: ./gui/package-runtime.sh <resources-dir> [sign-identity]

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO="${SCRIPT_DIR:A:h}"
RES_DIR="${1:?缺少 Resources 目录参数}"
SIGN_IDENTITY="${2:--}"
CHILD_ENTITLEMENTS="$REPO/gui/mac/TrueScalePDFChild.entitlements"
BIN_DIR="$RES_DIR/bin"
LIB_DIR="$RES_DIR/lib"
LIC_DIR="$RES_DIR/licenses"

mkdir -p "$BIN_DIR" "$LIB_DIR" "$LIC_DIR"

echo ">>> 打包渲染引擎（pandoc / typst）"
for tool in pandoc typst; do
  src=$(command -v "$tool" 2>/dev/null) || true
  [[ -n "$src" ]] || { echo "!!! 未找到 $tool，构建机需先 brew install $tool"; exit 1; }
  src=$(readlink -f "$src")
  arch=$(lipo -archs "$src" 2>/dev/null)
  echo "    $tool ($arch, $(du -h "$src" | cut -f1))"
  cp "$src" "$BIN_DIR/$tool"
  chmod +x "$BIN_DIR/$tool"
done

echo ">>> 重定位动态库引用"
relocate() {
  local f="$1" dep dylib
  otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}' \
      | grep -E '^/opt/homebrew/|^/usr/local/' | sort -u | while read -r dep; do
    dylib=$(basename "$dep")
    if [[ ! -f "$LIB_DIR/$dylib" ]]; then
      cp "$(readlink -f "$dep")" "$LIB_DIR/$dylib"
      chmod u+w "$LIB_DIR/$dylib"
      install_name_tool -id "@executable_path/../lib/$dylib" "$LIB_DIR/$dylib" 2>/dev/null
      echo "    + $dylib"
      relocate "$LIB_DIR/$dylib"
    fi
    install_name_tool -change "$dep" "@executable_path/../lib/$dylib" "$f" 2>/dev/null
  done
  return 0
}

for bin in "$BIN_DIR"/*; do
  [[ -f "$bin" ]] && relocate "$bin"
done

echo ">>> 重签渲染引擎"
for f in "$BIN_DIR"/*; do
  [[ -f "$f" ]] || continue
  codesign -f --entitlements "$CHILD_ENTITLEMENTS" -s "$SIGN_IDENTITY" "$f" >/dev/null 2>&1
done
for f in "$LIB_DIR"/*; do
  [[ -f "$f" ]] || continue
  codesign -f -s "$SIGN_IDENTITY" "$f" >/dev/null 2>&1
done

LEAK=$(for f in "$BIN_DIR"/* "$LIB_DIR"/*; do
  [[ -f "$f" ]] && otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}' \
    | grep -E '^/opt/homebrew/|^/usr/local/'
done | sort -u || true)
if [[ -n "$LEAK" ]]; then
  echo "!!! bundle 仍含 Homebrew 绝对路径引用："
  echo "$LEAK" | sed 's/^/    /'
  exit 1
fi
echo "    ✅ 无残留 Homebrew 路径引用"

echo ">>> 打包第三方许可文本"
for pkg in pandoc typst gmp; do
  pfx=$(brew --prefix "$pkg" 2>/dev/null) || continue
  for name in COPYING.md COPYING COPYING.LESSERv3 LICENSE NOTICE; do
    [[ -f "$pfx/$name" ]] && cp "$pfx/$name" "$LIC_DIR/${pkg}-${name}"
  done
done
[[ -f "$REPO/THIRD-PARTY-LICENSES.md" ]] && cp "$REPO/THIRD-PARTY-LICENSES.md" "$LIC_DIR/"
[[ -f "$REPO/LICENSE" ]] && cp "$REPO/LICENSE" "$LIC_DIR/truescale-pdf-LICENSE"

APP_VERSION=$(awk -F '"' '/MARKETING_VERSION:/ { print $2; exit }' "$REPO/project.yml")
SOURCE_DIR="$REPO/compliance/corresponding-source/$APP_VERSION"
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "!!! 缺少 $SOURCE_DIR —— 发布包必须随附对应源码"
  echo "    请先运行 scripts/package-corresponding-source.sh '$SOURCE_DIR'"
  exit 1
fi
rm -rf "$LIC_DIR/corresponding-source"
mkdir -p "$LIC_DIR/corresponding-source"
cp -R "$SOURCE_DIR" "$LIC_DIR/corresponding-source/$APP_VERSION"
echo "    ✅ 已随包附带对应源码与构建材料"
echo "    $(ls "$LIC_DIR" | wc -l | tr -d ' ') 个许可文件"
