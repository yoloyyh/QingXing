import Foundation

public struct FrameFeatures: Equatable {
    public let faceWidth: Double
    public let yaw: Double?
    public let pitch: Double?
    public let faceShoulderRatio: Double?
    public let posture: PostureFeatures?
    public let headPose: HeadPoseFeatures?
    public init(faceWidth: Double, yaw: Double? = 0, pitch: Double? = 0, faceShoulderRatio: Double? = nil, posture: PostureFeatures? = nil, headPose: HeadPoseFeatures? = nil) {
        self.faceWidth = faceWidth
        self.yaw = yaw
        self.pitch = pitch
        self.faceShoulderRatio = posture?.faceShoulderRatio ?? faceShoulderRatio
        self.posture = posture
        self.headPose = headPose
    }
    public static func valid(faceWidth: Double) -> Self { .init(faceWidth: faceWidth) }
    public static let unavailable = Self(faceWidth: 0)
    public var isValid: Bool { faceWidth > 0.04 && faceWidth < 0.9 && (yaw.map { abs($0) < 0.4 } ?? false) }
    public var supportsPosture: Bool {
        isValid && (posture?.isValid ?? ((pitch.map { abs($0) < 0.4 } ?? false) && faceShoulderRatio != nil))
    }
    public var supportsHeadPose: Bool { isValid && headPose?.isValid == true }
}

public struct Calibration: Codable, Equatable {
    public let faceWidth: Double
    public let faceShoulderRatio: Double?
    public let cameraID: String
    public let referenceDistanceCM: Double?
    public let usesDefaultDistance: Bool?
    public let postureReference: PostureFeatures?
    public let headReference: HeadPoseFeatures?
    public init(faceWidth: Double, faceShoulderRatio: Double?, cameraID: String, referenceDistanceCM: Double? = nil, usesDefaultDistance: Bool? = nil, postureReference: PostureFeatures? = nil, headReference: HeadPoseFeatures? = nil) {
        self.faceWidth = faceWidth
        self.faceShoulderRatio = faceShoulderRatio
        self.cameraID = cameraID
        self.referenceDistanceCM = referenceDistanceCM
        self.usesDefaultDistance = usesDefaultDistance
        self.postureReference = postureReference
        self.headReference = headReference
    }
}

public enum ReminderKind: String, Equatable { case distance, posture, rest }
public enum ReminderEvent: Equatable { case reminder(ReminderKind), adjusted, rested }
