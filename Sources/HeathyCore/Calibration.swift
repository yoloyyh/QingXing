import Foundation

public enum CalibrationPhase: Equatable { case collecting, complete }
public final class CalibrationSession {
    public private(set) var phase: CalibrationPhase = .collecting
    public private(set) var progress: Double = 0
    public private(set) var validSampleCount = 0
    public private(set) var postureProgress = 0.0
    public private(set) var postureReference: PostureFeatures?
    public private(set) var headReference: HeadPoseFeatures?
    public private(set) var headProgress = 0.0
    public private(set) var headRejectionMessage: String?
    public var headFailureMessage: String? {
        guard headReference == nil else { return nil }
        if let headRejectionMessage { return headRejectionMessage }
        if headSamples.isEmpty { return "本轮未获得稳定头部角度，距离参考仍可使用；不需要双肩入镜。" }
        if headSamples.count < 4 { return "头部角度有效样本不足（\(headSamples.count)/4）。" }
        return "头部角度稳定时间不足 1.5 秒。"
    }
    private var faceScaleUnstable = false
    public private(set) var postureRejectionMessage: String?
    public var postureFailureMessage: String? {
        guard postureReference == nil else { return nil }
        if let postureRejectionMessage { return postureRejectionMessage }
        guard !postureSamples.isEmpty else { return nil }
        if postureSamples.count < 4 { return "头肩有效样本不足（\(postureSamples.count)/4），请坐稳后再校准。" }
        return "头肩稳定时间不足 1.5 秒，请坐稳后再校准。"
    }
    public var failureMessage: String {
        if phase == .complete { return "" }
        if faceScaleUnstable { return "人脸大小暂不稳定，未能记录参考。请面向镜头后重试。" }
        if validSampleCount == 0 { return "本轮没有获得有效人脸画面，请面向所选摄像头。" }
        if samples.isEmpty { return "人脸跟踪中断，请保持脸部入镜后重试。" }
        return "本轮有效画面不足（\(samples.count)/4），请点击再检测一次。"
    }
    private struct TimedSample {
        let features: FrameFeatures
        let time: Date
    }
    private var samples: [TimedSample] = []
    private var lastSample: Date?
    private var candidate: (width: Double, shoulder: Double?)?
    private var postureSamples: [PostureFeatures] = []
    private var postureStarted: Date?
    private var headSamples: [(pose: HeadPoseFeatures, time: Date)] = []
    private let referenceDistanceCM: Double?
    private let usesDefaultDistance: Bool
    public init(referenceDistanceCM: Double? = nil) {
        if let referenceDistanceCM {
            self.referenceDistanceCM = DistanceMeasurement.isValidReference(referenceDistanceCM) ? referenceDistanceCM : nil
            usesDefaultDistance = false
        } else {
            self.referenceDistanceCM = DistanceMeasurement.defaultReferenceCM
            usesDefaultDistance = true
        }
    }

    public func add(_ sample: FrameFeatures, at time: Date) {
        let gap = lastSample.map { time.timeIntervalSince($0) > 3.5 } ?? false
        lastSample = time
        guard sample.isValid, !gap else {
            if !samples.isEmpty || !postureSamples.isEmpty { postureRejectionMessage = "人脸或头肩跟踪中断，请面向镜头并保持双肩入镜。" }
            if phase == .collecting { samples = []; progress = 0; faceScaleUnstable = false }
            postureSamples = []; postureStarted = nil; postureProgress = 0
            resetHeadSamples(reason: "头部角度跟踪中断，请面向镜头。")
            return
        }
        if phase == .complete, postureReference == nil || headReference == nil, let candidate,
           abs(sample.faceWidth / candidate.width - 1) > 0.08 {
            if postureReference == nil { resetPostureSamples(reason: "人脸大小偏离参考，暂缓记录头肩。") }
            if headReference == nil { resetHeadSamples(reason: "人脸大小偏离参考，暂缓记录头部角度。") }
            return
        }
        if phase == .complete { collectHead(sample, at: time); collectPosture(sample, at: time); return }
        validSampleCount += 1
        samples.append(TimedSample(features: sample, time: time))
        if samples.count > 5 { samples.removeFirst() }
        guard let window = stableDistanceWindow() else {
            faceScaleUnstable = true
            postureReference = nil
            headReference = nil
            resetHeadSamples(reason: "人脸大小暂不稳定，正在等待稳定画面。")
            resetPostureSamples(reason: "人脸大小暂不稳定，正在等待稳定画面。")
            progress = 0
            return
        }
        if faceScaleUnstable { resetPostureSamples(reason: nil) }
        faceScaleUnstable = false
        progress = min(1, time.timeIntervalSince(window.first!.time) / 1.5)
        collectHead(sample, at: time)
        collectPosture(sample, at: time)
        guard window.count >= 4, progress >= 1 else { return }

        // Use the same accepted frames for distance and posture. A discarded
        // face-box spike must not poison the fixed head/shoulder reference.
        postureReference = nil
        headReference = nil
        resetHeadSamples(reason: nil)
        resetPostureSamples(reason: nil)
        for observed in window {
            collectHead(observed.features, at: observed.time)
            collectPosture(observed.features, at: observed.time)
        }
        let widths = window.map { $0.features.faceWidth }
        let shoulders = window.compactMap { $0.features.supportsPosture ? $0.features.faceShoulderRatio : nil }
        let stableShoulders = shoulders.count >= 4 && (shoulders.max()! / shoulders.min()!) < 1.15
        candidate = (median(widths), stableShoulders ? median(shoulders) : nil)
        phase = .complete
    }

    private func stableDistanceWindow() -> [TimedSample]? {
        func isStable(_ window: [TimedSample]) -> Bool {
            let widths = window.map { $0.features.faceWidth }
            return widths.max()! / widths.min()! <= 1.12
        }
        let latest = Array(samples.suffix(4))
        if isStable(latest) {
            // Callback intervals can be slightly shorter than the analysis
            // cadence. Keep the fifth stable frame to reach the required span.
            if samples.count == 5, latest.last!.time.timeIntervalSince(latest.first!.time) < 1.5,
               isStable(samples) { return samples }
            return latest
        }
        guard samples.count == 5 else { return nil }
        // Only one interior sample may be excluded. Keep both ends, including
        // the newest frame, so an ongoing move cannot be dismissed as noise.
        for excluded in 1...3 {
            let inliers = samples.enumerated().compactMap { $0.offset == excluded ? nil : $0.element }
            if isStable(inliers) { return inliers }
        }
        return nil
    }

    private func resetPostureSamples(reason: String?) {
        postureSamples = []; postureStarted = nil; postureProgress = 0
        postureRejectionMessage = reason
    }

    public func reference(cameraID: String) -> Calibration? {
        guard phase == .complete, let candidate else { return nil }
        return Calibration(faceWidth: candidate.width, faceShoulderRatio: postureReference?.faceShoulderRatio ?? candidate.shoulder,
                           cameraID: cameraID, referenceDistanceCM: referenceDistanceCM, usesDefaultDistance: usesDefaultDistance,
                           postureReference: postureReference, headReference: headReference)
    }

    private func resetHeadSamples(reason: String?) {
        headSamples = []; headProgress = headReference == nil ? 0 : 1
        headRejectionMessage = reason
    }

    private func collectHead(_ sample: FrameFeatures, at time: Date) {
        guard headReference == nil else { return }
        guard sample.supportsHeadPose, let pose = sample.headPose else {
            resetHeadSamples(reason: "本帧未获得头部角度，正在等待有效画面。")
            return
        }
        headRejectionMessage = nil
        headSamples.append((pose, time))
        if headSamples.count > 5 { headSamples.removeFirst() }
        let pitches = headSamples.map { $0.pose.pitch }
        let rolls = headSamples.compactMap { $0.pose.roll }
        guard spread(pitches) < 0.12, spread(rolls) < 0.12 else {
            headSamples = [(pose, time)]; headProgress = 0
            headRejectionMessage = "头部角度变化较大，请保持舒服的看屏姿势。"
            return
        }
        headProgress = min(1, time.timeIntervalSince(headSamples.first!.time) / 1.5)
        if headSamples.count >= 4, headProgress >= 1 {
            headReference = HeadPoseFeatures(pitch: median(pitches), roll: rolls.count >= 4 ? median(rolls) : nil)
        }
    }

    private func collectPosture(_ sample: FrameFeatures, at time: Date) {
        guard postureReference == nil else { return }
        guard sample.supportsPosture, let posture = sample.posture else {
            if !postureSamples.isEmpty { postureRejectionMessage = "头肩跟踪中断，请保持双肩入镜后再校准。" }
            postureSamples = []; postureStarted = nil; postureProgress = 0; return
        }
        if let first = postureSamples.first,
           (first.usesFaceCenter ?? false) != (posture.usesFaceCenter ?? false) || first.shoulderModel != posture.shoulderModel {
            postureSamples = []; postureStarted = nil
        }
        postureRejectionMessage = nil
        if postureStarted == nil { postureStarted = time }
        postureSamples.append(posture)
        let ratios = postureSamples.map(\.faceShoulderRatio)
        let offsets = postureSamples.map(\.headOffset)
        let heights = postureSamples.map(\.headHeight)
        let tilts = postureSamples.map(\.shoulderTilt)
        let pitches = postureSamples.compactMap(\.pitch)
        let stable = ratios.max()! / ratios.min()! < 1.15 && spread(offsets) < 0.08 && spread(heights) < 0.08 &&
            spread(tilts) < 0.10 && (pitches.isEmpty || spread(pitches) < 0.12)
        guard stable else {
            postureRejectionMessage = "头肩位置变化较大，请坐稳后再校准。"
            postureSamples = [posture]; postureStarted = time; postureProgress = 0; return
        }
        postureProgress = min(1, time.timeIntervalSince(postureStarted!) / 1.5)
        if postureSamples.count >= 4 && postureProgress >= 1 {
            postureReference = PostureFeatures(faceShoulderRatio: median(ratios), headOffset: median(offsets),
                headHeight: median(heights), shoulderTilt: median(tilts), pitch: pitches.count >= 4 ? median(pitches) : nil,
                usesFaceCenter: postureSamples.first?.usesFaceCenter, shoulderModel: postureSamples.first?.shoulderModel)
        }
    }

    private func spread(_ values: [Double]) -> Double { (values.max() ?? 0) - (values.min() ?? 0) }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
