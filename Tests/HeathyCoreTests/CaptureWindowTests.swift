import Foundation
import HeathyCore

struct CaptureWindowTests {
    func testCaptureEndsAtFiveSeconds() {
        let window = CaptureWindow(startedAt: 100)
        expect(window.remaining(at: 100) == 5)
        expect(window.remaining(at: 104) == 1)
        expect(!window.hasExpired(at: 104.999))
        expect(window.hasExpired(at: 105))
        expect(window.remaining(at: 105) == 0)
        expect(window.remaining(at: 110) == 0)
    }

    func testShortScanCanDetectAndRecheckAnAdjustment() {
        let engine = ReminderEngine()
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "test")
        let start = Date(timeIntervalSince1970: 100)
        for second in 0..<3 { expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(Double(second))).isEmpty) }
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(3)) == [.reminder(.distance)])
        engine.endObservationWindow()
        let recheck = start.addingTimeInterval(300)
        expect(engine.observe(.valid(faceWidth: 0.2), at: recheck).isEmpty)
        expect(engine.observe(.valid(faceWidth: 0.2), at: recheck.addingTimeInterval(3)) == [.adjusted])
        expect(engine.observe(.valid(faceWidth: 0.2), at: recheck.addingTimeInterval(4)).isEmpty)
    }

    func testSeparateScansCannotCombineIncompleteEvidence() {
        let engine = ReminderEngine()
        engine.calibration = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "test")
        let start = Date(timeIntervalSince1970: 100)
        _ = engine.observe(.valid(faceWidth: 0.27), at: start)
        _ = engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(1))
        engine.endObservationWindow()
        for second in 0..<3 {
            expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(300 + Double(second))).isEmpty)
        }
        expect(engine.observe(.valid(faceWidth: 0.27), at: start.addingTimeInterval(303)) == [.reminder(.distance)])
    }
}
