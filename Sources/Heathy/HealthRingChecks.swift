import Foundation
import HeathyCore

@MainActor
enum HealthRingChecks {
    static func run() {
        let suite = "local.qingxing.health-ring-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        defer { state.shutdown() }
        let start = Date()
        state.breakMinutes = 1
        state.beginRest(at: start)
        state.tick(at: start.addingTimeInterval(59))
        precondition(state.rests == 0, "An unfinished rest must not earn a completion")
        state.tick(at: start.addingTimeInterval(60))
        precondition(state.rests == 1, "Rest must complete automatically at its target duration")
        precondition(state.isResting, "Completion must wait for the user to resume work")
        precondition(state.restCompleted && state.healthEnergy == 1 && state.restProgress == 1)
        precondition(state.buddyHeadline.contains("满血") && state.buddyExpression == .happy)
        precondition(state.notice?.rewardKind == .rest && state.notice?.autoDismissDelay == 8)
        state.tick(at: start.addingTimeInterval(61))
        precondition(state.rests == 1, "A completed rest cannot earn twice")
        let completedID = state.notice!.id
        state.expireNotice(id: completedID)
        state.tick(at: start.addingTimeInterval(90))
        precondition(state.notice == nil && state.isResting && state.restCompleted && state.healthEnergy == 1)
        state.finishRest(at: start.addingTimeInterval(91))
        state.finishRest(at: start.addingTimeInterval(92))
        precondition(!state.isResting && state.rests == 1 && state.workDuration == 0 && state.healthEnergy == 1)
        precondition(!state.cameraActive && state.cameraSession == nil)
        checkChargingAndCancellation()
        checkQuietAndSuspension()
        checkAdjustmentFeedback()
        print("PASS: automatic rest completion once; full ring survives card dismissal until explicit resume; no camera access")
    }

    private static func checkChargingAndCancellation() {
        let suite = "local.qingxing.health-charge.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        defer { state.shutdown() }
        let start = Date()
        state.workMinutes = 15
        state.breakMinutes = 1
        state.toggleManualTimer()
        for second in 0...450 { state.tick(at: start.addingTimeInterval(Double(second))) }
        precondition(state.workDuration == 450 && state.healthEnergy == 0.5)
        let restStart = start.addingTimeInterval(450)
        state.beginRest(at: restStart)
        precondition(state.healthEnergy == 0.5)
        state.beginRest(at: restStart.addingTimeInterval(20))
        state.tick(at: restStart.addingTimeInterval(30))
        precondition(state.restRemaining == 30 && state.restProgress == 0.5 && state.healthEnergy == 0.75)
        state.finishRest(at: restStart.addingTimeInterval(30))
        precondition(state.isResting && !state.restCompleted && state.rests == 0)
        state.cancelRest(at: restStart.addingTimeInterval(30))
        precondition(!state.isResting && state.rests == 0 && state.healthEnergy == 0.5 && state.workDuration == 450)
        let again = restStart.addingTimeInterval(31)
        state.beginRest(at: again)
        state.breakMinutes = 10
        state.tick(at: again.addingTimeInterval(60))
        precondition(state.restCompleted && state.activeRestMinutes == 1 && state.rests == 1 && state.healthEnergy == 1)
        state.finishRest(at: again.addingTimeInterval(61))
        state.beginRest(at: again.addingTimeInterval(62))
        precondition(state.activeRestMinutes == 10 && state.restRemaining == 600 && !state.restCompleted)
        state.clearLocalData()
        precondition(state.rests == 0 && state.workDuration == 0 && !state.isResting && !state.restCompleted && state.healthEnergy == 1)
        print("PASS: charging never drops on entry; early return preserves work; duration is fixed per rest; clear resets ring")
    }

    private static func checkQuietAndSuspension() {
        let suite = "local.qingxing.health-suspension.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = AppState(defaults: defaults)
        defer { state.shutdown() }
        let start = Date()
        state.quiet = true
        state.breakMinutes = 1
        state.beginRest(at: start)
        state.tick(at: start.addingTimeInterval(60))
        precondition(state.restCompleted && state.rests == 1 && state.notice == nil)
        state.finishRest(at: start.addingTimeInterval(61))
        state.quiet = false
        state.beginRest(at: start.addingTimeInterval(62))
        state.suspendForSystem(.screenLock)
        state.tick(at: start.addingTimeInterval(122))
        precondition(!state.restCompleted && state.rests == 1 && state.notice == nil)
        state.resumeFromSystem(.screenLock)
        state.tick(at: start.addingTimeInterval(123))
        precondition(state.restCompleted && state.rests == 2 && state.isResting && state.nextCheckAt == nil)
        state.finishRest(at: start.addingTimeInterval(124))
        // Replay the asynchronous stop callback; no capture session is created.
        state.detector.onStatus?(.off)
        state.tryRestDemo()
        state.completeDemo()
        precondition(state.notice?.rewardKind == .rest && state.notice?.isDemo == true)
        precondition(state.rests == 2 && !state.isResting && !state.restCompleted && state.workDuration == 0)
        precondition(!state.cameraActive && state.cameraSession == nil)
        print("PASS: quiet rest updates without popup; locked rest completes after unlock; demo changes no real progress")
    }

    private static func checkAdjustmentFeedback() {
        let suite = "local.qingxing.health-adjustment.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let reference = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "offline:640x480", referenceDistanceCM: 60)
        defaults.set(try! JSONEncoder().encode(reference), forKey: "qx.calibration")
        defaults.set("offline", forKey: "qx.camera")
        defaults.set(true, forKey: "qx.checksStarted")
        let engine = ReminderEngine()
        let start = Date()
        var observedAt = start
        let state = AppState(defaults: defaults, engine: engine, observationTime: { observedAt })
        defer { state.shutdown() }
        state.restoreAutomaticChecks(cameraAuthorized: true)
        engine.calibration = reference
        func scan(_ width: Double, at offset: TimeInterval) {
            state.prepareObservationWindow()
            state.detector.onStatus?(.running)
            for i in 0..<4 {
                observedAt = start.addingTimeInterval(offset + Double(i) * 0.5)
                state.detector.onSample?(.valid(faceWidth: width), reference.cameraID, "", nil)
            }
            state.detector.onStatus?(.off)
            state.detector.onWindowEnded?()
        }
        let energy = state.healthEnergy
        var lastReward: UUID?
        for episode in 1...3 {
            scan(0.25, at: Double(episode * 30))
            precondition(state.notice?.kind == .distance)
            scan(0.2, at: Double(episode * 30 + 10))
            precondition(state.adjustments == episode && state.notice?.rewardKind == .adjustment)
            precondition(state.notice?.message.contains("\(episode) 次") == true && state.notice?.autoDismissDelay == 8)
            precondition(lastReward != state.notice?.id)
            lastReward = state.notice?.id
            scan(0.2, at: Double(episode * 30 + 20))
            precondition(state.adjustments == episode, "Repeated safe frames cannot earn twice")
        }
        precondition(state.healthEnergy == energy && state.rests == 0 && !state.cameraActive && state.cameraSession == nil)
        print("PASS: three real recovery episodes each produce a distinct +1 reward and cumulative count; rest budget unchanged")
    }
}
