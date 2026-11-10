/// A scan stores numeric features and a failure explanation, never camera frames.
public struct ScanObservation {
    public private(set) var receivedSamples = 0
    public private(set) var validSamples = 0
    public private(set) var lastValidSample: FrameFeatures?
    public private(set) var lastPostureSample: FrameFeatures?
    public private(set) var lastHeadSample: FrameFeatures?
    private var lastPostureReason: String?
    private var lastHeadReason: String?
    private var lastFailureReason = ""
    public init() {}

    public mutating func add(_ sample: FrameFeatures, message: String, postureMessage: String? = nil) {
        receivedSamples += 1
        if sample.isValid { validSamples += 1; lastValidSample = sample }
        else { lastFailureReason = message }
        if sample.supportsPosture { lastPostureSample = sample }
        else { lastPostureReason = postureMessage }
        if sample.supportsHeadPose { lastHeadSample = sample }
        else { lastHeadReason = sample.isValid ? "本轮未获得头部角度，距离检测仍可使用。" : message }
    }

    public var headFailureMessage: String? {
        guard lastHeadSample == nil else { return nil }
        return failureMessage ?? lastHeadReason ?? "本轮未获得头部角度，请面向镜头后再检测。"
    }

    public var postureFailureMessage: String? {
        lastPostureSample == nil ? (lastPostureReason ?? "本轮没有头肩结果，请让双肩完整入镜后再检测。") : nil
    }

    public var failureMessage: String? {
        guard lastValidSample == nil else { return nil }
        if receivedSamples == 0 { return "5 秒内未收到分析结果，摄像头或识别模块启动较慢，请再试一次。" }
        return lastFailureReason.isEmpty ? "本轮未获取有效人脸，请面向所选摄像头后重试。" : lastFailureReason
    }
}

public enum DistanceReading {
    public static func label(sample: FrameFeatures?, reference: Calibration?, isLive: Bool) -> String {
        guard let sample else { return isLive ? "正在识别人脸" : "等待检测" }
        let prefix = isLive ? "" : "最近检测："
        guard sample.isValid else { return prefix + "未获取有效人脸" }
        guard let reference else { return "需要个人校准" }
        if let offset = reference.distanceOffsetCM(for: sample) {
            if abs(offset) <= 5 { return prefix + "参考范围内（±5 cm）" }
            return prefix + "比参考\(offset < 0 ? "近" : "远")约 \(Int(abs(offset).rounded())) cm"
        }
        let ratio = sample.faceWidth / reference.faceWidth
        return prefix + (ratio > 1.22 ? "比参考位置更靠近" : (ratio < 0.8 ? "比参考位置更远" : "与参考距离接近"))
    }
}
