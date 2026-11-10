import Foundation
import HeathyCore

struct ProximityWindowTests {
    private let start = Date(timeIntervalSince1970: 100)
    private func engine() -> ReminderEngine {
        let e = ReminderEngine()
        e.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "test", referenceDistanceCM: 60)
        return e
    }
    func testLateStableProximityTriggersAtCaptureEnd() {
        let e = engine()
        for offset in [2.8,3.3,3.8,4.3] { expect(e.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(offset)).isEmpty) }
        expect(e.completeObservationWindow() == [.reminder(.distance)])
        expect(e.distanceReminderLevel == .gentle)
        expect(e.completeObservationWindow().isEmpty)
        for offset in [302.8,303.3,303.8,304.3] { _ = e.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(offset)) }
        expect(e.completeObservationWindow() == [.reminder(.distance)])
        expect(e.distanceReminderLevel == .firm)
    }
    func testUnknownSafeFrameAndTooFewSamplesCannotTriggerProximity() {
        for last in [FrameFeatures.unavailable, .valid(faceWidth: 0.2)] {
            let e = engine()
            for offset in [2.5,3,3.5,4] { _ = e.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(offset)) }
            _ = e.observe(last, at: start.addingTimeInterval(4.5))
            expect(e.completeObservationWindow().isEmpty)
            expect(e.activeKind == nil)
        }
        let e = engine()
        for round in 0..<3 {
            for index in 0..<3 { _ = e.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(Double(round)*300+Double(index)*0.5)) }
            expect(e.completeObservationWindow().isEmpty)
        }
    }
    func testCancellationAndAlreadyIssuedAlertCannotDuplicate() {
        let e = engine()
        for index in 0..<4 { _ = e.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(Double(index)*0.5)) }
        e.endObservationWindow()
        expect(e.completeObservationWindow().isEmpty)
        for index in 0..<6 { expect(e.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(10+Double(index)*0.5)).isEmpty) }
        expect(e.observe(.valid(faceWidth: 0.25), at: start.addingTimeInterval(13)) == [.reminder(.distance)])
        expect(e.completeObservationWindow().isEmpty)
        expect(e.distanceReminderLevel == .gentle)
    }
}
