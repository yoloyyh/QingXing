import Foundation
import HeathyCore

struct PostureTests {
    private let start = Date(timeIntervalSince1970: 1_000)
    private func pose(ratio: Double = 0.4, offset: Double = 0, height: Double = 0.55, tilt: Double = 0, pitch: Double? = 0) -> PostureFeatures {
        .init(faceShoulderRatio: ratio, headOffset: offset, headHeight: height, shoulderTilt: tilt, pitch: pitch)
    }
    private func frame(_ posture: PostureFeatures) -> FrameFeatures {
        .init(faceWidth: 0.2, pitch: posture.pitch, faceShoulderRatio: posture.faceShoulderRatio, posture: posture)
    }
    private func reference(_ posture: PostureFeatures? = nil) -> Calibration {
        let posture = posture ?? pose()
        return Calibration(faceWidth: 0.2, faceShoulderRatio: posture.faceShoulderRatio, cameraID: "test", referenceDistanceCM: 60, postureReference: posture)
    }

    func testPostureGeometryIgnoresWholeBodyScalingAndTranslation() {
        let base = PostureFeatures.measure(faceWidth: 0.16, aspectRatio: 4.0 / 3, nose: .init(x: 0.5, y: 0.7), left: .init(x: 0.3, y: 0.4), right: .init(x: 0.7, y: 0.4), pitch: nil)
        let moved = PostureFeatures.measure(faceWidth: 0.192, aspectRatio: 4.0 / 3, nose: .init(x: 0.55, y: 0.74), left: .init(x: 0.31, y: 0.38), right: .init(x: 0.79, y: 0.38), pitch: nil)
        expect(base != nil && moved != nil)
        if let base, let moved {
            expect(abs(base.faceShoulderRatio - moved.faceShoulderRatio) < 0.0001)
            expect(abs(base.headOffset - moved.headOffset) < 0.0001)
            expect(abs(base.headHeight - moved.headHeight) < 0.0001)
            expect(abs(base.headHeight - 0.5625) < 0.0001)
        }
    }

    func testUncertainOrCroppedShouldersCannotBecomePosture() {
        expect(PostureFeatures.measure(faceWidth: 0.16, aspectRatio: 4.0 / 3, nose: .init(x: 0.5, y: 0.7), left: .init(x: 0.3, y: 0.4, confidence: 0.1), right: .init(x: 0.7, y: 0.4), pitch: nil) == nil)
        expect(PostureFeatures.measure(faceWidth: 0.16, aspectRatio: 4.0 / 3, nose: .init(x: 0.5, y: 0.7), left: .init(x: 0, y: 0.4), right: .init(x: 0.7, y: 0.4), pitch: nil) == nil)
        expect(!pose(offset: .nan).isValid)
    }

    func testHeadAndShoulderChangesCompareWithFixedReference() {
        expect(PostureAssessment.evaluate(frame(pose()), reference: reference()) == .aligned)
        expect(PostureAssessment.evaluate(frame(pose(ratio: 0.5)), reference: reference()) == .changed(.forward))
        expect(PostureAssessment.evaluate(frame(pose(offset: 0.18)), reference: reference()) == .changed(.headPosition))
        expect(PostureAssessment.evaluate(frame(pose(height: 0.35)), reference: reference()) == .changed(.headPosition))
        expect(PostureAssessment.evaluate(frame(pose(tilt: 0.25)), reference: reference()) == .changed(.shoulders))
        expect(PostureAssessment.evaluate(frame(pose(pitch: 0.3)), reference: reference()) == .changed(.headAngle))
    }

    func testMissingPitchStillAllowsVisibleHeadShoulderGeometry() {
        let sample = frame(pose(offset: 0.18, pitch: nil))
        expect(sample.isValid && sample.supportsPosture)
        expect(PostureAssessment.evaluate(sample, reference: reference(pose(pitch: nil))) == .changed(.headPosition))
        expect(PostureAssessment.evaluate(.valid(faceWidth: 0.2), reference: reference()) == .unavailable)
    }

    func testPostureCanCalibrateAfterDistanceCompletes() {
        let session = CalibrationSession()
        for index in 0...3 { session.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(Double(index) / 2)) }
        expect(session.phase == .complete)
        expect(session.reference(cameraID: "test")?.postureReference == nil)
        for index in 4...7 { session.add(frame(pose()), at: start.addingTimeInterval(Double(index) / 2)) }
        expect(session.reference(cameraID: "test")?.postureReference == pose())
        expect(session.reference(cameraID: "test")?.faceWidth == 0.2)
    }

    func testLatePostureCannotUseADifferentDistancePosition() {
        let session = CalibrationSession()
        for index in 0...3 { session.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(Double(index) / 2)) }
        let moved = FrameFeatures(faceWidth: 0.27, posture: pose())
        for index in 4...7 { session.add(moved, at: start.addingTimeInterval(Double(index) / 2)) }
        expect(session.reference(cameraID: "test")?.faceWidth == 0.2)
        expect(session.reference(cameraID: "test")?.postureReference == nil)
    }

    func testPostureTrackingLossBreaksEvidenceAndRecoveryRewardsOnce() {
        let engine = ReminderEngine()
        engine.calibration = reference()
        engine.postureEnabled = true
        for second in 0...1 { expect(engine.observe(frame(pose(offset: 0.18)), at: start.addingTimeInterval(Double(second))).isEmpty) }
        expect(engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(2)).isEmpty)
        for second in 3..<6 { expect(engine.observe(frame(pose(offset: 0.18)), at: start.addingTimeInterval(Double(second))).isEmpty) }
        expect(engine.observe(frame(pose(offset: 0.18)), at: start.addingTimeInterval(6)) == [.reminder(.posture)])
        expect(engine.observe(.valid(faceWidth: 0.2), at: start.addingTimeInterval(7)).isEmpty)
        for second in 8..<11 { expect(engine.observe(frame(pose()), at: start.addingTimeInterval(Double(second))).isEmpty) }
        expect(engine.observe(frame(pose()), at: start.addingTimeInterval(11)) == [.adjusted])
        expect(engine.observe(frame(pose()), at: start.addingTimeInterval(12)).isEmpty)
    }

    func testAbsentPostureReferenceIsNotReportedAsHealthy() {
        let old = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "test")
        expect(PostureAssessment.evaluate(frame(pose()), reference: old) == .needsCalibration)
        expect(!PostureAssessment.isRecovered(.valid(faceWidth: 0.2), reference: reference()))
    }

    func testPostureSummarySurvivesTheFinalMissedShoulders() {
        var scan = ScanObservation()
        let valid = frame(pose())
        scan.add(valid, message: "")
        scan.add(.valid(faceWidth: 0.2), message: "", postureMessage: "双肩未入镜")
        expect(scan.lastPostureSample == valid)
        expect(scan.postureFailureMessage == nil)
        var next = ScanObservation()
        next.add(.valid(faceWidth: 0.2), message: "", postureMessage: "双肩未入镜")
        expect(next.lastValidSample != nil && next.lastPostureSample == nil)
        expect(next.postureFailureMessage == "双肩未入镜")
    }

    func testRecognizedFaceAndShouldersDoNotNeedABodyNose() {
        let detected = PostureFeatures.measureFromFace(faceCenter: .init(x: 0.5, y: 0.75), faceWidth: 0.16,
            aspectRatio: 4.0 / 3, left: .init(x: 0.3, y: 0.4), right: .init(x: 0.7, y: 0.4), pitch: nil)
        expect(detected?.isValid == true && detected?.usesFaceCenter == true)
        if let detected {
            let session = CalibrationSession()
            for index in 0...3 { session.add(frame(detected), at: start.addingTimeInterval(Double(index) / 2)) }
            expect(session.reference(cameraID: "test")?.postureReference?.usesFaceCenter == true)
            expect(PostureAssessment.evaluate(frame(pose()), reference: reference(detected)) == .needsCalibration)
            expect(!PostureAssessment.isRecovered(frame(pose()), reference: reference(detected)))
        }
    }

    func testPostureCalibrationDistinguishesMissingFromInsufficientSamples() {
        let session = CalibrationSession()
        session.add(frame(pose()), at: start)
        session.add(frame(pose()), at: start.addingTimeInterval(0.5))
        expect(session.postureFailureMessage?.contains("2/4") == true)
        let noBody = CalibrationSession()
        for index in 0...3 { noBody.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(Double(index) / 2)) }
        expect(noBody.postureFailureMessage == nil)
    }
}
