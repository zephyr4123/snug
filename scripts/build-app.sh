#!/bin/zsh
# 构建 build/Snug.app。切模式的帮手进程就是 Snug 自己（带 --set-mode 运行），不另外打包。
# 只构建，不安装、不启动。版本号只从仓库根目录的 VERSION 读。
#
# 签名（按顺序）：
#   1. SIGN_IDENTITY 环境变量：证书名或 SHA-1；"-" 表示 ad-hoc
#   2. 没设就在钥匙串里找唯一一张「Developer ID Application」证书（有多张时报错，请用 SIGN_IDENTITY 指定）
#   3. 都没有就退回 ad-hoc 并警告：ad-hoc 签名每次构建后，辅助功能授权都会失效
# Developer ID 证书签名时带 --options runtime --timestamp（公证要求）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
BUNDLE_ID="com.zephyr4123.snug"
APP="build/Snug.app"

[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { echo "❌ VERSION 文件里的版本号不合法：「$VERSION」" >&2; exit 1; }

# —— 选签名身份 ——
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  IDENTITY="$SIGN_IDENTITY"
  if [[ "$IDENTITY" != "-" ]] && ! print -r -- "$IDENTITIES" | grep -qF -- "$IDENTITY"; then
    echo "❌ 钥匙串里找不到 SIGN_IDENTITY 指定的有效证书；ad-hoc 签名请设 SIGN_IDENTITY=-" >&2
    exit 1
  fi
else
  DEVELOPER_IDS=("${(@f)$(print -r -- "$IDENTITIES" | awk '/"Developer ID Application: /{print $2}')}")
  DEVELOPER_IDS=(${DEVELOPER_IDS:#})   # 去掉空行
  case ${#DEVELOPER_IDS} in
    0) IDENTITY="-"
       echo "⚠️  钥匙串里没有 Developer ID Application 证书，改用 ad-hoc 签名：每次构建后辅助功能授权都会失效，也不能公证分发" >&2 ;;
    1) IDENTITY="${DEVELOPER_IDS[1]}"
       echo "==> 使用钥匙串里唯一的 Developer ID Application 证书（SHA-1 ${IDENTITY[1,8]}…）" ;;
    *) echo "❌ 钥匙串里有 ${#DEVELOPER_IDS} 张 Developer ID Application 证书，请用 SIGN_IDENTITY 指定一张" >&2
       exit 1 ;;
  esac
fi
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]] && print -r -- "$IDENTITIES" | grep -F -- "$IDENTITY" | grep -q '"Developer ID Application: '; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi

# —— 编译 ——
swift build -c release --product Snug
BIN_DIR="$(swift build -c release --show-bin-path)"

# —— 组装 ——
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Snug" "$APP/Contents/MacOS/Snug"
# PermissionFlow 资源包（本地化文案等），PermissionFlowResources 在 Contents/Resources 里找
cp -R "$BIN_DIR/PermissionFlow_PermissionFlow.bundle" "$APP/Contents/Resources/"
# App 图标（界面里的其它图标都是 SF Symbols，见 Assets/AppIcon/README.md）
cp Assets/AppIcon/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>Snug</string>
  <key>CFBundleDisplayName</key><string>Snug</string>
  <key>CFBundleExecutable</key><string>Snug</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# —— 签名 ——
codesign "${SIGN_FLAGS[@]}" --identifier "${BUNDLE_ID}" "$APP"
codesign --verify --strict --deep "$APP"
echo "✅ 已生成 $APP（版本 ${VERSION}，签名：$([[ "$IDENTITY" == "-" ]] && echo ad-hoc || echo "${IDENTITY[1,8]}…")）"
