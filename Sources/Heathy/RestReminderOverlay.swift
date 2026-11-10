import AppKit
import HeathyCore
import SwiftUI

extension DistanceReminderLevel {
    var emphasis: RestReminderLevel {
        switch self {
        case .gentle, .firm: return .overdue
        case .urgent: return .urgent
        case .none: return .none
        }
    }
}

extension RestReminderLevel {
    var cueColor: Color {
        switch self {
        case .none, .due: return Palette.green
        case .overdue: return Palette.adaptive(light: NSColor(srgbRed: 0.67, green: 0.36, blue: 0.08, alpha: 1), dark: NSColor(srgbRed: 0.98, green: 0.72, blue: 0.34, alpha: 1))
        case .urgent: return Palette.adaptive(light: NSColor(srgbRed: 0.76, green: 0.24, blue: 0.18, alpha: 1), dark: NSColor(srgbRed: 0.98, green: 0.55, blue: 0.43, alpha: 1))
        }
    }
}

struct RestEdgeGlow: View {
    let level: RestReminderLevel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bright = false
    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(level.cueColor.opacity(bright ? 0.95 : 0.55), lineWidth: level == .urgent ? 7 : 4)
            .shadow(color: level.cueColor.opacity(0.4), radius: level == .urgent ? 12 : 8)
            .padding(2).allowsHitTesting(false).accessibilityHidden(true)
            .onAppear {
                if reduceMotion { bright = true }
                else { withAnimation(.easeInOut(duration: 2).repeatCount(3, autoreverses: true)) { bright = true } }
            }
    }
}

private final class PassiveRestPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RestEdgeController {
    private var panels: [NSPanel] = []
    private var currentLevel: RestReminderLevel = .none
    private var currentFrames: [NSRect] = []

    func update(_ level: RestReminderLevel) {
        guard level >= .overdue else { hide(); return }
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard level != currentLevel || frames != currentFrames else { return }
        hide()
        currentLevel = level
        currentFrames = frames
        panels = frames.map { frame in
            let panel = Self.makePanel(frame: frame, level: level)
            panel.orderFrontRegardless()
            return panel
        }
    }
    func hide() {
        panels.forEach { $0.close() }
        panels = []; currentFrames = []; currentLevel = .none
    }
    private static func makePanel(frame: NSRect, level: RestReminderLevel) -> NSPanel {
        let panel = PassiveRestPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: RestEdgeGlow(level: level))
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary]
        return panel
    }
    static func checkConfiguration() {
        let panel = makePanel(frame: NSRect(x: 0, y: 0, width: 800, height: 500), level: .urgent)
        precondition(panel.ignoresMouseEvents && !panel.canBecomeKey && !panel.canBecomeMain)
        precondition(!panel.isOpaque && !panel.hidesOnDeactivate && !panel.isVisible)
        precondition(panel.styleMask.contains(.nonactivatingPanel))
        panel.contentView?.layoutSubtreeIfNeeded()
        precondition(panel.contentView?.bounds.size == NSSize(width: 800, height: 500))
        precondition(BuddyNotice(kind: .rest, title: "", message: "").autoDismissDelay == 30)
        precondition(BuddyNotice(kind: .rest, title: "", message: "").isPersistentRest)
        precondition(!BuddyNotice(kind: .rest, title: "", message: "", isDemo: true).isPersistentRest)
        panel.close()
        let defaults = UserDefaults(suiteName: "local.qingxing.rest-check.\(UUID().uuidString)")!
        let state = AppState(defaults: defaults)
        let totals = (state.adjustments, state.rests, state.workDuration)
        state.tryRestDemo(level: .urgent)
        precondition(state.restEdgeLevel == .urgent && !state.cameraActive && state.cameraSession == nil)
        state.strongRestReminders = false
        precondition(state.restPresentationLevel == .due && state.restEdgeLevel == .none)
        state.strongRestReminders = true
        state.quiet = true
        precondition(state.restEdgeLevel == .none && state.notice == nil)
        state.quiet = false
        state.tryRestDemo(level: .overdue)
        state.pause()
        precondition(state.restEdgeLevel == .none && state.notice == nil)
        state.resume()
        precondition(!state.isPaused)
        precondition(state.adjustments == totals.0 && state.rests == totals.1 && state.workDuration == totals.2)
        precondition(!state.cameraActive && state.cameraSession == nil)
        state.shutdown()
        let completion = AppState(defaults: UserDefaults(suiteName: "local.qingxing.rest-completion.\(UUID().uuidString)")!)
        completion.tryRestDemo(level: .urgent)
        completion.completeDemo()
        precondition(completion.restEdgeLevel == .none && completion.notice?.kind == .reward && completion.notice?.isDemo == true)
        precondition(completion.rests == 0 && completion.adjustments == 0 && completion.workDuration == 0 && !completion.cameraActive)
        completion.shutdown()
        let real = AppState(defaults: UserDefaults(suiteName: "local.qingxing.rest-actions.\(UUID().uuidString)")!)
        real.workMinutes = 15
        real.toggleManualTimer()
        let start = Date()
        for second in 0...1_500 { real.tick(at: start.addingTimeInterval(Double(second))) }
        precondition(real.restUrgency == .urgent && real.notice?.isPersistentRest == true)
        let noticeID = real.notice?.id
        // With no distance reference, ordinary detection opens the guide only.
        real.enableCamera()
        precondition(real.page == .calibration && real.notice?.id == noticeID && !real.cameraActive)
        real.disableCamera()
        precondition(real.notice?.id == noticeID && real.notice?.isPersistentRest == true)
        real.snooze()
        precondition(real.notice == nil && real.restEdgeLevel == .none && real.nextCheckAt == nil)
        precondition(!real.cameraActive && real.cameraSession == nil)
        real.shutdown()
        checkScheduleSettings()
        print("PASS: rest reminder has a 30-second display limit; edge panels pass mouse events, cannot take focus and remain transparent; no panels shown")
        print("PASS: quiet, pause, emphasis off and demo completion hide edges; preview changes no work time, rewards or camera access")
        print("PASS: actual urgent notice survives opening calibration and stopping detection; rest snooze hides it without scheduling camera access")
    }

    private static func checkScheduleSettings() {
        let suite = "local.qingxing.schedule-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(60, forKey: "qx.restMinutes")
        let state = AppState(defaults: defaults)
        defer { state.shutdown() }
        precondition(state.workMinutes == 60 && state.breakMinutes == 5)
        state.workMinutes = 25
        state.breakMinutes = 10
        state.tryRestDemo()
        precondition(state.notice?.message.contains("10 分钟") == true)
        state.breakMinutes = 7
        precondition(state.notice?.message.contains("7 分钟") == true)
        state.closeNotice()
        state.toggleManualTimer()
        let start = Date()
        for second in 0...10 { state.tick(at: start.addingTimeInterval(Double(second))) }
        precondition(state.workDuration == 10 && state.remainingWork == 1_490)
        let restStart = start.addingTimeInterval(10)
        state.beginRest(at: restStart)
        precondition(state.restRemaining == 420 && state.activeRestMinutes == 7 && state.restProgress == 0)
        state.breakMinutes = 1
        state.tick(at: restStart.addingTimeInterval(210))
        precondition(state.restRemaining == 210 && state.activeRestMinutes == 7 && state.restProgress == 0.5)
        state.finishRest(at: restStart.addingTimeInterval(419))
        precondition(state.isResting && state.rests == 0 && state.workDuration == 10)
        state.finishRest(at: restStart.addingTimeInterval(420))
        precondition(!state.isResting && state.rests == 1 && state.workDuration == 0 && state.restProgress == 0)
        state.finishRest(at: restStart.addingTimeInterval(421))
        precondition(state.rests == 1 && state.nextCheckAt == nil && !state.cameraActive && state.cameraSession == nil)
        let restored = AppState(defaults: defaults)
        defer { restored.shutdown() }
        precondition(restored.workMinutes == 25 && restored.breakMinutes == 1)
        restored.clearLocalData()
        precondition(restored.workMinutes == 45 && restored.breakMinutes == 5 && !restored.isResting)
        precondition(defaults.object(forKey: "qx.restMinutes") == nil && defaults.object(forKey: "qx.breakMinutes") == nil)
        precondition(!restored.cameraActive && restored.cameraSession == nil)
        print("PASS: legacy work interval retained; rest defaults to five minutes; custom schedule persists; countdown and progress keep this rest's target; one reward; clear restores 45/5; no camera access")
    }
}
