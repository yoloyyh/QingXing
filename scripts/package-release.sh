#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build-app.sh
app_path="$PWD/build/轻醒.app"
release_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
architecture=$(lipo -archs "$app_path/Contents/MacOS/QingXing")
if [ "$architecture" != "arm64" ]; then
  printf 'Expected an arm64 release app, found: %s\n' "$architecture" >&2
  exit 1
fi
codesign --verify --deep --strict "$app_path"

release_dir="$PWD/build/releases/v$release_version"
mkdir -p "$release_dir"
image_root=$(mktemp -d "$PWD/.build/release-staging.XXXXXX")
trap 'rm -rf "$image_root"' EXIT
ditto "$app_path" "$image_root/轻醒.app"
ln -s /Applications "$image_root/Applications"
cat > "$image_root/安装说明.txt" <<'EOF'
轻醒 · QingXing

适用系统：macOS 14 或更新版本，Apple Silicon Mac（M1 及更新芯片）。

1. 将「轻醒.app」拖入旁边的「Applications」文件夹。
2. 从「应用程序」中双击打开「轻醒」。无需安装开发工具或额外依赖。
3. 首次使用可先体验提醒演示，再主动授权摄像头并记录参考位置。

首次打开提示：
当前版本采用项目开发签名，尚未完成 Apple 公证。
如果 macOS 阻止打开，请先尝试启动一次，再进入
「系统设置 → 隐私与安全性」，找到轻醒的提示并选择「仍要打开」，
按系统提示确认。之后可以直接双击启动。
不需要关闭系统安全检查，也不需要安装额外证书。

摄像头画面只在本机内存中分析，不录制、不保存、不上传。
也可以不开摄像头，单独使用工作与休息计时。
EOF

hdiutil create -ov -volname "轻醒 $release_version" -srcfolder "$image_root" \
  -format UDZO "$release_dir/QingXing-macOS-arm64.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$release_dir/QingXing-macOS-arm64.zip"
(
  cd "$release_dir"
  shasum -a 256 QingXing-macOS-arm64.dmg QingXing-macOS-arm64.zip > SHA256SUMS.txt
)
printf 'Release artifacts: %s\n' "$release_dir"
