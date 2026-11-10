import Foundation

public struct PosturePoint {
    public let x: Double
    public let y: Double
    public let confidence: Double
    public init(x: Double, y: Double, confidence: Double = 1) { self.x = x; self.y = y; self.confidence = confidence }
}

public struct PostureFeatures: Codable, Equatable {
    public let faceShoulderRatio: Double
    public let headOffset: Double
    public let headHeight: Double
    public let shoulderTilt: Double
    public let pitch: Double?
    public let usesFaceCenter: Bool?
    public let shoulderModel: String?
    public var isCurrentShoulderReference: Bool { usesFaceCenter == true && shoulderModel == PoseNetDecoder.modelID }
    public init(faceShoulderRatio: Double, headOffset: Double, headHeight: Double, shoulderTilt: Double, pitch: Double? = nil, usesFaceCenter: Bool? = nil, shoulderModel: String? = nil) {
        self.faceShoulderRatio = faceShoulderRatio; self.headOffset = headOffset
        self.headHeight = headHeight; self.shoulderTilt = shoulderTilt; self.pitch = pitch
        self.usesFaceCenter = usesFaceCenter
        self.shoulderModel = shoulderModel
    }
    public static func measureFromFace(faceCenter: PosturePoint, faceWidth: Double, aspectRatio: Double, left: PosturePoint, right: PosturePoint, pitch: Double?, shoulderModel: String? = nil) -> PostureFeatures? {
        measure(faceWidth: faceWidth, aspectRatio: aspectRatio, nose: faceCenter, left: left, right: right, pitch: pitch, usesFaceCenter: true, shoulderModel: shoulderModel)
    }
    public var isValid: Bool {
        faceShoulderRatio.isFinite && (0.05...2).contains(faceShoulderRatio) &&
        headOffset.isFinite && abs(headOffset) < 1 && headHeight.isFinite && (0...2).contains(headHeight) &&
        shoulderTilt.isFinite && abs(shoulderTilt) < 0.8 && (pitch.map { $0.isFinite && abs($0) < 1.2 } ?? true)
    }
    public static func measure(faceWidth: Double, aspectRatio: Double, nose: PosturePoint, left: PosturePoint, right: PosturePoint, pitch: Double?, usesFaceCenter: Bool? = nil, shoulderModel: String? = nil) -> PostureFeatures? {
        guard faceWidth.isFinite, faceWidth > 0, aspectRatio.isFinite, aspectRatio > 0,
              [nose, left, right].allSatisfy({ $0.confidence >= 0.5 && (0.02...0.98).contains($0.x) && (0.02...0.98).contains($0.y) }) else { return nil }
        let dx = (right.x - left.x) * aspectRatio
        let dy = right.y - left.y
        let span = hypot(dx, dy)
        guard span > 0.12 * aspectRatio else { return nil }
        let features = PostureFeatures(faceShoulderRatio: faceWidth * aspectRatio / span,
            headOffset: (nose.x - (left.x + right.x) / 2) * aspectRatio / span,
            headHeight: (nose.y - (left.y + right.y) / 2) / span,
            shoulderTilt: atan2(dy, abs(dx)), pitch: pitch, usesFaceCenter: usesFaceCenter, shoulderModel: shoulderModel)
        return features.isValid ? features : nil
    }
}

public enum PostureChange: Equatable {
    case forward, headPosition, shoulders, headAngle, headDown, headTilt
    public var usesHeadAngles: Bool { self == .headDown || self == .headTilt }
}
public enum PostureAssessment: Equatable {
    case unavailable, needsCalibration, aligned, changed(PostureChange)
    public static func evaluate(_ sample: FrameFeatures, reference: Calibration?, shoulderSample: FrameFeatures? = nil) -> PostureAssessment {
        guard let reference else { return .needsCalibration }
        let head = HeadPoseAssessment.evaluate(sample, reference: reference)
        if head == .lowered { return .changed(.headDown) }
        if head == .tilted { return .changed(.headTilt) }
        let shoulders = evaluateShoulders(shoulderSample ?? sample, reference: reference)
        if case .changed = shoulders { return shoulders }
        if reference.headReference != nil {
            if head == .aligned { return .aligned }
            return head == .needsCalibration ? .needsCalibration : .unavailable
        }
        return shoulders
    }
    private static func evaluateShoulders(_ sample: FrameFeatures, reference: Calibration?) -> PostureAssessment {
        guard let reference, reference.postureReference != nil || reference.faceShoulderRatio != nil else { return .needsCalibration }
        guard sample.supportsPosture else { return .unavailable }
        if let baseline = reference.postureReference {
            guard let current = sample.posture, current.isValid else { return .unavailable }
            guard (current.usesFaceCenter ?? false) == (baseline.usesFaceCenter ?? false),
                  current.shoulderModel == baseline.shoulderModel else { return .needsCalibration }
            if current.faceShoulderRatio / baseline.faceShoulderRatio > 1.18 { return .changed(.forward) }
            if abs(current.shoulderTilt - baseline.shoulderTilt) > 0.17 { return .changed(.shoulders) }
            if abs(current.headOffset - baseline.headOffset) > 0.12 || abs(current.headHeight - baseline.headHeight) > 0.12 { return .changed(.headPosition) }
            if reference.headReference == nil, let expected = baseline.pitch {
                guard let pitch = current.pitch else { return .unavailable }
                if abs(pitch - expected) > 0.22 { return .changed(.headAngle) }
            }
            return .aligned
        }
        guard let current = sample.faceShoulderRatio, let baseline = reference.faceShoulderRatio else { return .unavailable }
        return current / baseline > 1.18 ? .changed(.forward) : .aligned
    }
    public static func isRecovered(_ sample: FrameFeatures, reference: Calibration, for change: PostureChange? = nil) -> Bool {
        guard evaluate(sample, reference: reference) == .aligned else { return false }
        if change?.usesHeadAngles == true { return HeadPoseAssessment.isRecovered(sample, reference: reference) }
        if change != nil {
            return shouldersRecovered(sample, reference: reference) &&
                (reference.headReference == nil || HeadPoseAssessment.isRecovered(sample, reference: reference))
        }
        if reference.headReference != nil {
            guard HeadPoseAssessment.isRecovered(sample, reference: reference) else { return false }
            return sample.supportsPosture && reference.postureReference != nil ? shouldersRecovered(sample, reference: reference) : true
        }
        return shouldersRecovered(sample, reference: reference)
    }
    private static func shouldersRecovered(_ sample: FrameFeatures, reference: Calibration) -> Bool {
        guard sample.supportsPosture else { return false }
        if let baseline = reference.postureReference {
            guard let current = sample.posture, current.isValid,
                  (current.usesFaceCenter ?? false) == (baseline.usesFaceCenter ?? false),
                  current.shoulderModel == baseline.shoulderModel,
                  current.faceShoulderRatio / baseline.faceShoulderRatio < 1.10,
                  abs(current.headOffset - baseline.headOffset) < 0.06,
                  abs(current.headHeight - baseline.headHeight) < 0.06,
                  abs(current.shoulderTilt - baseline.shoulderTilt) < 0.10 else { return false }
            if reference.headReference == nil, let expected = baseline.pitch { return current.pitch.map { abs($0 - expected) < 0.12 } ?? false }
            return true
        }
        guard let current = sample.faceShoulderRatio, let baseline = reference.faceShoulderRatio else { return false }
        return current / baseline < 1.10
    }
}
