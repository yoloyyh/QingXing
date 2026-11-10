import AppKit
import AVFoundation
import Combine
import SwiftUI
import Darwin

@main
enum QingXing {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--check-shoulder-model") {
            do { try PoseNetShoulderDetector.checkBundledModel() }
            catch { print("FAIL: shoulder model check: \(error)"); exit(1) }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if CommandLine.arguments.contains("--check-app-icon") {
            app.finishLaunching()
            guard let image = AppIcon.install(),
                  AppIcon.matchesArtwork(app.applicationIconImage, expected: image) else {
                print("FAIL: bundled application icon could not be installed"); exit(1)
            }
            print("PASS: application and Dock icon use the bundled mist-blue owl artwork directly")
            return
        }
        if CommandLine.arguments.contains("--check-distance-follow-up") {
            do { try DistanceFollowUpChecks.run() }
            catch { print("FAIL: distance follow-up check: \(error)"); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--check-background-startup") {
            do { try BackgroundStartupChecks.run() }
            catch { print("FAIL: background startup check: \(error)"); exit(1) }
            return
        }
        if CommandLine.arguments.contains("--enable-login-item") || CommandLine.arguments.contains("--login-item-status") {
            let login = LoginLaunchController()
            if CommandLine.arguments.contains("--enable-login-item") { login.setEnabled(true) }
            print("LOGIN_ITEM: enabled=\(login.enabled), requiresApproval=\(login.needsApproval), issue=\(login.issue ?? "none")")
            if login.issue != nil || (!login.enabled && !login.needsApproval && CommandLine.arguments.contains("--enable-login-item")) { exit(1) }
            return
        }
        if CommandLine.arguments.contains("--check-health-ring") {
            HealthRingChecks.run()
            return
        }
        if CommandLine.arguments.contains("--check-themes") {
            ThemeChecks.run()
            return
        }
        if CommandLine.arguments.contains("--check-buddy") {
            BuddyPresentationChecks.run()
            return
        }
        if CommandLine.arguments.contains("--check-rest-presentation") {
            RestEdgeController.checkConfiguration()
            return
        }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--render-health-ring"), CommandLine.arguments.count > index + 1 {
            PreviewRenderer.renderHealthRing(to: CommandLine.arguments[index + 1])
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-themes"), CommandLine.arguments.count > index + 1 {
            PreviewRenderer.renderThemes(to: CommandLine.arguments[index + 1])
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-app-icon"), CommandLine.arguments.count > index + 1 {
            PreviewRenderer.renderAppIcon(to: CommandLine.arguments[index + 1])
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
            PreviewRenderer.render(to: CommandLine.arguments[index + 1])
            return
        }
        #endif
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem!
    private var dashboard: NSHostingController<DashboardView>!
    private var dashboardPanel: NSWindow!
    private var reminderPanel: NSPanel!
    private var reminderHost: NSHostingView<ReminderCard>!
    private var stateSubscription: AnyCancellable?
    private var autoHide: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var dashboardWasSuspended = false
    private var restoreDashboardAfterSuspension = false
    private var shoulderDiagnostics: ShoulderDiagnostics?
    private let restEdges = RestEdgeController()
    private let loginLaunch = LoginLaunchController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIcon.install(theme: state.theme)
        state.onThemeChange = { theme in AppIcon.install(theme: theme) }
        let startedAtLogin = LoginLaunchController.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
        statusItem = NSStatusBar.system.statusItem(withLength: 64)
        statusItem.autosaveName = "QingXingStatusItem"
        if let button = statusItem.button {
            button.image = statusIcon()
            button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("轻醒，摄像头未开启")
        }
        dashboard = NSHostingController(rootView: DashboardView(state: state, startup: loginLaunch))
        dashboard.sizingOptions = [.preferredContentSize]
        dashboardPanel = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        dashboardPanel.title = "轻醒"
        dashboardPanel.contentViewController = dashboard
        dashboardPanel.level = .floating
        dashboardPanel.hidesOnDeactivate = false
        dashboardPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary]
        dashboardPanel.isReleasedWhenClosed = false
        dashboardPanel.isMovableByWindowBackground = true
        dashboardPanel.setAccessibilityLabel("轻醒常驻窗口")
        resizeDashboard()
        if let frame = (statusItem.button?.window?.screen ?? NSScreen.main)?.visibleFrame {
            dashboardPanel.setFrameOrigin(NSPoint(x: frame.maxX - 20 - dashboardPanel.frame.width,
                                                  y: frame.maxY - 16 - dashboardPanel.frame.height))
        }

        reminderHost = NSHostingView(rootView: ReminderCard(state: state))
        reminderPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        reminderPanel.contentView = reminderHost
        reminderPanel.isFloatingPanel = true
        reminderPanel.level = .floating
        reminderPanel.backgroundColor = .clear
        reminderPanel.isOpaque = false
        reminderPanel.hasShadow = true
        reminderPanel.hidesOnDeactivate = false
        reminderPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        reminderPanel.setAccessibilityLabel("轻醒小伙伴提醒")
        state.onNotice = { [weak self] notice in self?.present(notice) }
        stateSubscription = state.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refreshStatus() }
        installLifecycleObservers()
        state.restoreAutomaticChecks(cameraAuthorized: AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        refreshStatus()
        if !startedAtLogin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.openDashboard() }
        }
        if CommandLine.arguments.contains("--diagnose-shoulders") || CommandLine.arguments.contains("--diagnose-distance") {
            dashboardPanel.title = "轻醒 · 本机数字诊断（最多 5 秒）"
            shoulderDiagnostics = ShoulderDiagnostics(state: state)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.shoulderDiagnostics?.start() }
        }
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                print("SMOKE initial: camera=\(self.state.cameraActive), session=\(self.state.cameraSession != nil), distance=\(self.state.distanceLabel), issue=\(self.state.distanceIssue ?? "none")")
                guard !self.state.cameraActive, self.state.cameraSession == nil else { exit(1) }
                guard self.state.distanceLabel == "等待检测", self.state.distanceIssue == nil else { exit(1) }
                guard let button = self.statusItem.button, button.title == "轻醒",
                      button.bounds.width >= 56, button.bounds.width <= 64.5 else { exit(1) }
                let app = NSApplication.shared
                print("SMOKE panel: regular=\(app.activationPolicy() == .regular), level=\(self.dashboardPanel.level.rawValue), hides=\(self.dashboardPanel.hidesOnDeactivate), released=\(self.dashboardPanel.isReleasedWhenClosed), visible=\(self.dashboardPanel.isVisible)")
                guard app.activationPolicy() == .regular else { exit(1) }
                guard self.dashboardPanel.level == .floating, !self.dashboardPanel.hidesOnDeactivate,
                      !self.dashboardPanel.isReleasedWhenClosed else { exit(1) }
                self.dashboardPanel.performClose(nil)
                print("SMOKE close: visible=\(self.dashboardPanel.isVisible), running=\(app.isRunning)")
                guard !self.dashboardPanel.isVisible,
                      !self.applicationShouldTerminateAfterLastWindowClosed(app), app.isRunning else { exit(1) }
                _ = self.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
                guard self.dashboardPanel.isVisible else { exit(1) }
                if let window = button.window {
                    let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
                    print("PASS: labeled menu item (\(button.bounds.width) pt), frame=\(frame); reopening shows dashboard")
                }
                Task { @MainActor in
                    var activeTurns = 0
                    for _ in 0..<20 {
                        try? await Task.sleep(for: .milliseconds(50))
                        activeTurns = app.isActive ? activeTurns + 1 : 0
                        if activeTurns >= 2 { break }
                    }
                    guard activeTurns >= 2 else {
                        print("FAIL: smoke activation did not settle; visible=\(self.dashboardPanel.isVisible), active=\(app.isActive), hidden=\(app.isHidden), minimized=\(self.dashboardPanel.isMiniaturized)")
                        exit(1)
                    }
                    for (characters, keyCode) in [("a", UInt16(0)), ("\t", UInt16(48)), ("\u{1b}", UInt16(53))] {
                        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: self.dashboardPanel.windowNumber,
                            context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode) else { exit(1) }
                        app.sendEvent(event)
                        guard self.dashboardPanel.isVisible else {
                            print("FAIL: dashboard disappeared after its own test keyCode=\(keyCode)")
                            exit(1)
                        }
                    }
                    print("PASS: dashboard survives ordinary typing, Tab and Escape")
                    app.deactivate()
                    print("SMOKE ready for application switch")
                    fflush(stdout)
                    var inactiveTurns = 0
                    for _ in 0..<200 {
                        try? await Task.sleep(for: .milliseconds(50))
                        inactiveTurns = app.isActive ? 0 : inactiveTurns + 1
                        if inactiveTurns >= 2 { break }
                    }
                    guard self.dashboardPanel.isVisible, !app.isActive, inactiveTurns >= 2 else {
                        print("FAIL: smoke residency after deactivation; visible=\(self.dashboardPanel.isVisible), active=\(app.isActive), hidden=\(app.isHidden), minimized=\(self.dashboardPanel.isMiniaturized)")
                        exit(1)
                    }
                    guard self.dashboardPanel.occlusionState.contains(.visible) else {
                        print("FAIL: dashboard remains ordered in but is not actually visible after application switch")
                        exit(1)
                    }
                    guard !self.state.cameraActive, self.state.cameraSession == nil else { exit(1) }
                    print("PASS: regular app access; dashboard stays visible after app deactivation")
                    print("PASS: closing the dashboard keeps the app running; reopening restores it")
                    print("PASS: launched without camera capture or permission request")
                    print("PASS: initial distance waits for detection without an assessment failure")
                    app.terminate(nil)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.isVisible = true
        openDashboard()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) { loginLaunch.refresh() }

    @objc private func statusClicked() {
        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let pause = NSMenuItem(title: state.isPaused ? "继续提醒" : "暂停 15 分钟", action: #selector(togglePause), keyEquivalent: "")
            pause.target = self
            menu.addItem(pause)
            let quiet = NSMenuItem(title: state.quiet ? "关闭安静模式" : "开启安静模式", action: #selector(toggleQuiet), keyEquivalent: "")
            quiet.target = self
            menu.addItem(quiet)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出轻醒", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.addItem(quit)
            if let button = statusItem.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        } else if dashboardPanel.isVisible && !dashboardPanel.isMiniaturized { dashboardPanel.orderOut(nil) }
        else { openDashboard() }
    }

    @objc private func togglePause() { state.isPaused ? state.resume() : state.pause() }
    @objc private func toggleQuiet() { state.quiet.toggle() }

    private func openDashboard(activate: Bool = true) {
        guard !state.systemSuspended else { return }
        let keepReminder = state.notice?.isAttentionReminder == true || state.notice?.kind == .reward
        if !keepReminder { reminderPanel.orderOut(nil) }
        resizeDashboard()
        if dashboardPanel.isMiniaturized { dashboardPanel.deminiaturize(nil) }
        if activate {
            NSApplication.shared.activate(ignoringOtherApps: true)
            dashboardPanel.makeKeyAndOrderFront(nil)
        } else {
            dashboardPanel.orderFrontRegardless()
        }
        if keepReminder { present(state.notice) }
    }

    private func resizeDashboard() {
        dashboard.view.layoutSubtreeIfNeeded()
        let size = dashboard.view.fittingSize
        guard size.width > 0, size.height > 0,
              dashboardPanel.contentRect(forFrameRect: dashboardPanel.frame).size != size else { return }
        let top = dashboardPanel.frame.maxY
        dashboardPanel.setContentSize(size)
        dashboardPanel.setFrameOrigin(NSPoint(x: dashboardPanel.frame.minX, y: top - dashboardPanel.frame.height))
    }

    private func refreshStatus() {
        guard let button = statusItem.button else { return }
        let restLevel = state.restPresentationLevel
        let attentionLevel = max(restLevel, state.distancePresentationLevel.emphasis)
        button.title = restLevel == .none ? "轻醒" : "休息啦"
        button.contentTintColor = state.quiet ? .systemOrange : (attentionLevel == .urgent ? .systemRed : (attentionLevel == .overdue ? .systemOrange : nil))
        let symbol: String?
        if state.cameraActive { symbol = "camera.fill" }
        else if state.isPaused { symbol = "pause.circle.fill" }
        else if state.quiet { symbol = "bell.slash.fill" }
        else if restLevel != .none { symbol = "cup.and.saucer.fill" }
        else if state.needsAdjustment || state.distancePresentationLevel != .none { symbol = "exclamationmark.circle" }
        else { symbol = nil }
        button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: state.statusLabel) } ?? statusIcon()
        let restDetail = restLevel == .none ? "" : "\n休息时间到 · 已超时 \(state.restOverdueMinutes) 分钟"
        let quietDetail = state.quiet ? "安静模式已开启，不弹窗；右键可恢复提醒。\n" : ""
        let distanceDetail = state.distanceFollowUpDetail.map { "\n" + $0 } ?? ""
        button.toolTip = "轻醒 · \(state.statusLabel)\n\(quietDetail)\(state.cameraDetail)\(restDetail)\(distanceDetail)\n点击查看；右键暂停或退出"
        button.setAccessibilityLabel("轻醒，\(state.statusLabel)，\(quietDetail)\(state.cameraDetail)\(restDetail)")
        restEdges.update(state.restEdgeLevel)
        if state.systemSuspended {
            if !dashboardWasSuspended {
                restoreDashboardAfterSuspension = dashboardPanel.isVisible && !dashboardPanel.isMiniaturized
                dashboardWasSuspended = true
            }
            dashboardPanel.orderOut(nil)
            reminderPanel.orderOut(nil)
            return
        }
        if dashboardWasSuspended {
            dashboardWasSuspended = false
            if restoreDashboardAfterSuspension { openDashboard(activate: false) }
            restoreDashboardAfterSuspension = false
        }
        if dashboardPanel.isVisible { resizeDashboard() }
        if reminderPanel.isVisible { resizeReminder() }
    }

    private func present(_ notice: BuddyNotice?) {
        autoHide?.cancel()
        autoHide = nil
        guard let notice, !state.quiet, !state.isPaused, !state.systemSuspended else { reminderPanel?.orderOut(nil); return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state.notice?.id == notice.id, !self.state.quiet,
                  !self.state.isPaused, !self.state.systemSuspended else { return }
            let remaining = notice.autoDismissDelay.map { max(0, $0 - Date().timeIntervalSince(notice.createdAt)) }
            if remaining == 0 { self.state.expireNotice(id: notice.id); return }
            self.resizeReminder()
            self.reminderPanel.level = notice.isAttentionReminder ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) : .floating
            self.reminderPanel.orderFrontRegardless()
            self.state.recordDistancePanelPresentation(noticeID: notice.id, visible: self.reminderPanel.isVisible)
            guard let delay = remaining else { return }
            let hide = DispatchWorkItem { [weak self] in
                guard let self, self.state.notice?.id == notice.id else { return }
                self.state.expireNotice(id: notice.id)
            }
            self.autoHide = hide
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: hide)
        }
    }

    private func resizeReminder() {
        reminderHost.layoutSubtreeIfNeeded()
        let size = reminderHost.fittingSize
        let screen = (state.notice?.isAttentionReminder == true || state.notice?.kind == .reward ? NSScreen.main : nil) ?? statusItem.button?.window?.screen ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let urgent = (state.notice?.kind == .rest && state.restPresentationLevel == .urgent) || state.notice?.kind == .distance || state.notice?.kind == .reward
        let origin = urgent ? NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
                            : NSPoint(x: frame.maxX - 20 - size.width, y: frame.maxY - 16 - size.height)
        reminderPanel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func installLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state.suspendForSystem(.sleep)
                self?.refreshStatus()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state.resumeFromSystem(.sleep)
                self?.refreshStatus()
            }
        })
        let distributed = DistributedNotificationCenter.default()
        lockObservers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state.suspendForSystem(.screenLock)
                self?.refreshStatus()
            }
        })
        lockObservers.append(distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.state.resumeFromSystem(.screenLock)
                self?.refreshStatus()
            }
        })
    }

    func applicationWillTerminate(_ notification: Notification) {
        autoHide?.cancel()
        restEdges.hide()
        state.shutdown()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        lockObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }

    private func statusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 2, width: 17, height: 14), xRadius: 7, yRadius: 7).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 6, y: 8, width: 1.8, height: 2.4)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11, y: 8, width: 1.8, height: 2.4)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
