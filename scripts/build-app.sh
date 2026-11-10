#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/swift-local.sh build -c release
swift -module-cache-path "$PWD/.build/clang-cache" scripts/compile-pose-model.swift
bundle_path="$PWD/build/轻醒.app"
staging_path="$PWD/.build/app-bundle/轻醒.app"
mkdir -p "$staging_path/Contents/MacOS" "$staging_path/Contents/Resources"
cp .build/release/QingXing "$staging_path/Contents/MacOS/QingXing"
cp Resources/Info.plist "$staging_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$staging_path/Contents/Resources/AppIcon.icns"
ditto .build/pose-model/PoseNetMobileNet075S16FP16.mlmodelc "$staging_path/Contents/Resources/PoseNetMobileNet075S16FP16.mlmodelc"
mkdir -p "$staging_path/Contents/Resources/PoseNetLicenses"
cp Resources/PoseNet/ACKNOWLEDGMENTS.txt Resources/PoseNet/LICENSE.txt Resources/PoseNet/SOURCE.md "$staging_path/Contents/Resources/PoseNetLicenses/"
python3 scripts/sign-app.py "$staging_path"
mkdir -p "$PWD/build"
ditto "$staging_path" "$bundle_path"
codesign --verify --strict "$bundle_path"
printf 'Built %s\n' "$bundle_path"
