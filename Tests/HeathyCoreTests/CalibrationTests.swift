import Foundation
import HeathyCore

struct CalibrationTests {
    private let start = Date(timeIntervalSince1970: 100)

    func testMissingPitchDoesNotDiscardUsableDistance() {
        let sample = FrameFeatures(faceWidth: 0.2, yaw: 0, pitch: nil)
        expect(sample.isValid)
        let session = CalibrationSession()
        for frame in 0...6 { session.add(sample, at: start.addingTimeInterval(Double(frame) / 2)) }
        expect(session.reference(cameraID: "camera") != nil)
    }

    func testHeadTiltDoesNotDiscardFrontalDistance() {
        let sample = FrameFeatures(faceWidth: 0.2, yaw: 0, pitch: 0.7, faceShoulderRatio: 0.6)
        expect(sample.isValid)
        expect(!sample.supportsPosture)
        let session = CalibrationSession()
        for frame in 0...3 { session.add(sample, at: start.addingTimeInterval(Double(frame) / 2)) }
        expect(session.reference(cameraID: "camera")?.faceWidth == 0.2)
        expect(session.reference(cameraID: "camera")?.faceShoulderRatio == nil)
    }

    func testCalibrationCanUseFramesAfterSlowCameraStartup() {
        let session = CalibrationSession()
        let window = CaptureWindow(startedAt: 100)
        for frame in 0...3 {
            let uptime = 103 + Double(frame) / 2
            expect(!window.hasExpired(at: uptime))
            session.add(.valid(faceWidth: 0.2), at: Date(timeIntervalSince1970: uptime))
        }
        expect(session.reference(cameraID: "camera")?.faceWidth == 0.2)
    }

    func testCalibrationExplainsInsufficientAndUnstableSamples() {
        let insufficient = CalibrationSession()
        insufficient.add(.valid(faceWidth: 0.2), at: start)
        expect(insufficient.failureMessage.contains("有效画面不足"))
        let unstable = CalibrationSession()
        unstable.add(.valid(faceWidth: 0.2), at: start)
        unstable.add(.valid(faceWidth: 0.3), at: start.addingTimeInterval(0.5))
        expect(unstable.failureMessage.contains("人脸大小"))
    }

    func testBaselineRequiresStableSamplesAndVerification() {
        let session = CalibrationSession()
        for frame in 0..<3 { session.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(Double(frame) / 2)) }
        expect(session.reference(cameraID: "camera") == nil)
        session.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(1.5))
        expect(session.phase == .complete)
        expect(session.reference(cameraID: "camera")?.faceWidth == 0.2)
    }

    func testMovingBaselineCannotBeAccepted() {
        let session = CalibrationSession()
        for frame in 0...9 {
            session.add(.valid(faceWidth: frame % 2 == 0 ? 0.2 : 0.3), at: start.addingTimeInterval(Double(frame) / 2))
        }
        expect(session.phase == .collecting)
        expect(session.reference(cameraID: "camera") == nil)
    }

    func testLostTrackingRestartsBaseline() {
        let session = CalibrationSession()
        for frame in 0...2 { session.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(Double(frame) / 2)) }
        session.add(.unavailable, at: start.addingTimeInterval(1.5))
        session.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(2))
        expect(session.phase == .collecting)
        expect(session.progress < 0.2)
    }

    func testUnstableShouldersDoNotBecomePostureReference() {
        let session = CalibrationSession()
        for frame in 0...6 {
            session.add(FrameFeatures(faceWidth: 0.2, faceShoulderRatio: frame % 2 == 0 ? 0.3 : 0.7), at: start.addingTimeInterval(Double(frame) / 2))
        }
        expect(session.reference(cameraID: "camera")?.faceWidth == 0.2)
        expect(session.reference(cameraID: "camera")?.faceShoulderRatio == nil)
    }

    func testSingleFaceBoxJumpDoesNotDiscardStableCalibration() {
        let session = CalibrationSession()
        for (index, width) in [0.2, 0.201, 0.25, 0.199, 0.2].enumerated() {
            let posture = PostureFeatures(faceShoulderRatio: width / 0.5, headOffset: 0,
                headHeight: 0.5, shoulderTilt: 0, usesFaceCenter: true, shoulderModel: PoseNetDecoder.modelID)
            session.add(.init(faceWidth: width, posture: posture), at: start.addingTimeInterval(Double(index) / 2))
        }
        expect(session.phase == .complete)
        expect(session.reference(cameraID: "camera")?.faceWidth == 0.2)
        expect(session.reference(cameraID: "camera")?.postureReference?.isCurrentShoulderReference == true)
        expect(session.failureMessage.isEmpty)
    }

    func testLatestDistanceChangeMustNotBeDiscardedAsNoise() {
        let session = CalibrationSession()
        for (index, width) in [0.2, 0.2, 0.2, 0.3, 0.3].enumerated() {
            session.add(.valid(faceWidth: width), at: start.addingTimeInterval(Double(index) / 2))
        }
        expect(session.phase == .collecting && session.reference(cameraID: "camera") == nil)
        for index in 5...6 { session.add(.valid(faceWidth: 0.3), at: start.addingTimeInterval(Double(index) / 2)) }
        expect(session.reference(cameraID: "camera")?.faceWidth == 0.3)
    }

    func testTrackingLossDoesNotRetainAnOldMovementExplanation() {
        let session = CalibrationSession()
        session.add(.valid(faceWidth: 0.2), at: start)
        session.add(.valid(faceWidth: 0.3), at: start.addingTimeInterval(0.5))
        session.add(.unavailable, at: start.addingTimeInterval(1))
        expect(session.failureMessage.contains("跟踪中断"))
    }

    func testFifthStableFrameCanCompleteSlightlyCompressedCallbacks() {
        let session = CalibrationSession()
        for index in 0...4 {
            session.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(Double(index) * 0.49))
        }
        expect(session.phase == .complete)
        expect(session.reference(cameraID: "camera")?.faceWidth == 0.2)
    }
}
