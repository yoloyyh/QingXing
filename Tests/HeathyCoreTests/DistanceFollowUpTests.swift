import Foundation
import HeathyCore

struct DistanceFollowUpTests {
    private let start = Date(timeIntervalSince1970: 12_000)
    private func engine() -> ReminderEngine {
        let value = ReminderEngine()
        value.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "offline", referenceDistanceCM: 60)
        return value
    }
    private func scan(_ engine: ReminderEngine, at offset: TimeInterval, sample: FrameFeatures = .valid(faceWidth: 0.25)) -> [ReminderEvent] {
        var events: [ReminderEvent] = []
        for index in 0...9 { events += engine.observe(sample, at: start.addingTimeInterval(offset + Double(index) * 0.5)) }
        engine.endObservationWindow()
        return events
    }
    func testDistanceEscalatesOncePerRecheckAndCapsAtUrgent() {
        let value = engine()
        expect(scan(value, at: 0) == [.reminder(.distance)])
        expect(value.distanceReminderLevel == .gentle && value.nextCheckInterval == 300)
        expect(scan(value, at: 305) == [.reminder(.distance)])
        expect(value.distanceReminderLevel == .firm)
        expect(scan(value, at: 610) == [.reminder(.distance)])
        expect(value.distanceReminderLevel == .urgent)
        expect(scan(value, at: 915) == [.reminder(.distance)])
        expect(value.distanceReminderLevel == .urgent)
    }
    func testConfirmedRecoveryEndsFollowUpAndRewardsOnlyOnce() {
        let value = engine()
        _ = scan(value, at: 0)
        expect(scan(value, at: 305, sample: .valid(faceWidth: 0.2)) == [.adjusted])
        expect(value.distanceReminderLevel == .none && value.nextCheckInterval == 1_800)
        expect(scan(value, at: 610, sample: .valid(faceWidth: 0.2)).isEmpty)
    }
    func testUnknownAndDistanceBufferDoNotEscalateOrRecover() {
        let value = engine()
        _ = scan(value, at: 0)
        expect(scan(value, at: 305, sample: .unavailable).isEmpty)
        expect(value.distanceReminderLevel == .gentle && value.nextCheckInterval == 300)
        expect(scan(value, at: 610, sample: .valid(faceWidth: 0.2 * 60 / 56)).isEmpty)
        expect(value.distanceReminderLevel == .gentle && value.activeKind == .distance)
    }
    func testSeparateShortRechecksCannotCombineEvidenceForEscalation() {
        let value = engine()
        _ = scan(value, at: 0)
        for offset: TimeInterval in [305, 610] {
            for second in 0...2 { expect(value.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(offset + Double(second))).isEmpty) }
            value.endObservationWindow()
        }
        expect(value.distanceReminderLevel == .gentle)
        expect(scan(value, at: 915) == [.reminder(.distance)])
        expect(value.distanceReminderLevel == .firm)
    }
    func testPauseAndRestPreservePendingDistanceWithoutGrantingAdjustment() {
        let value = engine()
        _ = scan(value, at: 0)
        value.suspend(preservingDistanceFollowUp: true)
        expect(value.activeKind == .distance && value.distanceReminderLevel == .gentle)
        value.beginRest(at: start.addingTimeInterval(10))
        expect(value.finishRest(at: start.addingTimeInterval(310)) == [.rested])
        expect(value.distanceReminderLevel == .gentle && value.nextCheckInterval == 300)
        expect(scan(value, at: 315) == [.reminder(.distance)])
        expect(value.distanceReminderLevel == .firm)
    }
    func testStoppingAndDismissingCancelTheDistanceFollowUp() {
        for dismiss in [false, true] {
            let value = engine()
            _ = scan(value, at: 0)
            if dismiss { value.dismiss() } else { value.suspend() }
            expect(value.activeKind == nil && value.distanceReminderLevel == .none && value.nextCheckInterval == 1_800)
            expect(scan(value, at: 305, sample: .valid(faceWidth: 0.2)).isEmpty)
        }
    }
    func testManualEarlyRecheckUsesItsOwnStableEvidence() {
        let value = engine()
        _ = scan(value, at: 0)
        expect(scan(value, at: 10) == [.reminder(.distance)])
        expect(value.distanceReminderLevel == .firm)
        expect(scan(value, at: 20, sample: .valid(faceWidth: 0.2)) == [.adjusted])
    }
    func testConfirmedDistanceCanSupersedeAnActivePostureReminder() {
        let value = engine()
        value.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "offline", referenceDistanceCM: 60, headReference: HeadPoseFeatures(pitch: 0))
        value.postureEnabled = true
        expect(scan(value, at: 0, sample: FrameFeatures(faceWidth: 0.2, headPose: HeadPoseFeatures(pitch: 0.4))) == [.reminder(.posture)])
        expect(scan(value, at: 305) == [.reminder(.distance)])
        expect(value.activeKind == .distance && value.distanceReminderLevel == .gentle)
    }
}
