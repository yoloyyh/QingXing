import Foundation
import HeathyCore

@MainActor
enum BuddyPresentationChecks {
    static func run() {
        let suite = "local.qingxing.buddy-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        defer { state.shutdown() }
        let totals = (state.workDuration, state.adjustments, state.rests)
        precondition(state.buddyExpression == .calm)
        for expression: BuddyExpression in [.tooClose, .headDown, .headTilt, .posture, .checking, .unclear, .resting] {
            state.tryDemo(expression: expression)
            precondition(state.notice?.isDemo == true && state.notice?.buddyExpression == expression)
            precondition(state.buddyExpression == expression && state.buddyDetail.contains("演示"))
            state.completeDemo()
            precondition(state.buddyExpression == .happy && state.notice?.isDemo == true)
            state.closeNotice()
            precondition(state.notice == nil && state.buddyExpression == .calm)
        }
        precondition(BuddyNotice(kind: .posture, title: "", message: "", expression: .headDown).buddyExpression == .headDown)
        precondition(BuddyNotice(kind: .posture, title: "", message: "", expression: .headTilt).buddyExpression == .headTilt)
        precondition(BuddyNotice(kind: .distance, title: "", message: "").buddyExpression == .tooClose)
        precondition(BuddyNotice(kind: .recovering, title: "", message: "").buddyExpression == .calm)
        state.tryRestDemo()
        precondition(state.buddyExpression == .restDue)
        state.closeNotice()
        state.beginRest()
        precondition(state.buddyExpression == .resting)
        state.cancelRest()
        state.pause()
        precondition(state.buddyExpression == .paused && state.notice == nil)
        precondition(state.workDuration == totals.0 && state.adjustments == totals.1 && state.rests == totals.2)
        precondition(!state.cameraActive && state.cameraSession == nil && state.nextCheckAt == nil)
        checkDashboardResultCopy()
        checkUnmutingDistanceAlert()
        print("PASS: distinct owl expressions on dashboard and notices; demo exits and rewards preserve work time and totals; rest/pause take priority; no camera or visible windows")
    }

    private static func checkDashboardResultCopy() {
        let suite = "local.qingxing.result-copy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reference = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "offline:640x480", referenceDistanceCM: 60)
        defaults.set(try! JSONEncoder().encode(reference), forKey: "qx.calibration")
        defaults.set("offline", forKey: "qx.camera")
        defaults.set(true, forKey: "qx.checksStarted")
        defaults.set(true, forKey: "qx.cameraIntroSeen")
        let state = AppState(defaults: defaults)
        defer { state.shutdown() }
        state.restoreAutomaticChecks(cameraAuthorized: true)
        precondition(state.buddyHeadline == "等待首次检测")
        precondition(!state.buddyDetail.contains("最近一次检测结果"))
        func scan(_ sample: FrameFeatures) {
            state.prepareObservationWindow()
            state.detector.onStatus?(.running)
            state.detector.onSample?(sample, reference.cameraID, sample.isValid ? "" : "未检测到人脸", nil)
            state.detector.onStatus?(.off)
            state.detector.onWindowEnded?()
        }
        scan(.valid(faceWidth: 0.2))
        precondition(state.buddyHeadline == "上次距离在参考范围内")
        precondition(state.buddyDetail.contains("头部尚未校准"))
        precondition(state.buddyDetail.contains("刚刚检测") && state.buddyDetail.contains("分钟后再检测"))
        scan(.valid(faceWidth: 0.15))
        precondition(state.buddyHeadline == "上次距离比参考更远")
        scan(.unavailable)
        precondition(state.buddyHeadline == "这轮没看清")
        precondition(state.buddyDetail.contains("未检测到人脸"))
        state.pause()
        precondition(state.buddyHeadline == "已暂停提醒")
        precondition(!state.cameraActive)
        print("PASS: dashboard distinguishes waiting, measured distance, unknown head pose, farther position, failed scan and pause without camera access")
    }

    private static func checkUnmutingDistanceAlert() {
        let suite = "local.qingxing.unmute-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "qx.quiet")
        let engine = ReminderEngine()
        let state = AppState(defaults: defaults, engine: engine)
        defer { state.shutdown() }
        precondition(state.quiet && state.notice == nil)
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "offline", referenceDistanceCM: 60)
        let start = Date()
        for second in 0..<3 { precondition(engine.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(Double(second))).isEmpty) }
        precondition(engine.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(3)) == [.reminder(.distance)])
        precondition(engine.activeKind == .distance && state.notice == nil)
        var distanceNotices = 0
        state.onNotice = { if $0?.kind == .distance { distanceNotices += 1 } }
        state.quiet = false
        precondition(state.notice?.kind == .distance && state.notice?.isDemo == false && state.notice?.buddyExpression == .tooClose)
        precondition(distanceNotices == 1)
        state.quiet = false
        precondition(distanceNotices == 1)
        state.quiet = true
        engine.dismiss()
        state.quiet = false
        precondition(state.notice == nil && distanceNotices == 1)
        precondition(!state.cameraActive && state.cameraSession == nil && state.workDuration == 0 && state.adjustments == 0)
        print("PASS: persisted quiet mode blocks cards; unmuting replays a confirmed distance alert once without starting camera or granting rewards")
    }
}
