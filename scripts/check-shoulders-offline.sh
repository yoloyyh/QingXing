#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import urllib.request
import plistlib
folder = Path('.build/pose-fixtures')
folder.mkdir(parents=True, exist_ok=True)
for name in ['pose_squats.mp4', 'pose_squats.full.json', 'pose_1.mp4', 'pose_1.json']:
    target = folder / name
    if not target.exists():
        url = 'https://raw.githubusercontent.com/tensorflow/tfjs-models/master/pose-detection/test_data/' + name
        with urllib.request.urlopen(url, timeout=30) as response:
            target.write_bytes(response.read())
source = Path('Sources/Heathy/PoseNetShoulderDetector.swift').read_text()
Path('.build/FixtureShoulderDetector.swift').write_text(source.replace('import HeathyCore\n', ''))
info = Path('.build/ShoulderChecks.app/Contents/Info.plist')
info.parent.mkdir(parents=True, exist_ok=True)
info.write_bytes(plistlib.dumps({'CFBundleExecutable': 'ShoulderChecks', 'CFBundleIdentifier': 'local.qingxing.offline-checks', 'CFBundlePackageType': 'APPL'}))
PY
check_bundle="$PWD/.build/ShoulderChecks.app"
mkdir -p "$check_bundle/Contents/MacOS" "$check_bundle/Contents/Resources"
if [ ! -d .build/pose-model/PoseNetMobileNet075S16FP16.mlmodelc ]; then
    swift -module-cache-path "$PWD/.build/clang-cache" scripts/compile-pose-model.swift
fi
ditto .build/pose-model/PoseNetMobileNet075S16FP16.mlmodelc "$check_bundle/Contents/Resources/PoseNetMobileNet075S16FP16.mlmodelc"
swiftc -O -parse-as-library -module-cache-path "$PWD/.build/clang-cache" Sources/HeathyCore/*.swift .build/FixtureShoulderDetector.swift scripts/check-shoulder-fixtures.swift -o "$check_bundle/Contents/MacOS/ShoulderChecks"
"$check_bundle/Contents/MacOS/ShoulderChecks"
