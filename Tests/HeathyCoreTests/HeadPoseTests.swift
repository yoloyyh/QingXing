import Foundation
import HeathyCore

struct HeadPoseTests {
    private let start = Date(timeIntervalSince1970: 2_000)
    private func body(ratio: Double = 0.4) -> PostureFeatures {
        .init(faceShoulderRatio: ratio, headOffset: 0, headHeight: 0.5, shoulderTilt: 0,
              pitch: 0.1, usesFaceCenter: true, shoulderModel: PoseNetDecoder.modelID)
    }
    private func reference(shoulders: Bool = false) -> Calibration {
        .init(faceWidth: 0.2, faceShoulderRatio: shoulders ? 0.4 : nil, cameraID: "camera",
              referenceDistanceCM: 60, postureReference: shoulders ? body() : nil,
              headReference: .init(pitch: 0.1, roll: 0))
    }
    private func frame(pitch: Double? = 0.1, roll: Double? = 0, width: Double = 0.2, body: PostureFeatures? = nil) -> FrameFeatures {
        .init(faceWidth: width, pitch: pitch, posture: body, headPose: pitch.map { .init(pitch: $0, roll: roll) })
    }

    func testHeadDownAndTiltUseThePersonalReferenceWithoutShoulders() {
        expect(HeadPoseAssessment.evaluate(frame(pitch: 0.4), reference: reference()) == .lowered)
        expect(PostureAssessment.evaluate(frame(pitch: 0.4), reference: reference()) == .changed(.headDown))
        expect(HeadPoseAssessment.evaluate(frame(pitch: -0.3), reference: reference()) == .aligned)
        expect(PostureAssessment.evaluate(frame(roll: 0.3), reference: reference()) == .changed(.headTilt))
        expect(HeadPoseAssessment.evaluate(frame(pitch: 0.18, roll: 0.05), reference: reference()) == .aligned)
    }

    func testLeaningBackWithoutShouldersDoesNotBecomeForwardHeadPosture() {
        let reclined = frame(width: 0.13)
        expect(!reference().isTooClose(reclined))
        expect(PostureAssessment.evaluate(reclined, reference: reference()) == .aligned)
        let reclinedBody = PostureFeatures(faceShoulderRatio: 0.4, headOffset: 0, headHeight: 0.5,
            shoulderTilt: 0, pitch: -0.3, usesFaceCenter: true, shoulderModel: PoseNetDecoder.modelID)
        let lookingUp = frame(pitch: -0.3, body: reclinedBody)
        expect(PostureAssessment.evaluate(lookingUp, reference: reference(shoulders: true)) == .aligned)
        expect(PostureAssessment.isRecovered(lookingUp, reference: reference(shoulders: true), for: .forward))
    }

    func testMissingHeadAnglesAreUnknownAndCannotRecover() {
        let missing = frame(pitch: nil)
        expect(!missing.supportsHeadPose)
        expect(PostureAssessment.evaluate(missing, reference: reference()) == .unavailable)
        expect(!HeadPoseAssessment.isRecovered(missing, reference: reference()))
        expect(!HeadPoseAssessment.isRecovered(frame(roll: nil), reference: reference()))
        expect(HeadPoseAssessment.evaluate(frame(pitch: 0.4, roll: nil), reference: reference()) == .lowered)
        expect(!HeadPoseFeatures(pitch: .nan).isValid)
    }

    func testHeadReferenceCalibratesWithoutAnyShoulderResults() {
        let session = CalibrationSession()
        for index in 0...3 { session.add(frame(), at: start.addingTimeInterval(Double(index) / 2)) }
        expect(session.reference(cameraID: "camera")?.headReference == .init(pitch: 0.1, roll: 0))
        expect(session.reference(cameraID: "camera")?.postureReference == nil)
        expect(session.headProgress == 1)
    }

    func testHeadReferenceCanCompleteAfterDistanceWithinTheSameScan() {
        let session = CalibrationSession()
        for index in 0...3 { session.add(frame(pitch: nil), at: start.addingTimeInterval(Double(index) / 2)) }
        expect(session.phase == .complete && session.headReference == nil)
        for index in 4...7 { session.add(frame(), at: start.addingTimeInterval(Double(index) / 2)) }
        expect(session.reference(cameraID: "camera")?.headReference != nil)
    }

    func testMovingHeadDoesNotBecomeTheReference() {
        let session = CalibrationSession()
        for index in 0...8 { session.add(frame(pitch: index % 2 == 0 ? 0.1 : 0.5), at: start.addingTimeInterval(Double(index) / 2)) }
        expect(session.phase == .complete && session.headReference == nil)
    }

    func testHeadReminderAndRecoveryWorkWithoutShouldersAndRewardOnce() {
        let engine = ReminderEngine()
        engine.calibration = reference(shoulders: true)
        engine.postureEnabled = true
        for second in 0..<3 { expect(engine.observe(frame(pitch: 0.4), at: start.addingTimeInterval(Double(second))).isEmpty) }
        expect(engine.observe(frame(pitch: 0.4), at: start.addingTimeInterval(3)) == [.reminder(.posture)])
        expect(engine.activePostureChange == .headDown)
        for second in 4...7 { expect(engine.observe(frame(pitch: nil), at: start.addingTimeInterval(Double(second))).isEmpty) }
        for second in 8..<11 { expect(engine.observe(frame(), at: start.addingTimeInterval(Double(second))).isEmpty) }
        expect(engine.observe(frame(), at: start.addingTimeInterval(11)) == [.adjusted])
        expect(engine.observe(frame(), at: start.addingTimeInterval(12)).isEmpty)
    }

    func testShoulderReminderCannotRecoverJustBecauseShouldersDisappear() {
        let engine = ReminderEngine()
        engine.calibration = reference(shoulders: true)
        engine.postureEnabled = true
        for second in 0..<3 { _ = engine.observe(frame(body: body(ratio: 0.55)), at: start.addingTimeInterval(Double(second))) }
        expect(engine.observe(frame(body: body(ratio: 0.55)), at: start.addingTimeInterval(3)) == [.reminder(.posture)])
        expect(engine.activePostureChange == .forward)
        for second in 4...8 { expect(engine.observe(frame(), at: start.addingTimeInterval(Double(second))).isEmpty) }
    }

    func testHeadScanResultSurvivesTheFinalMissedAngles() {
        var scan = ScanObservation()
        scan.add(frame(), message: "", postureMessage: "双肩不可见")
        scan.add(frame(pitch: nil), message: "", postureMessage: "双肩不可见")
        expect(scan.lastHeadSample?.headPose == .init(pitch: 0.1, roll: 0))
        expect(scan.lastPostureSample == nil && scan.lastValidSample != nil)
    }

    func testHeadReferencePersistenceAndDistanceMigration() {
        let initial = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "camera",
            headReference: .init(pitch: 0.1, roll: 0.02))
        let migrated = initial.applyingDefaultDistanceIfMissing()
        expect(migrated.headReference == initial.headReference)
        if let data = try? JSONEncoder().encode(migrated), let decoded = try? JSONDecoder().decode(Calibration.self, from: data) {
            expect(decoded.headReference == initial.headReference)
        } else { expect(false) }
    }

    func testLegacyPitchMigratesWithoutInventingRollOrChangingDistance() {
        let legacy = Calibration(faceWidth: 0.2, faceShoulderRatio: 0.4, cameraID: "camera",
            referenceDistanceCM: 72, usesDefaultDistance: false, postureReference: body())
        let migrated = legacy.applyingHeadReferenceFromLegacyPostureIfMissing()
        expect(migrated.headReference == .init(pitch: 0.1, roll: nil))
        expect(migrated.faceWidth == legacy.faceWidth && migrated.referenceDistanceCM == 72)
        expect(migrated.postureReference == legacy.postureReference && migrated.usesDefaultDistance == false)
        let legacyDistance = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "camera", referenceDistanceCM: 60)
        expect(legacyDistance.applyingHeadReferenceFromLegacyPostureIfMissing().headReference == nil)
    }

    func testIndependentHeadAndShoulderResultsRemainVisibleInOneScan() {
        let shoulders = frame(body: body(ratio: 0.55))
        expect(PostureAssessment.evaluate(frame(), reference: reference(shoulders: true), shoulderSample: shoulders) == .changed(.forward))
        expect(PostureAssessment.evaluate(frame(pitch: 0.4), reference: reference(shoulders: true), shoulderSample: shoulders) == .changed(.headDown))
    }
}
