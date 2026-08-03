#!/bin/zsh
# gui/build-app.sh — 编译原生 SwiftUI 应用并组装 .app bundle
# 用法: ./gui/build-app.sh
# 产出: gui/TrueScale PDF.app

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO="${SCRIPT_DIR:A:h}"
MAC_DIR="$SCRIPT_DIR/mac"
APP_NAME="TrueScale PDF"
APP_DIR="$SCRIPT_DIR/$APP_NAME.app"

echo ">>> 清理旧 .app"
rm -rf "$APP_DIR"

echo ">>> 编译原生 SwiftUI 应用"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

swiftc \
    "$MAC_DIR/TrueScalePDFApp.swift" \
    "$MAC_DIR/OpenSourceComponentsView.swift" \
    "$MAC_DIR/ContentView.swift" \
    "$MAC_DIR/ConversionViewModel.swift" \
    -o "$APP_DIR/Contents/MacOS/TrueScalePDF" \
    -framework SwiftUI \
    -framework AppKit \
    -framework PDFKit \
    -framework UniformTypeIdentifiers \
    -target arm64-apple-macos14.0

echo ">>> 复制 Info.plist"
cp "$MAC_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.figedu.truescalepdf" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.0.0" "$APP_DIR/Contents/Info.plist"

echo ">>> 复制隐私清单"
cp "$MAC_DIR/PrivacyInfo.xcprivacy" "$APP_DIR/Contents/Resources/PrivacyInfo.xcprivacy"

ICON_SRC="$MAC_DIR/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    echo ">>> 复制图标"
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo ">>> 复制运行时依赖"
cp "$REPO/config.sh" "$APP_DIR/Contents/Resources/config.sh"
cp "$REPO/book.sh" "$APP_DIR/Contents/Resources/book.sh"
chmod +x "$APP_DIR/Contents/Resources/book.sh"
cp "$REPO/deliver.typ" "$APP_DIR/Contents/Resources/deliver.typ"
cp "$REPO/book-filter.lua" "$APP_DIR/Contents/Resources/book-filter.lua"
# 签名身份。默认 `-` 即 ad-hoc；有 Developer ID 后可传入而无需改脚本：
#   SIGN_IDENTITY="Developer ID Application: …" ./gui/build-app.sh
# 注意 ad-hoc 只够本机运行 —— Apple 的 syspolicy_check 明确判定
# 「adhoc signed apps are not suitable for distribution」，公证另需 notarytool。
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

"$SCRIPT_DIR/package-runtime.sh" "$APP_DIR/Contents/Resources" "$SIGN_IDENTITY"

# ---------------------------------------------------------------------------
# 给整个 .app 盖封印 —— 必须是最后一步。
#
# 【此前的 bug】脚本只签了 Resources/bin 与 Resources/lib 里的单个二进制，
# 从未签过 .app 本体。swiftc 产出的可执行文件自带 ad-hoc 签名，但那只覆盖
# 它自己；把它装进 bundle 又塞进 Resources 之后，bundle 缺少 _CodeSignature/
# CodeResources，签名与内容不一致。表现为：
#   codesign --verify → "code has no resources but signature indicates
#                        they must be present"
#   spctl --assess    → rejected（exit 1）
# 用户下载后 macOS 报「已损坏，请移到废纸篓」—— 那个提示没有「仍要打开」的出路，
# 比「无法验证开发者」恶劣得多，等于彻底不可用。
#
# 【为何放在这里】封印会把 Resources 下所有文件的哈希写进 CodeResources。
# 只要之后再往 bundle 里加/改任何一个文件，封印立即失效。所以这一步必须在
# 引擎、许可、脚本、图标全部就位之后执行，位置本身就是修复的一部分。
#
# 【为何不用 --deep】Apple 已不推荐：它会覆盖内层已有签名。正确做法是
# 内层先各自签好（上面已做），再签外层 bundle。
# ---------------------------------------------------------------------------
echo ">>> 给 .app 盖封印（签名身份：$SIGN_IDENTITY）"
ENTITLEMENTS="$MAC_DIR/TrueScalePDF.entitlements"
codesign --force --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_DIR" 2>&1 | sed 's/^/    /'

if codesign --verify --deep --strict "$APP_DIR" 2>/dev/null; then
  echo "    ✅ 签名校验通过"
else
  echo "!!! 签名校验失败 —— 下载后 macOS 会报「已损坏」，不可分发："
  codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>&1 | tail -5 | sed 's/^/    /'
  exit 1
fi

if codesign -d --entitlements - "$APP_DIR" 2>&1 | grep -q 'com.apple.security.app-sandbox'; then
  echo "    ✅ App Sandbox 签名验证通过"
else
  echo "!!! 沙盒校验失败 —— app 缺少 com.apple.security.app-sandbox=true"
  exit 1
fi

echo ">>> 完成: $APP_DIR"
echo "    双击访达中的 \"$APP_NAME.app\" 即可启动"
