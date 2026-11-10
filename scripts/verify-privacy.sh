#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
import plistlib
import re
import subprocess

allowed = {"com.apple.security.app-sandbox": True, "com.apple.security.device.camera": True}
declared = plistlib.loads(Path("Resources/Heathy.entitlements").read_bytes())
assert declared == allowed, f"Unexpected entitlements: {declared}"
info = plistlib.loads(Path("Resources/Info.plist").read_bytes())
privacy_keys = {key for key in info if key.endswith("UsageDescription")}
assert privacy_keys == {"NSCameraUsageDescription"}, privacy_keys
forbidden = re.compile(r"URLSession|URLRequest|NWConnection|AVCaptureAudioDataOutput|AVCaptureMovieFileOutput|AVCapturePhotoOutput|SCStream|CGWindowList|CGEvent|addGlobalMonitorForEvents|NSPasteboard|runningApplications|Data\(contentsOf:|FileHandle|AVAudioRecorder")
for source in Path("Sources/Heathy").glob("*.swift"):
    for number, line in enumerate(source.read_text().splitlines(), 1):
        assert not forbidden.search(line), f"Unexpected data-access API {source}:{number}: {line.strip()}"
camera = Path("Sources/Heathy/CameraDetector.swift").read_text()
assert "mediaType: .video" in camera and "AVCaptureVideoDataOutput()" in camera
assert ".audio" not in camera
app = Path("build/轻醒.app")
if app.exists():
    signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)], check=True, capture_output=True)
    assert plistlib.loads(signed.stdout) == allowed, "Bundle signature has unexpected entitlements"
    subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
print("PASS: camera-only resource entitlement; camera-only privacy description; no prohibited capture, file, input, or network APIs")
print("This checks the declared access surface and source APIs; it is not a camera-accuracy or energy test.")
PY
