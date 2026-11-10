import HeathyCore
import SwiftUI

/// Shares the existing owl and theme; only the work/rest budget controls the arc.
struct HealthRingView: View {
    var theme: AppTheme
    var expression: BuddyExpression
    var progress: Double
    var isFull = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { ThemePalette(theme: theme).green }
    private var fill: Double { min(1, max(0, progress)) }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(accent.opacity(isFull ? 0.13 : 0.04)).padding(11)
                Circle().stroke(accent.opacity(0.14), lineWidth: 10).padding(6)
                Circle().trim(from: 0, to: fill)
                    .stroke(AngularGradient(colors: [theme.lightFeather, accent, accent], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(6)
                    .shadow(color: accent.opacity(isFull ? 0.30 : 0), radius: 8)
                BuddyView(theme: theme, expression: expression)
                    .frame(width: size * 0.78, height: size * 0.78)
                if isFull {
                    Image(systemName: "bolt.fill").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white).frame(width: 30, height: 30)
                        .background(accent, in: Circle())
                        .overlay(Circle().stroke(ThemePalette(theme: theme).paper, lineWidth: 3))
                        .offset(x: size * 0.31, y: size * 0.31)
                }
            }.frame(width: size, height: size)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: fill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFull ? "休息完成，健康环已充满" : "健康环，工作与休息进度")
        .accessibilityValue("\(Int(fill * 100))%")
    }
}

struct DailyHealthAchievements: View {
    let theme: AppTheme
    let adjustments: Int
    let rests: Int
    private var palette: ThemePalette { ThemePalette(theme: theme) }
    var body: some View {
        HStack(spacing: 10) {
            achievement(adjustments, label: "今日调整", symbol: "checkmark.circle.fill")
            achievement(rests, label: "今日充满", symbol: "bolt.circle.fill")
        }
    }
    private func achievement(_ count: Int, label: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(palette.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) 次").font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(label).font(.system(size: 10)).foregroundStyle(palette.muted)
            }
            Spacer(minLength: 0)
        }.padding(11).frame(maxWidth: .infinity)
            .background(palette.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityElement(children: .ignore).accessibilityLabel("\(label) \(count) 次")
    }
}
