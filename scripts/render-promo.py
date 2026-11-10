#!/usr/bin/env python3
"""Render the existing app UI at 4x without modifying application sources.

The exporter is compiled from temporary source copies under .build. Matching
the hosting window's backing scale and SwiftUI displayScale is necessary:
a larger bitmap alone leaves Canvas artwork at its original resolution.
"""
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TEMP = ROOT / ".build/promo-hires"
SCALE = 4


def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)


run("bash", "scripts/swift-local.sh", "build", "--product", "QingXing")
sources = TEMP / "sources"
sources.mkdir(parents=True, exist_ok=True)
for path in (ROOT / "Sources/Heathy").glob("*.swift"):
    shutil.copyfile(path, sources / path.name)

preview = sources / "PreviewRenderer.swift"
original = preview.read_text()
bitmap = """        guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RenderError.empty }
        host.cacheDisplay(in: host.bounds, to: image)"""
high_resolution = f"""        let scale = {SCALE}.0
        guard let image = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {{ throw RenderError.empty }}
        image.size = size
        host.cacheDisplay(in: host.bounds, to: image)"""
edits = {
    "/// Development-only renders": f"private final class PromoExportWindow: NSWindow {{\n    override var backingScaleFactor: CGFloat {{ {SCALE} }}\n}}\n\n/// Development-only renders",
    "let host = NSHostingView(rootView: content)": f"let host = NSHostingView(rootView: content.environment(\\.displayScale, {SCALE}))",
    "let window = NSWindow(contentRect: host.frame": "let window = PromoExportWindow(contentRect: host.frame",
    bitmap: high_resolution,
    'print("Rendered \\(name): \\(Int(size.width)) × \\(Int(size.height)) pt")': 'print("Rendered \\(name): \\(image.pixelsWide) × \\(image.pixelsHigh) px (4x)")',
}
modified = original
for old, new in edits.items():
    if modified.count(old) != 1:
        raise RuntimeError("PreviewRenderer changed; update the temporary export adapter")
    modified = modified.replace(old, new)
preview.write_text(modified)

build = ROOT / ".build/arm64-apple-macosx/debug"
compiler = ["xcrun", "swiftc", "-swift-version", "5", "-DDEBUG",
            "-parse-as-library", "-module-name", "Heathy", "-target",
            "arm64-apple-macos14.0", "-module-cache-path", str(ROOT / ".build/module-cache"),
            "-I", str(build / "Modules"), "-o", str(TEMP / "QingXing")]
compiler += [str(path) for path in sorted(sources.glob("*.swift"))]
compiler += [str(path) for path in sorted((build / "HeathyCore.build").glob("*.o"))]
run(*compiler)
for option, directory in [("--render-health-ring", "health"),
                          ("--render-previews", "ui"), ("--render-themes", "themes")]:
    run(str(TEMP / "QingXing"), option, str(ROOT / ".build/promo-reference" / directory))
run("python3", "scripts/generate-promo.py")
