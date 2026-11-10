import Foundation
import HeathyCore

struct ReminderEngineTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testMissingOrientationDoesNotMakePostureClaims() {
        let engine = engine()
        engine.postureEnabled = true
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: 0.5, cameraID: "test")
        let sample = FrameFeatures(faceWidth: 0.21, yaw: 0, pitch: nil, faceShoulderRatio: 0.7)
        for second in 0...4 { expect(engine.observe(sample, at: start.addingTimeInterval(Double(second))).isEmpty) }
    }

    func testDisablingPostureDoesNotBlockDistanceReminders() {
        let engine = engine()
        engine.postureEnabled = true
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: 0.5, cameraID: "test")
        let shifted = FrameFeatures(faceWidth: 0.21, faceShoulderRatio: 0.65)
        for second in 0..<3 { _ = engine.observe(shifted, at: start.addingTimeInterval(Double(second))) }
        expect(engine.observe(shifted, at: start.addingTimeInterval(3)) == [.reminder(.posture)])
        engine.postureEnabled = false
        expect(engine.activeKind == nil)
        for second in 10..<13 { _ = engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(Double(second))) }
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(13)) == [.reminder(.distance)])
    }

    private func engine() -> ReminderEngine {
        let engine = ReminderEngine()
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "test")
        return engine
    }

    private func trigger(_ engine: ReminderEngine, offset: TimeInterval = 0) {
        for second in 0..<3 {
            _ = engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(offset + Double(second)))
        }
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(offset + 3)) == [.reminder(.distance)])
    }

    func testProximityMustPersistBeforeReminder() {
        let engine = engine()
        expect(engine.observe(.valid(faceWidth: 0.27), at: start).isEmpty)
        for second in 1..<3 {
            expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(Double(second))).isEmpty)
        }
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(3)) == [.reminder(.distance)])
    }

    func testLostTrackingBreaksContinuousEvidence() {
        let engine = engine()
        _ = engine.observe(.valid(faceWidth: 0.27), at: start)
        _ = engine.observe(.unavailable, at: start.addingTimeInterval(9))
        for second in 10..<13 {
            expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(Double(second))).isEmpty)
        }
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(13)) == [.reminder(.distance)])
    }

    func testLongSampleGapCannotTriggerReminder() {
        let engine = engine()
        _ = engine.observe(.valid(faceWidth: 0.27), at: start)
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(60)).isEmpty)
    }

    func testRecoveryRewardsOnceAfterThreeSeconds() {
        let engine = engine()
        trigger(engine)
        expect(engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(11)).isEmpty)
        expect(engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(14)) == [.adjusted])
        expect(engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(15)).isEmpty)
    }

    func testDismissedFalseAlarmDoesNotReward() {
        let engine = engine()
        trigger(engine)
        engine.dismiss()
        _ = engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(11))
        expect(engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(14)).isEmpty)
    }

    func testCooldownAfterRecovery() {
        let engine = engine()
        trigger(engine)
        _ = engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(11))
        _ = engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(14))
        _ = engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(20))
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(30)).isEmpty)
    }

    func testPauseCancelsPendingEvidenceAndRewards() {
        let engine = engine()
        trigger(engine)
        engine.suspend()
        _ = engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(11))
        expect(engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(14)).isEmpty)
    }

    func testRestRequiresElapsedTimeAndConfirmation() {
        let engine = engine()
        engine.restDuration = 120
        engine.beginRest(at: start)
        expect(engine.finishRest(at: start.addingTimeInterval(119)).isEmpty)
        expect(engine.finishRest(at: start.addingTimeInterval(120)) == [.rested])
        expect(engine.finishRest(at: start.addingTimeInterval(121)).isEmpty)
    }

    func testTimerDoesNotCountPausedOrLongSuspension() {
        let engine = engine()
        engine.restInterval = 45 * 60
        _ = engine.tick(at: start, working: true)
        _ = engine.tick(at: start.addingTimeInterval(1), working: true)
        expect(engine.workDuration == 1)
        _ = engine.tick(at: start.addingTimeInterval(2), working: false)
        _ = engine.tick(at: start.addingTimeInterval(100), working: true)
        expect(engine.workDuration == 1)
    }

    func testRestReminderOnlyFiresOnceUntilSnoozed() {
        let engine = engine()
        engine.restInterval = 2
        _ = engine.tick(at: start, working: true)
        expect(engine.tick(at: start.addingTimeInterval(1), working: true).isEmpty)
        expect(engine.tick(at: start.addingTimeInterval(2), working: true) == [.reminder(.rest)])
        expect(engine.tick(at: start.addingTimeInterval(3), working: true).isEmpty)
    }

    func testInvalidYawIsNotMisclassifiedAsProximity() {
        let engine = engine()
        let side = FrameFeatures(faceWidth: 0.3, yaw: 1, pitch: 0, faceShoulderRatio: nil)
        _ = engine.observe(side, at: start)
        expect(engine.observe(side, at: start.addingTimeInterval(10)).isEmpty)
    }

    func testSnoozeCanRemindAgainForSameProblem() {
        let engine = engine()
        trigger(engine)
        engine.snooze(at: start.addingTimeInterval(11))
        for second in 12..<314 {
            expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(Double(second))).isEmpty)
        }
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(314)) == [.reminder(.distance)])
    }

    func testPostureInferenceIsOptIn() {
        let engine = engine()
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: 0.5, cameraID: "test")
        let sample = FrameFeatures(faceWidth: 0.21, faceShoulderRatio: 0.65)
        for second in 0...30 {
            expect(engine.observe(sample, at: start.addingTimeInterval(Double(second))).isEmpty)
        }
    }

    func testMissingShouldersCannotEarnPostureReward() {
        let engine = engine()
        engine.postureEnabled = true
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: 0.5, cameraID: "test")
        let shifted = FrameFeatures(faceWidth: 0.21, faceShoulderRatio: 0.65)
        for second in 0..<3 { _ = engine.observe(shifted, at: start.addingTimeInterval(Double(second))) }
        expect(engine.observe(shifted, at: start.addingTimeInterval(3)) == [.reminder(.posture)])
        expect(!engine.isRecovering(shifted))
        for second in 4...8 {
            expect(!engine.isRecovering(.valid(faceWidth: 0.2)))
            expect(engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(Double(second))).isEmpty)
        }
    }
}
