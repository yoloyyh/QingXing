#if DEBUG
import AppKit
import SwiftUI
import HeathyCore

/// Development-only renders of camera-free UI. Excluded from the release app.
@MainActor
enum PreviewRenderer {
    static func renderHealthRing(to directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                NSApplication.shared.appearance = NSAppearance(named: appearance)
                for theme in AppTheme.allCases {
                    let suite = "local.qingxing.health-preview.\(UUID().uuidString)"
                    let defaults = UserDefaults(suiteName: suite)!
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let state = AppState(defaults: defaults)
                    defer { state.shutdown() }
                    state.theme = theme
                    state.workMinutes = 15
                    state.breakMinutes = 1
                    state.toggleManualTimer()
                    let start = Date()
                    for second in 0...900 { state.tick(at: start.addingTimeInterval(Double(second))) }
                    if theme == .mist && name == "light" { try save(DashboardView(state: state), named: "work-due", directory: output) }
                    state.beginRest(at: start.addingTimeInterval(900))
                    state.detector.onStatus?(.off)
                    state.tick(at: start.addingTimeInterval(930))
                    precondition(state.healthEnergy == 0.5)
                    if theme == .mist { try save(DashboardView(state: state), named: "charging-\(name)", directory: output) }
                    state.tick(at: start.addingTimeInterval(960))
                    precondition(state.restCompleted && state.notice?.rewardKind == .rest)
                    try save(ReminderCard(state: state), named: "full-\(theme.rawValue)-\(name)", directory: output)
                    if theme == .mist { try save(DashboardView(state: state), named: "full-dashboard-\(name)", directory: output) }
                    state.finishRest(at: start.addingTimeInterval(961))
                    state.handle([.adjusted, .adjusted, .adjusted])
                    try save(ReminderCard(state: state), named: "adjustment-\(theme.rawValue)-\(name)", directory: output)
                    precondition(state.adjustments == 3 && state.rests == 1 && !state.cameraActive && state.cameraSession == nil)
                }
            }
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            try save(HealthRingPreviewSheet(), named: "health-ring-states", directory: output)
            print("PASS: health ring work/charging/full and repeat adjustment previews in all themes, without camera activation")
        } catch { fputs("Health ring render failed: \(error)\n", stderr); exit(1) }
    }

    static func renderAppIcon(to path: String) {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        let renderer = ImageRenderer(content: OwlAppIconArtwork())
        renderer.scale = 1
        renderer.isOpaque = false
        guard let cgImage = renderer.cgImage, cgImage.width == 1_024, cgImage.height == 1_024,
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            fputs("App icon render failed\n", stderr); exit(1)
        }
        do { try data.write(to: URL(fileURLWithPath: path)) }
        catch { fputs("App icon write failed: \(error)\n", stderr); exit(1) }
        print("Rendered mist-blue owl app icon: 1024 × 1024 pixels, transparent corners")
    }

    static func renderThemes(to directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let suite = "local.qingxing.theme-preview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let state = AppState(defaults: defaults)
            defer { state.shutdown() }
            for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                NSApplication.shared.appearance = NSAppearance(named: appearance)
                for theme in AppTheme.allCases {
                    state.theme = theme
                    state.page = .settings
                    try save(DashboardView(state: state), named: "theme-\(theme.rawValue)-\(name)-settings", directory: output)
                    state.tryDistanceDemo()
                    try save(ReminderCard(state: state), named: "theme-\(theme.rawValue)-\(name)-reminder", directory: output)
                    state.closeNotice()
                }
            }
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            try save(ThemePreviewSheet(), named: "theme-comparison", directory: output)
            print("PASS: theme previews rendered without camera activation")
        } catch { fputs("Theme render failed: \(error)\n", stderr); exit(1) }
    }

    static func render(to directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let state = AppState(defaults: UserDefaults(suiteName: "local.qingxing.preview.\(UUID().uuidString)")!)
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            try save(OwlExpressionSheet(), named: "owl-expressions", directory: output)
            try save(DashboardView(state: state), named: "dashboard", directory: output)
            state.quiet = true
            try save(DashboardView(state: state), named: "quiet-dashboard", directory: output)
            state.quiet = false
            state.toggleManualTimer()
            precondition(state.manualTimerRunning && !state.cameraActive)
            try save(DashboardView(state: state), named: "timer", directory: output)
            state.toggleManualTimer()
            state.page = .settings
            try save(DashboardView(state: state), named: "settings", directory: output)
            state.page = .dashboard
            let restStart = Date()
            let restState = AppState(defaults: UserDefaults(suiteName: "local.qingxing.rest-preview.\(UUID().uuidString)")!)
            restState.breakMinutes = 10
            restState.beginRest(at: restStart)
            restState.tick(at: restStart.addingTimeInterval(300))
            precondition(restState.restRemaining == 300 && restState.restProgress == 0.5 && restState.activeRestMinutes == 10)
            try save(DashboardView(state: restState), named: "rest-countdown-custom", directory: output)
            restState.shutdown()
            let totalsBeforeDemo = (state.adjustments, state.rests)
            state.tryDemo()
            try save(ReminderCard(state: state), named: "reminder", directory: output)
            state.completeDemo()
            precondition(state.adjustments == totalsBeforeDemo.0 && state.rests == totalsBeforeDemo.1, "Demo must not create real rewards")
            try save(ReminderCard(state: state), named: "reward", directory: output)
            state.hideNotice()
            for (name, level) in [("distance-gentle", DistanceReminderLevel.gentle), ("distance-firm", .firm), ("distance-urgent", .urgent)] {
                state.tryDistanceDemo(level: level)
                try save(ReminderCard(state: state), named: name, directory: output)
                state.closeNotice()
            }
            for (name, expression) in [("owl-too-close", BuddyExpression.tooClose), ("owl-head-down", .headDown), ("owl-head-tilt", .headTilt), ("owl-unclear", .unclear)] {
                state.tryDemo(expression: expression)
                precondition(state.buddyExpression == expression && state.notice?.buddyExpression == expression)
                try save(ReminderCard(state: state), named: name, directory: output)
                state.closeNotice()
            }
            for (name, level) in [("rest-due", RestReminderLevel.due), ("rest-overdue", .overdue), ("rest-urgent", .urgent)] {
                state.tryRestDemo(level: level)
                try save(ReminderCard(state: state), named: name, directory: output)
                if level == .urgent {
                    try save(RestScenePreview(state: state, level: level), named: "rest-urgent-scene", directory: output)
                }
            }
            state.completeDemo()
            precondition(state.adjustments == totalsBeforeDemo.0 && state.rests == totalsBeforeDemo.1 && state.workDuration == 0)
            precondition(state.restEdgeLevel == .none && !state.cameraActive)
            try save(ReminderCard(state: state), named: "rest-star-reward", directory: output)
            state.hideNotice()
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
            state.tryDistanceDemo(level: .urgent)
            try save(ReminderCard(state: state), named: "distance-urgent-dark", directory: output)
            state.closeNotice()
            try save(OwlExpressionSheet(), named: "owl-expressions-dark", directory: output)
            try save(DashboardView(state: state), named: "dashboard-dark", directory: output)
            state.page = .settings
            try save(DashboardView(state: state), named: "settings-dark", directory: output)
            state.page = .dashboard
            state.tryRestDemo(level: .urgent)
            try save(ReminderCard(state: state), named: "rest-urgent-dark", directory: output)
            state.closeNotice()
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
            state.enableCamera()
            precondition(state.page == .calibration && state.canStartCalibration)
            state.enableCamera()
            precondition(state.canStartCalibration && !state.calibrationCaptureStarted && !state.cameraBusy)
            try save(DashboardView(state: state), named: "calibration-simple", directory: output)
            state.cancelCalibration()
            print("PASS: no-input calibration waits for an explicit start without camera activation")
            let migrationDefaults = UserDefaults(suiteName: "local.qingxing.preview.\(UUID().uuidString)")!
            migrationDefaults.set(try JSONEncoder().encode(Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "preview")), forKey: "qx.calibration")
            let migrated = AppState(defaults: migrationDefaults)
            precondition(!migrated.needsDistanceCalibration && migrated.savedCalibration?.referenceDistanceCM == 60)
            precondition(migrated.savedCalibration?.usesDefaultDistance == true && migrated.savedCalibration?.faceWidth == 0.2)
            guard migrated.needsAnyCalibration else { throw RenderError.missingPostureCalibration }
            migrated.beginCalibration()
            precondition(migrated.page == .calibration && migrated.canStartCalibration && !migrated.cameraBusy && !migrated.cameraActive)
            migrated.shutdown()
            migrationDefaults.set(try JSONEncoder().encode(Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "preview", referenceDistanceCM: 60)), forKey: "qx.calibration")
            let restored = AppState(defaults: migrationDefaults)
            precondition(!restored.needsDistanceCalibration && restored.savedCalibration?.referenceDistanceCM == 60)
            restored.beginCalibration()
            precondition(restored.canStartCalibration && !restored.cameraActive && !restored.cameraBusy)
            restored.enableCamera()
            precondition(restored.page == .calibration && !restored.calibrationCaptureStarted && !restored.cameraActive && !restored.cameraBusy)
            restored.shutdown()
            let oldShoulders = PostureFeatures(faceShoulderRatio: 0.4, headOffset: 0, headHeight: 0.5, shoulderTilt: 0, usesFaceCenter: true)
            migrationDefaults.set(try JSONEncoder().encode(Calibration(faceWidth: 0.2, faceShoulderRatio: 0.4,
                cameraID: "preview", referenceDistanceCM: 60, postureReference: oldShoulders)), forKey: "qx.calibration")
            let oldModel = AppState(defaults: migrationDefaults)
            precondition(!oldModel.needsDistanceCalibration && !oldModel.hasPostureReference && oldModel.needsAnyCalibration)
            oldModel.beginCalibration()
            precondition(oldModel.page == .calibration && !oldModel.cameraActive && !oldModel.cameraBusy)
            oldModel.shutdown()
            let currentShoulders = PostureFeatures(faceShoulderRatio: 0.4, headOffset: 0, headHeight: 0.5,
                shoulderTilt: 0, usesFaceCenter: true, shoulderModel: PoseNetDecoder.modelID)
            migrationDefaults.set(try JSONEncoder().encode(Calibration(faceWidth: 0.2, faceShoulderRatio: 0.4,
                cameraID: "preview", referenceDistanceCM: 60, postureReference: currentShoulders)), forKey: "qx.calibration")
            let newModel = AppState(defaults: migrationDefaults)
            precondition(newModel.hasPostureReference && !newModel.hasHeadReference && newModel.needsAnyCalibration && !newModel.cameraActive)
            newModel.shutdown()
            print("PASS: old shoulder model requires calibration; current model reference restores; distance retained; camera off")
            let headOnly = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "preview", referenceDistanceCM: 60,
                headReference: HeadPoseFeatures(pitch: 0.1, roll: 0.02))
            migrationDefaults.set(try JSONEncoder().encode(headOnly), forKey: "qx.calibration")
            let headState = AppState(defaults: migrationDefaults)
            precondition(headState.hasHeadReference && headState.hasPostureReference && !headState.needsAnyCalibration)
            precondition(headState.postureLabel == "等待检测" && headState.postureIssue == nil)
            try save(DashboardView(state: headState), named: "head-reference-without-shoulders", directory: output)
            headState.beginCalibration()
            precondition(!headState.cameraActive && !headState.cameraBusy)
            try save(DashboardView(state: headState), named: "head-only-calibration-guide", directory: output)
            headState.shutdown()
            let legacyAngles = PostureFeatures(faceShoulderRatio: 0.4, headOffset: 0, headHeight: 0.5, shoulderTilt: 0, pitch: 0.14)
            migrationDefaults.set(try JSONEncoder().encode(Calibration(faceWidth: 0.2, faceShoulderRatio: 0.4,
                cameraID: "preview", referenceDistanceCM: 72, postureReference: legacyAngles)), forKey: "qx.calibration")
            let migratedHead = AppState(defaults: migrationDefaults)
            precondition(migratedHead.hasHeadReference && migratedHead.savedCalibration?.headReference == HeadPoseFeatures(pitch: 0.14))
            precondition(migratedHead.savedCalibration?.referenceDistanceCM == 72 && !migratedHead.cameraActive)
            migratedHead.shutdown()
            print("PASS: head-only reference restores without shoulders; legacy pitch migrates without guessing roll or changing distance")
            print("PASS: legacy migration and persisted centimeter reference restore without camera access")
            precondition(!state.cameraActive && state.cameraSession == nil)
            state.shutdown()
            print("PASS: rendered camera-free UI; no camera activation")
        } catch { fputs("Preview render failed: \(error)\n", stderr); exit(1) }
    }

    private static func save<Content: View>(_ content: Content, named name: String, directory: URL) throws {
        let host = NSHostingView(rootView: content)
        host.sizingOptions = [.intrinsicContentSize]
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSApplication.shared.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RenderError.empty }
        host.cacheDisplay(in: host.bounds, to: image)
        guard let data = image.representation(using: .png, properties: [:]) else { throw RenderError.empty }
        try data.write(to: directory.appendingPathComponent(name + ".png"))
        print("Rendered \(name): \(Int(size.width)) × \(Int(size.height)) pt")
        window.orderOut(nil)
    }
    private enum RenderError: Error { case empty, missingPostureCalibration }
}


private struct HealthRingPreviewSheet: View {
    var body: some View {
        HStack(spacing: 30) {
            phase("该充电啦", detail: "到了休息时间", expression: .restDue, progress: 0)
            phase("正在充能 · 50%", detail: "离开屏幕，慢慢补满", expression: .resting, progress: 0.5)
            phase("满血状态 · 100%", detail: "准备好再出发", expression: .happy, progress: 1)
        }.padding(32).background(ThemePalette(theme: .mist).paper)
    }
    private func phase(_ title: String, detail: String, expression: BuddyExpression, progress: Double) -> some View {
        VStack(spacing: 16) {
            HealthRingView(theme: .mist, expression: expression, progress: progress, isFull: progress == 1).frame(width: 180, height: 180)
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(ThemePalette(theme: .mist).ink)
            Text(detail).font(.system(size: 13)).foregroundStyle(ThemePalette(theme: .mist).muted)
        }.frame(width: 245)
    }
}

private struct ThemePreviewSheet: View {
    var body: some View {
        HStack(spacing: 18) {
            ForEach(AppTheme.allCases) { theme in
                let palette = ThemePalette(theme: theme)
                VStack(spacing: 12) {
                    Text(theme.title).font(.system(size: 23, weight: .semibold))
                    OwlArtwork(theme: theme).frame(width: 170, height: 170)
                    Text("同一只猫头鹰，同样的状态回应").font(.system(size: 12))
                    HStack {
                        OwlArtwork(expression: .tooClose, dizzy: true, theme: theme)
                        OwlArtwork(expression: .happy, theme: theme)
                    }.frame(height: 90)
                    Text("主窗口 · 提醒 · Dock 同步切换").font(.system(size: 11)).foregroundStyle(palette.muted)
                    Text("已选择").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(10).background(palette.green, in: Capsule())
                }.padding(22).frame(width: 290).background(palette.paper, in: RoundedRectangle(cornerRadius: 22)).foregroundStyle(palette.ink)
            }
        }.padding(24).background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct OwlExpressionSheet: View {
    private let items: [(BuddyExpression, String, String)] = [
        (.calm, "陪你专注", "安静陪伴，等待检测"),
        (.tooClose, "靠太近啦", "大眼睛 · 晕圈 · 轻轻后靠"),
        (.headDown, "低头过多", "垂头 · 提示轻轻抬头"),
        (.headTilt, "头部侧倾", "歪头 · 提示慢慢回正"),
        (.restDue, "该休息啦", "打哈欠 · 伸展翅膀"),
        (.happy, "调整完成", "眯眼 · 小跳跃 · 星星"),
        (.checking, "检测中", "睁眼观察 · 最多 5 秒"),
        (.unclear, "这轮没看清", "疑惑 · 等下次有效结果")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("小猫头鹰 · 表情会说话").font(.system(size: 25, weight: .semibold))
            Text("眼睛回应距离，头部回应姿态，翅膀邀请休息。")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(185)), count: 4), spacing: 12) {
                ForEach(items, id: \.0) { expression, title, detail in
                    VStack(spacing: 7) {
                        OwlArtwork(expression: expression, dizzy: expression == .tooClose).frame(width: 132, height: 132)
                        Text(title).font(.system(size: 15, weight: .semibold))
                        Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }.frame(width: 185, height: 200).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            Text("示意图 · 动作在状态切换时短暂播放 · 结果来自最近一轮检测")
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.padding(24).background(Palette.paper).foregroundStyle(Palette.ink)
    }
}

private struct RestScenePreview: View {
    @ObservedObject var state: AppState
    let level: RestReminderLevel
    var body: some View {
        ZStack {
            Color(red: 0.92, green: 0.94, blue: 0.92)
            VStack(alignment: .leading, spacing: 18) {
                Text("专注工作区 · 示意图").font(.system(size: 18, weight: .medium))
                ForEach(0..<7) { index in
                    RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12))
                        .frame(width: index % 2 == 0 ? 590 : 410, height: 12)
                }
                Spacer()
            }.padding(38)
            RestEdgeGlow(level: level)
            ReminderCard(state: state)
        }.frame(width: 800, height: 560)
    }
}
#endif
