import HeathyCore
import SwiftUI

extension BuddyExpression {
    var title: String {
        switch self {
        case .calm: return "坐舒服一点，再出发"
        case .checking: return "我来看看，5 秒就好"
        case .tooClose: return "靠太近啦，往后一点点"
        case .headDown: return "抬抬头，看看前方"
        case .headTilt: return "小脑袋，轻轻回正"
        case .posture: return "调整一下，坐得更舒服"
        case .restDue: return "该休息啦，给自己充个电"
        case .resting: return "让身体，换个节奏"
        case .happy: return "调整成功，舒服多了"
        case .unclear: return "这轮没看清，等你准备好"
        case .paused: return "先安静陪你一会儿"
        }
    }
    var accessibilityDescription: String {
        switch self {
        case .calm: return "小猫头鹰安静陪伴"
        case .checking: return "小猫头鹰睁眼观察，正在检测"
        case .tooClose: return "小猫头鹰睁大眼睛、展开翅膀，提醒往后靠"
        case .headDown: return "小猫头鹰低下头，提示轻轻抬头"
        case .headTilt: return "小猫头鹰歪头，提示轻轻回正"
        case .posture: return "小猫头鹰关注头肩位置变化"
        case .restDue: return "小猫头鹰打哈欠、伸翅膀，邀请休息"
        case .resting: return "小猫头鹰闭眼放松，正在休息"
        case .happy: return "小猫头鹰眯眼开心，星星庆祝"
        case .unclear: return "小猫头鹰疑惑，未获得有效检测结果"
        case .paused: return "小猫头鹰安静闭眼，提醒已暂停"
        }
    }
}

struct BuddyView: View {
    var theme: AppTheme = .mist
    var expression: BuddyExpression = .calm
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = 0.0
    @State private var reacting = false

    var body: some View {
        OwlArtwork(expression: expression, motion: motion, dizzy: reacting && expression == .tooClose, theme: theme)
            .accessibilityElement(children: .ignore).accessibilityLabel(expression.accessibilityDescription)
            .task(id: "\(expression.rawValue)-\(reduceMotion)") {
                motion = 0; reacting = false
                guard !reduceMotion, expression != .calm, expression != .paused else { return }
                reacting = true
                withAnimation(.easeInOut(duration: 0.55).repeatCount(2, autoreverses: true)) { motion = 1 }
                do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
                reacting = false
                motion = 0
            }
    }
}

/// Unit-coordinate vector artwork shared by live views and static expression previews.
struct OwlArtwork: View, Animatable {
    var expression: BuddyExpression = .calm
    var motion: Double = 0
    var dizzy = false
    var animatableData: Double { get { motion } set { motion = newValue } }
    var theme: AppTheme = .mist
    private var ink: Color { theme.owlInk }
    private var feather: Color { theme.feather }
    private var cream: Color { theme.cream }
    private let gold = Color(red: 0.88, green: 0.59, blue: 0.28)

    var body: some View {
        Canvas { context, size in
            var ctx = context
            let scale = min(size.width, size.height) / 100
            ctx.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            draw(in: &ctx)
        }
    }

    private func draw(in ctx: inout GraphicsContext) {
        ctx.fill(Path(ellipseIn: CGRect(x: 25, y: 91, width: 50, height: 6)), with: .color(ink.opacity(0.09)))
        var bird = ctx
        if expression == .happy { bird.translateBy(x: 0, y: -5 * motion) }
        for x: CGFloat in [35, 53] {
            bird.fill(Path(roundedRect: CGRect(x: x, y: 86, width: 12, height: 5), cornerRadius: 2.5), with: .color(gold))
        }
        bird.fill(Path(ellipseIn: CGRect(x: 24, y: 42, width: 52, height: 47)), with: .linearGradient(
            Gradient(colors: [theme.lightFeather, feather]),
            startPoint: CGPoint(x: 30, y: 44), endPoint: CGPoint(x: 65, y: 90)))
        bird.fill(Path(ellipseIn: CGRect(x: 34, y: 58, width: 32, height: 27)), with: .color(cream.opacity(0.85)))
        for (x, y): (CGFloat, CGFloat) in [(43, 70), (56, 70), (50, 77)] {
            var mark = Path(); mark.move(to: CGPoint(x: x - 2, y: y)); mark.addQuadCurve(to: CGPoint(x: x + 2, y: y), control: CGPoint(x: x, y: y + 4))
            bird.stroke(mark, with: .color(feather.opacity(0.55)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        wing(in: bird, left: true)
        wing(in: bird, left: false)
        var head = bird
        let tilt: Double = expression == .headTilt ? 17 - 7 * motion : (expression == .unclear ? -9 : (expression == .resting ? -5 : 0))
        let down = expression == .headDown
        head.translateBy(x: 50 + (expression == .posture ? 5 : 0), y: 52 + (down ? 7 - 3 * motion : 0))
        head.rotate(by: .degrees(tilt))
        head.scaleBy(x: down ? 1.03 : 1, y: down ? 0.82 : 1)
        head.translateBy(x: -50, y: -52)
        var tufts = Path()
        tufts.move(to: CGPoint(x: 19, y: 27)); tufts.addQuadCurve(to: CGPoint(x: 18, y: 10), control: CGPoint(x: 16, y: 17)); tufts.addQuadCurve(to: CGPoint(x: 37, y: 22), control: CGPoint(x: 29, y: 10)); tufts.closeSubpath()
        tufts.move(to: CGPoint(x: 63, y: 22)); tufts.addQuadCurve(to: CGPoint(x: 82, y: 10), control: CGPoint(x: 71, y: 10)); tufts.addQuadCurve(to: CGPoint(x: 81, y: 27), control: CGPoint(x: 84, y: 17)); tufts.closeSubpath()
        head.fill(tufts, with: .color(feather))
        head.fill(Path(roundedRect: CGRect(x: 17, y: 14, width: 66, height: 48), cornerRadius: 23), with: .linearGradient(
            Gradient(colors: [theme.lightFeather, feather]),
            startPoint: CGPoint(x: 30, y: 14), endPoint: CGPoint(x: 65, y: 61)))
        for x: CGFloat in [21, 49] {
            head.fill(Path(ellipseIn: CGRect(x: x, y: 22, width: 30, height: 34)), with: .color(cream))
        }
        eye(in: head, center: CGPoint(x: 36, y: 37), left: true)
        eye(in: head, center: CGPoint(x: 64, y: 37), left: false)
        for x: CGFloat in [23, 68] {
            head.fill(Path(ellipseIn: CGRect(x: x, y: 46, width: 9, height: 4)), with: .color(Color(red: 0.92, green: 0.54, blue: 0.43).opacity(0.48)))
        }
        if expression == .restDue {
            head.fill(Path(ellipseIn: CGRect(x: 47, y: 46, width: 6, height: 9)), with: .color(ink))
        } else {
            var beak = Path(); beak.move(to: CGPoint(x: 46, y: 46)); beak.addQuadCurve(to: CGPoint(x: 54, y: 46), control: CGPoint(x: 50, y: 43)); beak.addLine(to: CGPoint(x: 50, y: 54)); beak.closeSubpath()
            head.fill(beak, with: .color(gold))
        }
        decorations(in: ctx)
    }

    private func wing(in context: GraphicsContext, left: Bool) {
        var ctx = context
        let open = expression == .tooClose || expression == .restDue || expression == .happy
        let angle = open ? 55 + 10 * motion : (expression == .resting ? 8 : 18)
        ctx.translateBy(x: left ? 28 : 72, y: 56)
        ctx.rotate(by: .degrees(left ? angle : -angle))
        ctx.fill(Path(ellipseIn: CGRect(x: -7, y: -2, width: 14, height: 31)), with: .color(feather))
        var line = Path(); line.move(to: CGPoint(x: 0, y: 10)); line.addQuadCurve(to: CGPoint(x: 1, y: 23), control: CGPoint(x: -2, y: 18))
        ctx.stroke(line, with: .color(cream.opacity(0.3)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private func eye(in context: GraphicsContext, center: CGPoint, left: Bool) {
        var ctx = context
        ctx.translateBy(x: center.x, y: center.y)
        let closed = expression == .happy || expression == .resting || expression == .paused || expression == .restDue
        if closed {
            var lid = Path(); lid.move(to: CGPoint(x: -7, y: 0))
            lid.addQuadCurve(to: CGPoint(x: 7, y: 0), control: CGPoint(x: 0, y: expression == .happy ? -8 : 6))
            ctx.stroke(lid, with: .color(ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            return
        }
        let big = expression == .tooClose
        let radius: CGFloat = big ? 13 : 10
        ctx.fill(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)), with: .color(.white))
        ctx.stroke(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)), with: .color(feather.opacity(0.25)), lineWidth: 0.8)
        if big && dizzy {
            var spiral = Path()
            for index in 0...80 {
                let angle = Double(index) / 80 * .pi * 4.5 + motion * .pi / 3
                let r = Double(index) / 80 * 8
                let point = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
                if index == 0 { spiral.move(to: point) } else { spiral.addLine(to: point) }
            }
            ctx.stroke(spiral, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        } else {
            let x: CGFloat = expression == .checking ? -1 + 3 * motion : 0
            let y: CGFloat = expression == .headDown ? 3 : 0
            let pupil: CGFloat = big ? 6.4 : 4.7
            ctx.fill(Path(ellipseIn: CGRect(x: x - pupil, y: y - pupil, width: pupil * 2, height: pupil * 2)), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 3, width: 2.5, height: 2.5)), with: .color(.white))
        }
        if expression == .headDown || (expression == .unclear && left) {
            var lid = Path(); lid.move(to: CGPoint(x: -11, y: -9)); lid.addQuadCurve(to: CGPoint(x: 11, y: -9), control: CGPoint(x: 0, y: 2)); lid.closeSubpath()
            ctx.fill(lid, with: .color(cream))
        }
        var brow = Path()
        let browY: CGFloat = big ? -17 : -13
        brow.move(to: CGPoint(x: -6, y: browY + (left ? 0 : -1)))
        brow.addQuadCurve(to: CGPoint(x: 6, y: browY), control: CGPoint(x: 0, y: browY - 3))
        ctx.stroke(brow, with: .color(feather), style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
    }

    private func decorations(in ctx: GraphicsContext) {
        if expression == .happy {
            for (x, y, size): (CGFloat, CGFloat, CGFloat) in [(9, 30, 9), (90, 22, 12), (83, 66, 6)] {
                var star = Path(); star.move(to: CGPoint(x: x, y: y - size / 2)); star.addQuadCurve(to: CGPoint(x: x + size / 2, y: y), control: CGPoint(x: x + 1, y: y - 1)); star.addQuadCurve(to: CGPoint(x: x, y: y + size / 2), control: CGPoint(x: x + 1, y: y + 1)); star.addQuadCurve(to: CGPoint(x: x - size / 2, y: y), control: CGPoint(x: x - 1, y: y + 1)); star.addQuadCurve(to: CGPoint(x: x, y: y - size / 2), control: CGPoint(x: x - 1, y: y - 1)); star.closeSubpath()
                ctx.fill(star, with: .color(gold))
            }
        }
        let symbol: String?
        switch expression {
        case .headDown: symbol = "arrow.up"
        case .headTilt: symbol = "arrow.uturn.left"
        case .posture: symbol = "exclamationmark"
        case .unclear: symbol = "questionmark"
        case .paused: symbol = "moon.fill"
        case .checking: symbol = "viewfinder"
        default: symbol = nil
        }
        if let symbol {
            ctx.draw(Text(Image(systemName: symbol)).font(.system(size: 12, weight: .bold)).foregroundColor(Palette.ink.opacity(0.75)), at: CGPoint(x: 89, y: 23))
        }
        if expression == .restDue {
            ctx.draw(Text("z").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(Palette.green), at: CGPoint(x: 9, y: 21))
        }
        if expression == .resting {
            ctx.draw(Text(Image(systemName: "cup.and.saucer.fill")).font(.system(size: 16)).foregroundColor(feather), at: CGPoint(x: 82, y: 81))
        }
    }
}

struct OwlAppIconArtwork: View {
    var theme: AppTheme = .mist
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 190, style: .continuous)
                .fill(LinearGradient(colors: [theme.iconBackground.opacity(0.88), theme.iconBackground], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 190, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 3))
                .frame(width: 836, height: 836)
            OwlArtwork(expression: .calm, theme: theme)
                .frame(width: 1050, height: 1050).offset(y: 194)
                .frame(width: 836, height: 836)
                .clipShape(RoundedRectangle(cornerRadius: 190, style: .continuous))
        }.frame(width: 1024, height: 1024)
    }
}

