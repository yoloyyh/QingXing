import Foundation
import HeathyCore

@MainActor
enum DistanceFollowUpChecks {
    static func run() throws {
        let suite = "local.qingxing.distance-follow-up.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reference = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "offline:640x480", referenceDistanceCM: 60)
        defaults.set(try JSONEncoder().encode(reference), forKey: "qx.calibration")
        defaults.set("offline", forKey: "qx.camera")
        defaults.set(true, forKey: "qx.checksStarted")
        defaults.set(true, forKey: "qx.cameraIntroSeen")
        let engine = ReminderEngine()
        let start = Date()
        var observedAt = start
        let state = AppState(defaults: defaults, engine: engine, observationTime: { observedAt })
        defer { state.shutdown() }
        state.restoreAutomaticChecks(cameraAuthorized: true)
        engine.calibration = reference
        func scan(at offset: TimeInterval, sample: FrameFeatures = .valid(faceWidth: 0.25), frameCount: Int = 10) {
            state.prepareObservationWindow()
            state.detector.onStatus?(.running)
            for index in 0..<frameCount {
                observedAt = start.addingTimeInterval(offset + Double(index) * 0.5)
                state.detector.onSample?(sample, reference.cameraID, sample.isValid ? "" : "未检测到人脸", nil)
            }
            state.detector.onStatus?(.off)
            state.detector.onWindowEnded?()
        }
        func checkInterval(_ expected: TimeInterval) {
            guard let date = state.nextCheckAt else { preconditionFailure("Missing scheduled check") }
            precondition(abs(date.timeIntervalSinceNow - expected) < 2)
        }
        scan(at: 0, frameCount: 4)
        precondition(state.distanceFollowUpActive && state.notice?.distanceLevel == .gentle)
        precondition(DistanceReminderLevel.gentle.emphasis == .overdue, "First confirmed proximity warning must have an amber attention cue")
        checkInterval(300)
        precondition(state.lastDistanceDecision == "已发出距离提醒，等待窗口显示")
        if let id = state.notice?.id { state.recordDistancePanelPresentation(noticeID: id, visible: true) }
        precondition(state.lastDistanceDecision == "距离弹窗已显示")
        state.hideNotice()
        scan(at: 305)
        precondition(state.notice?.distanceLevel == .firm && state.notice?.autoDismissDelay == 30 && state.notice?.isAttentionReminder == true)
        // Exercise postponing an in-progress round through the existing status boundary.
        // This does not start a capture session or use a camera.
        state.detector.onStatus?(.running)
        precondition(state.cameraActive)
        state.closeNotice()
        precondition(state.notice == nil && state.distanceFollowUpActive && !state.cameraActive && state.cameraStatus == .stopping)
        checkInterval(300)
        state.quiet = true
        scan(at: 610)
        precondition(state.notice == nil && engine.distanceReminderLevel == .urgent)
        precondition(state.lastDistanceDecision == "安静模式已拦截弹窗")
        state.quiet = false
        precondition(state.notice?.distanceLevel == .urgent)
        let urgentID = state.notice?.id
        scan(at: 915, sample: .unavailable)
        precondition(engine.distanceReminderLevel == .urgent && state.adjustments == 0 && state.notice?.id == urgentID)
        state.pause()
        precondition(state.nextCheckAt == nil && state.distanceFollowUpActive && !state.needsAdjustment && state.notice == nil)
        state.resume()
        checkInterval(300)
        state.beginRest(at: start)
        precondition(state.nextCheckAt == nil && state.distanceFollowUpActive)
        state.finishRest(at: start.addingTimeInterval(300))
        precondition(state.rests == 1 && state.adjustments == 0 && state.distanceFollowUpActive)
        checkInterval(300)
        scan(at: 1_215, sample: .valid(faceWidth: 0.2), frameCount: 4)
        precondition(!state.distanceFollowUpActive && state.adjustments == 1 && state.notice?.kind == .reward)
        checkInterval(1_800)
        scan(at: 1_230)
        precondition(state.notice?.kind == .distance && state.notice?.distanceLevel == .gentle && state.distanceFollowUpActive)
        state.dismissReminder()
        scan(at: 1_520, sample: .valid(faceWidth: 0.2))
        precondition(state.adjustments == 1)
        scan(at: 1_825)
        precondition(state.distanceFollowUpActive)
        state.dismissReminder()
        precondition(!state.distanceFollowUpActive && state.notice == nil)
        checkInterval(1_800)
        state.disableCamera()
        precondition(state.nextCheckAt == nil && !state.distanceFollowUpActive && !defaults.bool(forKey: "qx.checksStarted"))
        precondition(!state.cameraActive && state.cameraSession == nil)
        let demoSuite = "local.qingxing.distance-demo.\(UUID().uuidString)"
        let demoDefaults = UserDefaults(suiteName: demoSuite)!
        defer { demoDefaults.removePersistentDomain(forName: demoSuite) }
        let demo = AppState(defaults: demoDefaults)
        defer { demo.shutdown() }
        demo.tryDistanceDemo()
        demo.advanceDistanceDemo()
        precondition(demo.notice?.distanceLevel == .firm && !demo.distanceFollowUpActive)
        demo.advanceDistanceDemo()
        precondition(demo.notice?.distanceLevel == .urgent)
        demo.completeDemo()
        precondition(demo.notice?.kind == .reward && demo.adjustments == 0 && demo.rests == 0 && demo.workDuration == 0)
        precondition(!demo.cameraActive && demo.cameraSession == nil && demo.nextCheckAt == nil)
        print("PASS: confirmed near switches to 5-minute rechecks, repeated proof escalates, recovery rewards once and returns to 30 minutes; unknown frames do not count")
        print("PASS: close, quiet, pause and rest preserve pending follow-up; dismiss and stop end it; three-stage demo changes no camera, time or real rewards")
    }
}
