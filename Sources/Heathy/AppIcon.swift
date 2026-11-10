import AppKit
import SwiftUI

@MainActor
enum AppIcon {
    /// Load our bundled artwork directly so Dock does not retain a stale placeholder.
    @discardableResult
    static func install(theme: AppTheme = .mist) -> NSImage? {
        if theme != .mist {
            let renderer = ImageRenderer(content: OwlAppIconArtwork(theme: theme))
            renderer.scale = 1
            if let cgImage = renderer.cgImage {
                let image = NSImage(cgImage: cgImage, size: NSSize(width: 1024, height: 1024))
                NSApplication.shared.applicationIconImage = image
                return image
            }
        }
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url), image.isValid else { return nil }
        NSApplication.shared.applicationIconImage = image
        return image
    }

    static func matchesArtwork(_ applied: NSImage, expected: NSImage) -> Bool {
        func bitmap(_ image: NSImage) -> NSBitmapImageRep {
            let value = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: value)
            NSGraphicsContext.current!.cgContext.clear(CGRect(x: 0, y: 0, width: 128, height: 128))
            image.draw(in: NSRect(x: 0, y: 0, width: 128, height: 128), from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            return value
        }
        let actual = bitmap(applied), source = bitmap(expected)
        for (x, y) in [(64, 64), (40, 48), (88, 48), (64, 90), (64, 110), (20, 64)] {
            guard let a = actual.colorAt(x: x, y: y), let b = source.colorAt(x: x, y: y) else { return false }
            if abs(a.redComponent - b.redComponent) > 0.04 || abs(a.greenComponent - b.greenComponent) > 0.04 || abs(a.blueComponent - b.blueComponent) > 0.04 { return false }
        }
        return true
    }
}
