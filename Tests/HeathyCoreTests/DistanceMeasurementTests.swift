import Foundation
import HeathyCore

struct DistanceMeasurementTests {
    private let start = Date(timeIntervalSince1970: 1_000)
    private func sample(at centimeters: Double, reference: Double = 60) -> FrameFeatures {
        .valid(faceWidth: 0.2 * reference / centimeters)
    }
    private func baseline(_ centimeters: Double = 60) -> Calibration {
        Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "test", referenceDistanceCM: centimeters)
    }

    func testDefaultCalibrationNeedsNoManualDistance() {
        let session = CalibrationSession()
        for frame in 0...3 { session.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(Double(frame) / 2)) }
        let reference = session.reference(cameraID: "test")
        expect(reference?.referenceDistanceCM == 60)
        expect(reference?.usesDefaultDistance == true)
        expect(reference?.faceWidth == 0.2)
    }

    func testDefaultMigrationPreservesThePersonalBaseline() {
        let legacy = Calibration(faceWidth: 0.23, faceShoulderRatio: 0.5, cameraID: "camera:640x480")
        let upgraded = legacy.applyingDefaultDistanceIfMissing()
        expect(upgraded.faceWidth == 0.23 && upgraded.faceShoulderRatio == 0.5)
        expect(upgraded.cameraID == legacy.cameraID)
        expect(upgraded.referenceDistanceCM == 60 && upgraded.usesDefaultDistance == true)
        let measured = baseline(70)
        expect(measured.applyingDefaultDistanceIfMissing() == measured)
        if let encoded = try? JSONEncoder().encode(upgraded), let decoded = try? JSONDecoder().decode(Calibration.self, from: encoded) {
            expect(decoded.usesDefaultDistance == true)
        } else { expect(false) }
    }

    func testDistanceUsesTheFixedReferenceScale() {
        let reference = baseline()
        expect(abs((reference.estimatedDistanceCM(for: sample(at: 54)) ?? 0) - 54) < 0.001)
        expect(abs((reference.distanceOffsetCM(for: sample(at: 54)) ?? 0) + 6) < 0.001)
        expect(abs((reference.distanceOffsetCM(for: sample(at: 66)) ?? 0) - 6) < 0.001)
        expect(reference.estimatedDistanceCM(for: .unavailable) == nil)
        let legacy = Calibration(faceWidth: 0.2, faceShoulderRatio: nil, cameraID: "test")
        expect(legacy.estimatedDistanceCM(for: sample(at: 54)) == nil)
    }

    func testFiveCentimeterReminderUsesDistanceInsteadOfOneRatio() {
        for referenceCM in [60.0, 90.0] {
            let engine = ReminderEngine()
            engine.calibration = baseline(referenceCM)
            for second in 0...4 {
                expect(engine.observe(sample(at: referenceCM - 4, reference: referenceCM), at: start.addingTimeInterval(Double(second))).isEmpty)
            }
            for second in 5..<8 {
                expect(engine.observe(sample(at: referenceCM - 6, reference: referenceCM), at: start.addingTimeInterval(Double(second))).isEmpty)
            }
            expect(engine.observe(sample(at: referenceCM - 6, reference: referenceCM), at: start.addingTimeInterval(8)) == [.reminder(.distance)])
            expect(engine.calibration?.referenceDistanceCM == referenceCM)
        }
    }

    func testRecoveryNeedsThreeCentimetersAndRewardsOnlyOnce() {
        let engine = ReminderEngine()
        engine.calibration = baseline()
        for second in 0...3 { _ = engine.observe(sample(at: 54), at: start.addingTimeInterval(Double(second))) }
        expect(engine.activeKind == .distance)
        for second in 4...7 { expect(engine.observe(sample(at: 56), at: start.addingTimeInterval(Double(second))).isEmpty) }
        for second in 8..<11 { expect(engine.observe(sample(at: 58), at: start.addingTimeInterval(Double(second))).isEmpty) }
        expect(engine.observe(sample(at: 58), at: start.addingTimeInterval(11)) == [.adjusted])
        expect(engine.observe(sample(at: 58), at: start.addingTimeInterval(12)).isEmpty)
    }

    func testCalibrationPersistsScaleAndReadsLegacyData() {
        let session = CalibrationSession(referenceDistanceCM: 60)
        for frame in 0...3 { session.add(.valid(faceWidth: 0.2), at: start.addingTimeInterval(Double(frame) / 2)) }
        let reference = session.reference(cameraID: "test")
        expect(reference?.referenceDistanceCM == 60)
        if let reference, let data = try? JSONEncoder().encode(reference), let decoded = try? JSONDecoder().decode(Calibration.self, from: data) {
            expect(decoded.referenceDistanceCM == 60)
            expect(decoded == reference)
        } else { expect(false) }
        let legacy = Data(#"{"faceWidth":0.2,"cameraID":"test"}"#.utf8)
        expect((try? JSONDecoder().decode(Calibration.self, from: legacy))?.faceWidth == 0.2)
        expect((try? JSONDecoder().decode(Calibration.self, from: legacy))?.referenceDistanceCM == nil)
    }

    func testDistanceLabelsShowEstimatedOffsetFromReference() {
        expect(DistanceReading.label(sample: sample(at: 54), reference: baseline(), isLive: false) == "最近检测：比参考近约 6 cm")
        expect(DistanceReading.label(sample: sample(at: 60), reference: baseline(), isLive: false) == "最近检测：参考范围内（±5 cm）")
        expect(DistanceReading.label(sample: sample(at: 66), reference: baseline(), isLive: true) == "比参考远约 6 cm")
        expect(baseline().isTooClose(sample(at: 54)))
        expect(!baseline().isTooClose(sample(at: 56)))
    }
}
