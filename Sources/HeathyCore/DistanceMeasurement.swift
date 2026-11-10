import Foundation

public enum DistanceMeasurement {
    public static let defaultReferenceCM = 60.0
    public static func isValidReference(_ value: Double) -> Bool { value.isFinite && (20...200).contains(value) }
}

extension Calibration {
    public func applyingDefaultDistanceIfMissing() -> Calibration {
        guard referenceDistanceCM == nil else { return self }
        return Calibration(faceWidth: faceWidth, faceShoulderRatio: faceShoulderRatio, cameraID: cameraID,
                           referenceDistanceCM: DistanceMeasurement.defaultReferenceCM, usesDefaultDistance: true,
                           postureReference: postureReference, headReference: headReference)
    }
    public func applyingHeadReferenceFromLegacyPostureIfMissing() -> Calibration {
        guard headReference == nil, let pitch = postureReference?.pitch else { return self }
        let head = HeadPoseFeatures(pitch: pitch)
        guard head.isValid else { return self }
        return Calibration(faceWidth: faceWidth, faceShoulderRatio: faceShoulderRatio, cameraID: cameraID,
            referenceDistanceCM: referenceDistanceCM, usesDefaultDistance: usesDefaultDistance,
            postureReference: postureReference, headReference: head)
    }
    public func estimatedDistanceCM(for sample: FrameFeatures) -> Double? {
        guard sample.isValid, faceWidth.isFinite, faceWidth > 0,
              let referenceDistanceCM, DistanceMeasurement.isValidReference(referenceDistanceCM) else { return nil }
        return referenceDistanceCM * faceWidth / sample.faceWidth
    }
    public func distanceOffsetCM(for sample: FrameFeatures) -> Double? {
        guard let distance = estimatedDistanceCM(for: sample), let referenceDistanceCM else { return nil }
        return distance - referenceDistanceCM
    }
    public func isTooClose(_ sample: FrameFeatures) -> Bool {
        guard sample.isValid else { return false }
        if referenceDistanceCM != nil { return distanceOffsetCM(for: sample).map { $0 < -5 } ?? false }
        return sample.faceWidth / faceWidth > 1.22
    }
    public func isWithinRecoveryDistance(_ sample: FrameFeatures) -> Bool {
        guard sample.isValid else { return false }
        if referenceDistanceCM != nil { return distanceOffsetCM(for: sample).map { $0 >= -3 } ?? false }
        return sample.faceWidth / faceWidth < 1.10
    }
}
