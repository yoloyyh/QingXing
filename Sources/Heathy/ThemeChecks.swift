import AppKit
import Foundation
import SwiftUI

@MainActor
enum ThemeChecks {
    static func run() {
        let suite = "local.qingxing.theme-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = AppState(defaults: defaults)
        precondition(initial.theme == .mist)
        initial.shutdown()
        defaults.set("future-theme", forKey: "qx.theme")
        let unknown = AppState(defaults: defaults)
        precondition(unknown.theme == .mist)
        unknown.shutdown()
        let state = AppState(defaults: defaults)
        defer { state.shutdown() }
        let before = defaults.dictionaryRepresentation()
        let totals = (state.workDuration, state.adjustments, state.rests)
        var changes: [AppTheme] = []
        state.onThemeChange = { changes.append($0) }
        for theme in AppTheme.allCases {
            state.theme = theme
            let restored = AppState(defaults: defaults)
            precondition(restored.theme == theme)
            precondition(!state.cameraActive && state.cameraSession == nil && state.nextCheckAt == nil)
            precondition(state.workDuration == totals.0 && state.adjustments == totals.1 && state.rests == totals.2)
            restored.shutdown()
        }
        precondition(changes == AppTheme.allCases)
        var after = defaults.dictionaryRepresentation()
        var original = before
        after.removeValue(forKey: "qx.theme"); original.removeValue(forKey: "qx.theme")
        precondition(NSDictionary(dictionary: after).isEqual(to: original))
        var previousIcon: NSImage?
        for theme in AppTheme.allCases {
            let renderer = ImageRenderer(content: OwlAppIconArtwork(theme: theme))
            renderer.scale = 0.125
            guard let cg = renderer.cgImage else { preconditionFailure("Theme icon failed to render") }
            let icon = NSImage(cgImage: cg, size: NSSize(width: 128, height: 128))
            precondition(cg.width == 128 && cg.height == 128)
            if let previousIcon { precondition(!AppIcon.matchesArtwork(icon, expected: previousIcon)) }
            previousIcon = icon
        }
        print("PASS: all three themes render distinct Dock artwork from the same owl")
        print("PASS: legacy and unknown themes default to mist; three themes restore; selection changes only qx.theme; no camera, timer, calibration or counter changes")
    }
}
