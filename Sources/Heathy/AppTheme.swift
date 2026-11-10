import SwiftUI
import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case mist, amber, latte
    var id: String { rawValue }
    var title: String {
        switch self { case .mist: return "雾蓝"; case .amber: return "琥珀棕"; case .latte: return "奶咖" }
    }
    var feather: Color {
        switch self {
        case .mist: return Color(red: 0.32, green: 0.47, blue: 0.62)
        case .amber: return Color(red: 0.60, green: 0.37, blue: 0.22)
        case .latte: return Color(red: 0.59, green: 0.46, blue: 0.42)
        }
    }
    var lightFeather: Color {
        switch self {
        case .mist: return Color(red: 0.64, green: 0.77, blue: 0.85)
        case .amber: return Color(red: 0.83, green: 0.66, blue: 0.43)
        case .latte: return Color(red: 0.85, green: 0.73, blue: 0.63)
        }
    }
    var owlInk: Color {
        switch self {
        case .mist: return Color(red: 0.17, green: 0.24, blue: 0.34)
        case .amber: return Color(red: 0.24, green: 0.17, blue: 0.14)
        case .latte: return Color(red: 0.30, green: 0.21, blue: 0.22)
        }
    }
    var cream: Color {
        switch self {
        case .mist: return Color(red: 0.97, green: 0.97, blue: 0.91)
        case .amber: return Color(red: 1, green: 0.94, blue: 0.80)
        case .latte: return Color(red: 1, green: 0.96, blue: 0.88)
        }
    }
    var iconBackground: Color {
        switch self {
        case .mist: return Color(red: 0.95, green: 0.89, blue: 0.80)
        case .amber: return Color(red: 0.16, green: 0.22, blue: 0.32)
        case .latte: return Color(red: 0.76, green: 0.47, blue: 0.42)
        }
    }
}

struct ThemePalette {
    let theme: AppTheme
    var ink: Color { Palette.adaptive(light: NSColor(theme.owlInk), dark: NSColor(white: 0.93, alpha: 1)) }
    var buddyInk: Color { theme.owlInk }
    var muted: Color { Palette.muted }
    var green: Color {
        switch theme {
        case .mist: return Palette.adaptive(light: .init(srgbRed: 0.25, green: 0.42, blue: 0.58, alpha: 1), dark: .init(srgbRed: 0.65, green: 0.80, blue: 0.91, alpha: 1))
        case .amber: return Palette.adaptive(light: .init(srgbRed: 0.47, green: 0.29, blue: 0.16, alpha: 1), dark: .init(srgbRed: 0.87, green: 0.69, blue: 0.46, alpha: 1))
        case .latte: return Palette.adaptive(light: .init(srgbRed: 0.60, green: 0.33, blue: 0.30, alpha: 1), dark: .init(srgbRed: 0.91, green: 0.69, blue: 0.64, alpha: 1))
        }
    }
    private var darkPaper: NSColor {
        switch theme {
        case .mist: return .init(srgbRed: 0.11, green: 0.15, blue: 0.20, alpha: 1)
        case .amber: return .init(srgbRed: 0.18, green: 0.14, blue: 0.11, alpha: 1)
        case .latte: return .init(srgbRed: 0.19, green: 0.14, blue: 0.15, alpha: 1)
        }
    }
    var paper: Color {
        let light: NSColor
        switch theme {
        case .mist: light = .init(srgbRed: 0.96, green: 0.97, blue: 0.97, alpha: 1)
        case .amber: light = .init(srgbRed: 0.98, green: 0.96, blue: 0.91, alpha: 1)
        case .latte: light = .init(srgbRed: 0.98, green: 0.95, blue: 0.94, alpha: 1)
        }
        return Palette.adaptive(light: light, dark: darkPaper)
    }
    var surface: Color { Palette.adaptive(light: .white, dark: darkPaper.blended(withFraction: 0.07, of: .white)!) }
    var line: Color { Palette.adaptive(light: NSColor(theme.feather).withAlphaComponent(0.23), dark: NSColor(white: 1, alpha: 0.16)) }
}
