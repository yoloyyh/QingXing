import Foundation

public struct HeadPoseFeatures: Codable, Equatable {
    public let pitch: Double
    public let roll: Double?
    public init(pitch: Double, roll: Double? = nil) { self.pitch = pitch; self.roll = roll }
    public var isValid: Bool {
        pitch.isFinite && abs(pitch) <= .pi / 2 && (roll.map { $0.isFinite && abs($0) <= .pi } ?? true)
    }
}

public enum HeadPoseAssessment: Equatable {
    case unavailable, needsCalibration, aligned, lowered, tilted
    public static func evaluate(_ sample: FrameFeatures, reference: Calibration?) -> HeadPoseAssessment {
        guard let baseline = reference?.headReference, baseline.isValid else { return .needsCalibration }
        guard sample.supportsHeadPose, let current = sample.headPose else { return .unavailable }
        // Vision defines positive pitch as nodding down (VNObservation.h).
        if current.pitch - baseline.pitch > 15 * .pi / 180 { return .lowered }
        if let expected = baseline.roll, let roll = current.roll, abs(rollDifference(roll, expected)) > 12 * .pi / 180 { return .tilted }
        return .aligned
    }
    public static func isRecovered(_ sample: FrameFeatures, reference: Calibration) -> Bool {
        guard sample.supportsHeadPose, let current = sample.headPose,
              let baseline = reference.headReference, baseline.isValid,
              current.pitch - baseline.pitch < 8 * .pi / 180 else { return false }
        if let expected = baseline.roll {
            guard let roll = current.roll else { return false }
            return abs(rollDifference(roll, expected)) < 6 * .pi / 180
        }
        return true
    }
    private static func rollDifference(_ value: Double, _ reference: Double) -> Double {
        atan2(sin(value - reference), cos(value - reference))
    }
}
