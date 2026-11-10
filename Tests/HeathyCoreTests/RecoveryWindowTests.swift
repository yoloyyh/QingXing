import Foundation
import HeathyCore

struct RecoveryWindowTests {
    private let start = Date(timeIntervalSince1970: 100)
    private func pendingDistance() -> ReminderEngine {
        let engine = ReminderEngine()
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "test")
        for second in 0...3 { _ = engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(Double(second))) }
        engine.endObservationWindow()
        return engine
    }
    func testLateStableTailCanConfirmAtWindowEndOnlyOnce() {
        let engine = pendingDistance()
        for offset in [302.8, 303.3, 303.8, 304.3] {
            expect(engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(offset)).isEmpty)
        }
        expect(engine.completeObservationWindow() == [.adjusted])
        expect(engine.activeKind == nil && engine.distanceReminderLevel == .none)
        expect(engine.completeObservationWindow().isEmpty)
    }
    func testNewProximityAfterRecoveryIsNotMutedByOldCooldown() {
        for shortWindow in [false, true] {
            let engine = pendingDistance()
            let count = shortWindow ? 4 : 7
            for index in 0..<count { _ = engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(10 + Double(index)*0.5)) }
            _ = engine.completeObservationWindow()
            expect(engine.activeKind == nil)
            for index in 0..<6 { expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(20 + Double(index)*0.5)).isEmpty) }
            expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(23)) == [.reminder(.distance)])
            expect(engine.distanceReminderLevel == .gentle)
        }
    }

    func testUnknownOrNearFinalFrameCannotConfirmRecovery() {
        for last in [FrameFeatures.unavailable, .valid(faceWidth: 0.27)] {
            let engine = pendingDistance()
            for offset in [302.5, 303, 303.5, 304] { _ = engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(offset)) }
            _ = engine.observe(last, at: start.addingTimeInterval(304.5))
            expect(engine.completeObservationWindow().isEmpty)
            expect(engine.activeKind == .distance)
        }
    }
    func testShortSeparateScansAndCancellationCannotEarnReward() {
        let engine = pendingDistance()
        for round in 0..<3 {
            for index in 0..<3 { _ = engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(300 + Double(round)*300 + Double(index)*0.5)) }
            expect(engine.completeObservationWindow().isEmpty)
        }
        for index in 0..<4 { _ = engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(1200 + Double(index)*0.5)) }
        engine.endObservationWindow() // cancelled, not a completed capture
        expect(engine.completeObservationWindow().isEmpty)
        expect(engine.activeKind == .distance)
    }
}
