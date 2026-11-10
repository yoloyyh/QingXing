import AppKit
import AVFoundation
import Combine
import HeathyCore

enum AppPage { case dashboard, settings, calibration }

struct BuddyNotice: Identifiable {
    enum Kind { case distance, posture, recovering, rest, reward, welcome, demo }
    enum RewardKind { case adjustment, rest }
    let id = UUID()
    let createdAt = Date()
    let kind: Kind
    let title: String
    let message: String
    var isDemo = false
    var restLevel: RestReminderLevel = .due
    var distanceLevel: DistanceReminderLevel = .gentle
    var expression: BuddyExpression?
    var rewardKind: RewardKind?
    var buddyExpression: BuddyExpression {
        if let expression { return expression }
        switch kind {
        case .distance: return .tooClose
        case .posture: return .posture
        case .rest: return .restDue
        case .reward: return .happy
        case .recovering, .welcome, .demo: return .calm
        }
    }
    var isPersistentRest: Bool { kind == .rest && !isDemo }
    var isAttentionReminder: Bool { kind == .rest || kind == .distance }
    var autoDismissDelay: TimeInterval? {
        if isAttentionReminder { return 30 }
        return kind == .reward ? 8 : (kind == .welcome ? 4 : 10)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var page: AppPage = .dashboard
    @Published private(set) var cameraStatus: CameraStatus = .off
    @Published private(set) var cameraSession: AVCaptureSession?
    @Published private(set) var scanSecondsRemaining = 5
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var nextCheckAt: Date?
    @Published private(set) var cameras: [CameraChoice] = []
    @Published private(set) var selectedCameraID: String
    @Published private(set) var latestSample: FrameFeatures = .unavailable
    @Published private var completedScan: ScanObservation?
    @Published private(set) var observationMessage = "开启后，仅在本机分析画面"
    @Published private(set) var postureObservationMessage = "检测时请让脸部清晰入镜，双肩为可选补充。"
    @Published private(set) var savedCalibration: Calibration?
    @Published private(set) var calibrationPhase: CalibrationPhase = .collecting
    @Published private(set) var calibrationProgress = 0.0
    @Published private(set) var calibrationComplete = false
    @Published private(set) var calibrationIssue: String?
    @Published private(set) var postureCalibrationIssue: String?
    @Published private(set) var calibrationCaptureStarted = false
    @Published private(set) var workDuration: TimeInterval = 0
    @Published private(set) var restRemaining: TimeInterval = 0
    @Published private(set) var restUrgency: RestReminderLevel = .none
    @Published private(set) var isResting = false
    @Published private(set) var restCompleted = false
    private var restStartingEnergy = 1.0
    private var restTargetDuration: TimeInterval = 300
    @Published private(set) var manualTimerRunning = false
    @Published private(set) var pauseUntil: Date?
    @Published private(set) var systemSuspended = false
    @Published private(set) var adjustments: Int
    @Published private(set) var rests: Int
    @Published private(set) var notice: BuddyNotice?
    @Published private(set) var lastDistanceDecision: String?
    private var distanceDelivery: String?

    func recordDistancePanelPresentation(noticeID: UUID, visible: Bool) {
        guard notice?.id == noticeID, notice?.kind == .distance, notice?.isDemo == false else { return }
        distanceDelivery = visible ? "距离弹窗已显示" : "已发出提醒，但窗口未显示"
        if var report = defaults.dictionary(forKey: "qx.lastScanDecision") {
            report["delivery"] = distanceDelivery
            defaults.set(report, forKey: "qx.lastScanDecision")
        }
        if !cameraActive { lastDistanceDecision = distanceDelivery }
    }
    @Published var quiet: Bool {
        didSet {
            defaults.set(quiet, forKey: "qx.quiet")
            if quiet { cancelDemo(); hideNotice() }
            else if oldValue {
                engine.rearmRestReminder()
                if let kind = engine.activeKind { handle([.reminder(kind)]) }
            }
        }
    }
    @Published var strongRestReminders: Bool { didSet { defaults.set(strongRestReminders, forKey: "qx.restEmphasis"); engine.rearmRestReminder() } }
    // The legacy key stores the work interval, not the length of a break.
    @Published var workMinutes: Double { didSet { engine.restInterval = workMinutes * 60; defaults.set(workMinutes, forKey: "qx.restMinutes") } }
    @Published var breakMinutes: Double {
        didSet {
            engine.restDuration = breakMinutes * 60
            defaults.set(breakMinutes, forKey: "qx.breakMinutes")
            if let notice, notice.kind == .rest { showRestReminder(level: notice.restLevel, isDemo: notice.isDemo) }
        }
    }
    @Published var experimentalPosture: Bool {
        didSet {
            let removingAlert = !experimentalPosture && engine.activeKind == .posture
            syncPostureEngine()
            if removingAlert { hideNotice() }
            defaults.set(experimentalPosture, forKey: "qx.posture")
        }
    }
    @Published var automaticChecks: Bool {
        didSet {
            defaults.set(automaticChecks, forKey: "qx.automaticChecks")
            if !automaticChecks { defaults.set(false, forKey: "qx.checksStarted") }
            else { rememberStartedChecks() }
            nextCheckAt = automaticChecks && wantedCamera && !cameraActive && !cameraBusy && !isPaused && !isResting ? Date().addingTimeInterval(engine.nextCheckInterval) : nil
        }
    }
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: "qx.theme"); onThemeChange?(theme) }
    }
    var onThemeChange: ((AppTheme) -> Void)?
    var onNotice: ((BuddyNotice?) -> Void)?

    let detector = CameraDetector()
    private let engine: ReminderEngine
    private let defaults: UserDefaults
    private let observationTime: () -> Date
    private var calibrationSession: CalibrationSession?
    private var cameraSignature = ""
    private var captureWindow: CaptureWindow?
    private var scanObservation = ScanObservation()
    private var wantedCamera = false
    private var activationGeneration = 0
    private var lastSeen: Date?
    private var suspendedAt: Date?
    private var suspensionGate = SuspensionGate()
    private var day: String
    private var clock: Timer?
    private var demoRunning = false
    private var cameraIntroSeen: Bool
    private var buddyResultDismissed = false

    init(defaults: UserDefaults = .standard, engine: ReminderEngine = ReminderEngine(), observationTime: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        theme = AppTheme(rawValue: defaults.string(forKey: "qx.theme") ?? "") ?? .mist
        self.engine = engine
        self.observationTime = observationTime
        cameraIntroSeen = defaults.bool(forKey: "qx.cameraIntroSeen")
        quiet = defaults.bool(forKey: "qx.quiet")
        strongRestReminders = defaults.object(forKey: "qx.restEmphasis") as? Bool ?? true
        let minutes = defaults.double(forKey: "qx.restMinutes")
        workMinutes = (15...90).contains(minutes) ? minutes : 45
        let breakLength = defaults.double(forKey: "qx.breakMinutes")
        breakMinutes = (1...20).contains(breakLength) ? breakLength : 5
        experimentalPosture = defaults.object(forKey: "qx.posture") as? Bool ?? true
        automaticChecks = defaults.object(forKey: "qx.automaticChecks") as? Bool ?? true
        selectedCameraID = defaults.string(forKey: "qx.camera") ?? ""
        day = Self.dayKey(Date())
        if defaults.string(forKey: "qx.day") == day {
            adjustments = defaults.integer(forKey: "qx.adjustments")
            rests = defaults.integer(forKey: "qx.rests")
        } else { adjustments = 0; rests = 0 }
        if let data = defaults.data(forKey: "qx.calibration"),
           let reference = try? JSONDecoder().decode(Calibration.self, from: data),
           reference.faceWidth.isFinite, (0.04...0.9).contains(reference.faceWidth),
           reference.faceShoulderRatio.map({ $0.isFinite && $0 > 0 }) ?? true,
           reference.referenceDistanceCM.map(DistanceMeasurement.isValidReference) ?? true,
           reference.postureReference?.isValid ?? true {
            let upgraded = reference.applyingDefaultDistanceIfMissing().applyingHeadReferenceFromLegacyPostureIfMissing()
            savedCalibration = upgraded
            if upgraded != reference { defaults.set(try? JSONEncoder().encode(upgraded), forKey: "qx.calibration") }
        }
        engine.restInterval = workMinutes * 60
        engine.restDuration = breakMinutes * 60
        engine.postureEnabled = false
        detector.onStatus = { [weak self] status in self?.receiveStatus(status) }
        detector.onSession = { [weak self] session in self?.cameraSession = session }
        detector.onStarted = { [weak self] uptime in
            self?.captureWindow = CaptureWindow(startedAt: uptime)
            self?.scanSecondsRemaining = Int(ceil(self?.captureWindow?.remaining(at: ProcessInfo.processInfo.systemUptime) ?? 0))
        }
        detector.onWindowEnded = { [weak self] in self?.finishScan() }
        detector.onSample = { [weak self] sample, signature, message, postureMessage in
            self?.receive(sample, signature: signature, message: message, postureMessage: postureMessage)
        }
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(at: Date()) }
        }
    }

    var isPaused: Bool { pauseUntil != nil || systemSuspended }
    var checksEnabled: Bool { wantedCamera }
    func restoreAutomaticChecks(at now: Date = Date(), cameraAuthorized: Bool) {
        guard !wantedCamera, !cameraActive, !cameraBusy, !isPaused, !isResting else { return }
        let hasReference = !selectedCameraID.isEmpty && savedCalibration.map {
            $0.referenceDistanceCM != nil && $0.cameraID.hasPrefix(selectedCameraID + ":")
        } == true
        guard cameraAuthorized, hasReference else {
            if defaults.bool(forKey: "qx.checksStarted") { defaults.set(false, forKey: "qx.checksStarted") }
            return
        }
        guard let scheduled = AutomaticCheckSchedule.restoredCheck(at: now,
            previouslyEnabled: defaults.bool(forKey: "qx.checksStarted"), automatic: automaticChecks,
            authorized: cameraAuthorized, hasReference: hasReference) else { return }
        wantedCamera = true
        manualTimerRunning = true
        nextCheckAt = scheduled
    }
    var cameraActive: Bool { cameraStatus == .running }
    var cameraBusy: Bool { cameraStatus == .starting || cameraStatus == .requesting || cameraStatus == .stopping }
    var hasCalibration: Bool { engine.calibration != nil }
    private var availableReference: Calibration? { engine.calibration ?? (cameraSignature.isEmpty ? savedCalibration : nil) }
    private var referenceMatchesCamera: Bool {
        selectedCameraID.isEmpty || availableReference?.cameraID.hasPrefix(selectedCameraID + ":") == true
    }
    var hasHeadReference: Bool { referenceMatchesCamera && availableReference?.headReference?.isValid == true }
    var hasPostureReference: Bool {
        hasHeadReference || (referenceMatchesCamera && availableReference?.postureReference?.isCurrentShoulderReference == true)
    }
    var needsDistanceCalibration: Bool { savedCalibration?.referenceDistanceCM == nil }
    var needsAnyCalibration: Bool { needsDistanceCalibration || (experimentalPosture && !hasHeadReference) }
    var canStartCalibration: Bool {
        !calibrationCaptureStarted && !cameraBusy && !cameraActive && !isPaused && !isResting
    }
    var distanceWarning: Bool { engine.calibration?.isTooClose(displayedSample) ?? false }
    var distanceReferenceDetail: String? {
        guard let centimeters = engine.calibration?.referenceDistanceCM else { return nil }
        let source = engine.calibration?.usesDefaultDistance == true ? "默认参考" : "个人参考"
        return "\(source) \(Int(centimeters.rounded())) cm · 约 5 cm 提醒 · 仅估算"
    }
    private var displayedSample: FrameFeatures {
        cameraActive ? latestSample : (completedScan?.lastValidSample ?? .unavailable)
    }
    var currentRatio: Double? {
        guard displayedSample.isValid, let reference = engine.calibration else { return nil }
        return displayedSample.faceWidth / reference.faceWidth
    }
    var needsAdjustment: Bool { !isPaused && !isResting && engine.activeKind != nil }
    @Published private(set) var recoveryUnconfirmed = false
    var isRecovering: Bool { engine.isRecovering(latestSample) }
    var distanceFollowUpActive: Bool { engine.distanceReminderLevel != .none }
    var distancePresentationLevel: DistanceReminderLevel {
        guard !isPaused, !isResting else { return .none }
        if let notice, notice.kind == .distance, notice.isDemo { return notice.distanceLevel }
        return engine.distanceReminderLevel
    }
    var distanceFollowUpDetail: String? {
        guard distanceFollowUpActive else { return nil }
        if isPaused { return "距离复查已暂停，继续后 5 分钟再确认。" }
        if isResting { return "先好好休息，返回工作后 5 分钟再确认距离。" }
        if !automaticChecks || !wantedCamera { return "距离待确认 · 自动检测已关闭，可手动复查。" }
        if completedScan?.failureMessage != nil { return "这轮没看清，5 分钟后再复查，不据此升级或奖励。" }
        return "距离待确认 · 每 5 分钟复查，确认恢复后改回半小时一次。"
    }
    var buddyExpression: BuddyExpression {
        if isPaused { return .paused }
        if isResting { return restCompleted ? .happy : .resting }
        if let notice, notice.isDemo || notice.kind == .reward { return notice.buddyExpression }
        if restUrgency != .none { return .restDue }
        if cameraActive {
            let result = currentBuddyResult
            return result == .calm ? .checking : result
        }
        if currentBuddyResult != .calm { return currentBuddyResult }
        if completedScan?.failureMessage != nil { return .unclear }
        return .calm
    }
    private var currentBuddyResult: BuddyExpression {
        guard !buddyResultDismissed else { return .calm }
        return BuddyExpression.result(distanceWarning: distanceWarning, posture: experimentalPosture ? postureAssessment : .unavailable)
    }
    var buddyHeadline: String {
        if notice?.isDemo == true { return buddyExpression.title }
        if isPaused { return "已暂停提醒" }
        if isResting { return restCompleted ? "满血状态，准备好再出发" : "正在充能，慢慢来" }
        if buddyExpression == .happy { return notice?.title ?? "调整已确认，舒服多了" }
        if restUrgency != .none { return "该离开屏幕休息一下了" }
        if cameraBusy { return "正在准备检测" }
        if cameraActive { return currentBuddyResult == .calm ? "正在检测，请自然坐好" : currentBuddyResult.title }
        if calibrationIssue != nil { return "需要重新记录参考位置" }
        guard let completedScan else { return needsDistanceCalibration ? "先记录你的舒服位置" : "等待首次检测" }
        if completedScan.failureMessage != nil { return "这轮没看清" }
        if buddyResultDismissed { return "已忽略这次提醒" }
        if distanceWarning { return "上次检测：距离偏近" }
        if postureWarning { return currentBuddyResult.title }
        if recoveryUnconfirmed || distanceFollowUpActive { return "位置接近参考，尚未确认恢复" }
        guard engine.calibration != nil else { return "需要重新记录参考位置" }
        if let offset = engine.calibration?.distanceOffsetCM(for: displayedSample), offset > 5 { return "上次距离比参考更远" }
        if experimentalPosture, case .aligned = postureAssessment { return "上次已测距离和姿态接近参考" }
        return "上次距离在参考范围内"
    }
    private var nextDetectionCopy: String {
        if let nextCheckAt {
            let minutes = max(1, Int(ceil(nextCheckAt.timeIntervalSinceNow / 60)))
            return "\(minutes) 分钟后\(distanceFollowUpActive ? "复查" : "再检测") · 当前摄像头关闭"
        }
        return "可点“立即检测”更新 · 当前摄像头关闭"
    }
    private var lastDetectionAge: String {
        guard let lastCheckedAt else { return "上次检测" }
        let minutes = max(0, Int(Date().timeIntervalSince(lastCheckedAt) / 60))
        if minutes == 0 { return "刚刚检测" }
        if minutes < 60 { return "\(minutes) 分钟前检测" }
        return "\(minutes / 60) 小时前检测"
    }
    var buddyDetail: String {
        if notice?.isDemo == true { return "表情演示 · 不会启动摄像头" }
        if isPaused { return "计时和检测已暂停，继续后再提醒你。" }
        if isResting { return restCompleted ? "已完成本轮休息，健康环已充满。\n点击“满血出发”再开始工作。" : "离开屏幕活动一下，健康环正在慢慢补满。" }
        if cameraActive { return "本轮还剩 \(scanSecondsRemaining) 秒 · 结束后自动关闭摄像头" }
        if cameraBusy { return cameraDetail }
        if buddyExpression == .happy { return notice?.message ?? "已确认恢复到参考范围，主动调整 +1。" }
        if restUrgency != .none { return "已工作到设定时长，起身活动 \(Int(breakMinutes)) 分钟吧。" }
        if let calibrationIssue { return calibrationIssue }
        guard let completedScan else {
            return needsDistanceCalibration ? "坐到舒服的位置，用 5 秒记录参考；此时摄像头未开启。" : "本次启动后还没有检测结果。\n" + nextDetectionCopy
        }
        if let failure = completedScan.failureMessage { return lastDetectionAge + " · " + failure + "\n" + nextDetectionCopy }
        if buddyResultDismissed { return "本轮判断已忽略；可重新检测或校准参考位置。" }
        if recoveryUnconfirmed { return lastDetectionAge + " · 已接近参考，但稳定样本不足。\n" + nextDetectionCopy }
        if distanceWarning { return lastDetectionAge + " · 距离比参考偏近，请往后靠一点。\n" + nextDetectionCopy }
        if postureWarning { return lastDetectionAge + " · 头部或肩部位置相对参考有变化。\n" + nextDetectionCopy }
        if distanceFollowUpActive { return lastDetectionAge + " · 尚未确认调整成功。\n" + nextDetectionCopy }
        let scope: String
        if !experimentalPosture { scope = "姿态检测已关闭" }
        else {
            switch postureAssessment {
            case .needsCalibration: scope = "头部尚未校准，暂只判断距离"
            case .unavailable: scope = "头部角度未获取，暂只判断距离"
            case .aligned: scope = hasHeadReference ? "已测头部角度接近参考" : "头肩位置接近参考"
            case .changed: scope = "姿态相对参考有变化"
            }
        }
        return lastDetectionAge + " · " + scope + "\n" + nextDetectionCopy
    }
    var restPresentationLevel: RestReminderLevel {
        guard !isPaused, !isResting else { return .none }
        let level: RestReminderLevel
        if let notice, notice.isDemo, notice.kind == .rest { level = notice.restLevel }
        else { level = manualTimerRunning ? restUrgency : .none }
        return strongRestReminders || level == .none ? level : .due
    }
    var restEdgeLevel: RestReminderLevel {
        guard !quiet, restPresentationLevel >= .overdue else { return .none }
        return restPresentationLevel
    }
    var restOverdueMinutes: Int {
        if let notice, notice.isDemo, notice.kind == .rest {
            return notice.restLevel == .urgent ? 10 : (notice.restLevel == .overdue ? 3 : 0)
        }
        return Int(max(0, workDuration - workMinutes * 60) / 60)
    }
    var restPlanSummary: String {
        if isResting { return restCompleted ? "本轮已充满 · 今天完成 \(rests) 次休息" : "休息满 \(activeRestMinutes) 分钟，自动进入满血状态。" }
        if isPaused { return "工作计时已暂停，继续后恢复提醒。" }
        if manualTimerRunning && workDuration >= workMinutes * 60 {
            return restOverdueMinutes == 0 ? "休息时间到啦，离开屏幕 \(Int(breakMinutes)) 分钟吧。" : "休息计划已超时 \(restOverdueMinutes) 分钟，离开屏幕 \(Int(breakMinutes)) 分钟吧。"
        }
        return "再过 \(Int(ceil(remainingWork / 60))) 分钟，休息 \(Int(breakMinutes)) 分钟"
    }
    var canPreviewRestReminder: Bool {
        !quiet && !isPaused && !isResting && !cameraActive && !cameraBusy && !distanceFollowUpActive && page != .calibration && calibrationSession == nil && !(manualTimerRunning && workDuration >= workMinutes * 60)
    }
    var remainingWork: TimeInterval { max(0, workMinutes * 60 - workDuration) }
    var activeRestMinutes: Int { Int((isResting ? restTargetDuration : breakMinutes * 60) / 60) }
    var restProgress: Double {
        guard isResting, restTargetDuration > 0 else { return 0 }
        return restCompleted ? 1 : min(1, max(0, 1 - restRemaining / restTargetDuration))
    }
    /// A visual work/rest budget, not a measured physiological health score.
    var healthEnergy: Double {
        if isResting { return restStartingEnergy + (1 - restStartingEnergy) * restProgress }
        return max(0, min(1, 1 - workDuration / (workMinutes * 60)))
    }
    var healthRingLabel: String {
        if isResting { return restCompleted ? "满血状态 · 100%" : "休息充能 · \(Int(healthEnergy * 100))%" }
        if isPaused { return "健康环 · 已暂停" }
        if !manualTimerRunning { return "健康环 · 待开始" }
        if healthEnergy <= 0 { return "健康环 · 该充电啦" }
        return "健康环 · \(Int(healthEnergy * 100))%"
    }
    var statusLabel: String {
        if cameraStatus == .stopping { return "关闭中" }
        if systemSuspended { return "已暂停" }
        if pauseUntil != nil { return "已暂停" }
        if isResting { return restCompleted ? "已充满" : "休息中" }
        switch cameraStatus {
        case .running: return "检测 \(scanSecondsRemaining)s"
        case .requesting: return "等待授权"
        case .starting: return "启动中"
        case .stopping: return "关闭中"
        case .denied: return "未授权"
        case .unavailable: return "仅计时"
        case .off:
            if nextCheckAt != nil { return distanceFollowUpActive ? "等待复查" : "等待检测" }
            if lastCheckedAt != nil { return "检测结束" }
            return manualTimerRunning ? "仅计时" : "未开启"
        }
    }
    var cameraDetail: String {
        switch cameraStatus {
        case .running: return "本轮最多 5 秒 · 剩余 \(scanSecondsRemaining) 秒 · 仅本机"
        case .starting: return "正在启动摄像头，尚未开始检测"
        case .requesting: return "请在系统提示中选择是否允许"
        case .stopping: return "正在停止采集并释放摄像头"
        case .denied: return "摄像头未授权，休息计时仍可使用"
        case .unavailable(let message): return message
        case .off:
            if let calibrationIssue { return "摄像头已关闭 · \(calibrationIssue)" }
            if let nextCheckAt { return "摄像头已关闭 · \(max(1, Int(ceil(nextCheckAt.timeIntervalSinceNow / 60)))) 分钟后\(distanceFollowUpActive ? "复查" : "检测") 5 秒" }
            return lastCheckedAt != nil ? "本轮检测已结束 · 摄像头已关闭" : "摄像头已关闭 · 每次只检测 5 秒"
        }
    }
    var distanceLabel: String {
        let sample: FrameFeatures?
        if cameraActive { sample = scanObservation.receivedSamples == 0 ? nil : latestSample }
        else { sample = completedScan.map { $0.lastValidSample ?? .unavailable } }
        return DistanceReading.label(sample: sample, reference: engine.calibration, isLive: cameraActive)
    }
    var distanceIssue: String? {
        if let calibrationIssue { return calibrationIssue }
        if cameraActive { return latestSample.isValid ? nil : observationMessage }
        return completedScan?.failureMessage
    }
    private var displayedPostureSample: FrameFeatures {
        cameraActive ? latestSample : (completedScan?.lastHeadSample ?? completedScan?.lastPostureSample ?? .unavailable)
    }
    private var displayedShoulderSample: FrameFeatures { cameraActive ? latestSample : (completedScan?.lastPostureSample ?? .unavailable) }
    private var postureAssessment: PostureAssessment {
        PostureAssessment.evaluate(displayedPostureSample, reference: engine.calibration, shoulderSample: displayedShoulderSample)
    }
    var postureWarning: Bool {
        guard experimentalPosture else { return false }
        if case .changed = postureAssessment { return true }
        return false
    }
    var postureLabel: String {
        guard experimentalPosture else { return "已关闭" }
        guard hasPostureReference else { return "需校准头部" }
        guard cameraActive || completedScan != nil else { return "等待检测" }
        let prefix = cameraActive ? "" : "最近检测："
        switch postureAssessment {
        case .needsCalibration: return "需校准头部"
        case .unavailable: return prefix + "头部角度暂未获取"
        case .aligned: return prefix + (hasHeadReference ? "已测角度接近参考" : "头肩相对位置接近参考")
        case .changed(let change):
            switch change {
            case .headDown: return prefix + "低头幅度较大"
            case .headTilt: return prefix + "头部有些侧倾"
            case .forward: return prefix + "头肩比例有变化"
            case .headPosition: return prefix + "头部相对位置有偏移"
            case .shoulders: return prefix + "双肩有些倾斜"
            case .headAngle: return prefix + "头部角度有变化"
            }
        }
    }
    var postureIssue: String? {
        guard experimentalPosture else { return nil }
        guard hasHeadReference else {
            if cameraActive {
                if let rejection = calibrationSession?.headRejectionMessage { return rejection }
                if latestSample.supportsHeadPose {
                    return calibrationSession != nil ? "已获取头部角度，正在记录稳定参考；不需要双肩入镜。" : "已获取头部角度，请点击校准记录参考；不需要双肩入镜。"
                }
                return latestSample.isValid ? "暂未获得头部角度，距离检测仍可使用。" : observationMessage
            }
            return postureCalibrationIssue ?? completedScan?.headFailureMessage ?? "记录一次头部参考即可判断低头和侧倾，不需要双肩入镜。"
        }
        guard cameraActive || completedScan != nil else { return nil }
        let sample = displayedPostureSample
        guard sample.supportsHeadPose else {
            return cameraActive ? (sample.isValid ? "暂未获得头部角度，距离检测仍可使用。" : observationMessage) : completedScan?.headFailureMessage
        }
        if availableReference?.headReference?.roll == nil { return "当前可判断低头；侧倾参考可在下次主动校准时补充。" }
        if sample.headPose?.roll == nil { return "本轮可判断低头，侧倾角度暂缺。" }
        return displayedShoulderSample.supportsPosture && availableReference?.postureReference?.isCurrentShoulderReference == true ? nil : "本轮按头部角度判断，无需双肩。"
    }
    var calibrationHeadline: String {
        if calibrationComplete && experimentalPosture && !hasHeadReference { return "距离已记录，继续记录头部" }
        return calibrationComplete ? "认识你啦！" : "找到你的舒服位置"
    }
    private func syncPostureEngine() {
        engine.postureEnabled = experimentalPosture && (engine.calibration?.headReference?.isValid == true || engine.calibration?.postureReference?.isCurrentShoulderReference == true)
    }
    var calibrationInstruction: String {
        if !calibrationCaptureStarted { return "靠好坐稳，自然看屏幕，让脸部入镜即可，不需要双肩。点击开始后最多检测 5 秒，无需测量或输入。" }
        switch calibrationPhase {
        case .collecting: return "坐到你希望保持的位置，面向镜头。用 5 秒建立固定参考，之后都与它比较。"
        case .complete:
            if experimentalPosture && !hasHeadReference { return "距离参考已保存。剩余时间继续记录头部角度，自然看屏幕即可，不需要双肩。" }
            return "参考已记录，之后都与这次校准比较；仅主动重新校准时更新。本轮结束后摄像头关闭。"
        }
    }

    func enableCamera() {
        guard page != .calibration, !cameraBusy, !cameraActive, !isPaused, !isResting else { return }
        if needsDistanceCalibration { beginCalibration(); return }
        activateCamera()
    }

    func startCalibrationCapture() {
        guard page == .calibration, canStartCalibration else { return }
        calibrationSession = CalibrationSession()
        calibrationCaptureStarted = true
        activateCamera()
    }

    private func activateCamera() {
        cancelDemo()
        hideNonRestNotice()
        nextCheckAt = nil
        wantedCamera = true
        activationGeneration += 1
        let token = activationGeneration
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: startSelectedCamera()
        case .notDetermined:
            cameraStatus = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.activationGeneration == token, self.wantedCamera, !self.isPaused else { return }
                    if allowed { self.startSelectedCamera() }
                    else { self.wantedCamera = false; self.defaults.set(false, forKey: "qx.checksStarted"); self.cameraStatus = .denied; self.manualTimerRunning = true; self.cancelCalibration() }
                }
            }
        default:
            wantedCamera = false
            defaults.set(false, forKey: "qx.checksStarted")
            cameraStatus = .denied
            manualTimerRunning = true
            cancelCalibration()
        }
    }

    private func startSelectedCamera() {
        guard wantedCamera, !isPaused, !isResting else { return }
        cancelDemo()
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            wantedCamera = false; defaults.set(false, forKey: "qx.checksStarted"); cameraStatus = .denied; return
        }
        cameras = CameraDetector.availableCameras()
        if !cameras.contains(where: { $0.id == selectedCameraID }) {
            selectedCameraID = cameras.first?.id ?? ""
            completedScan = nil
            lastCheckedAt = nil
            calibrationIssue = nil
            observationMessage = "摄像头已关闭"
        }
        guard !selectedCameraID.isEmpty else {
            cameraStatus = .unavailable("没有可用的摄像头，请先连接设备。")
            wantedCamera = false
            defaults.set(false, forKey: "qx.checksStarted")
            manualTimerRunning = true
            return
        }
        defaults.set(selectedCameraID, forKey: "qx.camera")
        if calibrationSession == nil, savedCalibration?.cameraID.hasPrefix(selectedCameraID + ":") != true {
            prepareCalibration()
            return
        }
        prepareObservationWindow()
        rememberStartedChecks()
        detector.start(cameraID: selectedCameraID, includeBodyPose: experimentalPosture)
    }

    // Shared by real camera startup and camera-free callback replay.
    func prepareObservationWindow() {
        latestSample = .unavailable
        buddyResultDismissed = false
        scanSecondsRemaining = 5
        scanObservation = ScanObservation()
        calibrationIssue = nil
        postureCalibrationIssue = nil
        recoveryUnconfirmed = false
        distanceDelivery = nil
        lastDistanceDecision = nil
        observationMessage = "正在等待摄像头的首帧画面。"
        engine.endObservationWindow()
    }

    func selectCamera(_ id: String) {
        guard !cameraActive, !cameraBusy, id != selectedCameraID else { return }
        selectedCameraID = id
        defaults.set(id, forKey: "qx.camera")
        completedScan = nil
        lastCheckedAt = nil
        calibrationIssue = nil
        observationMessage = "摄像头已关闭"
        postureCalibrationIssue = nil
        cancelCalibration()
        engine.suspend()
        if wantedCamera { startSelectedCamera() }
    }

    private func receiveStatus(_ status: CameraStatus) {
        let wasRunning = cameraActive
        cameraStatus = status
        if status == .running && !wasRunning {
            manualTimerRunning = true
            lastSeen = Date()
            if !cameraIntroSeen {
                cameraIntroSeen = true
                defaults.set(true, forKey: "qx.cameraIntroSeen")
                show(.init(kind: .welcome, title: "看一小会儿就好", message: "本轮最多 5 秒，结束后自动关闭摄像头。"))
            }
        }
        switch status {
        case .denied, .unavailable:
            wantedCamera = false
            defaults.set(false, forKey: "qx.checksStarted")
            manualTimerRunning = true
            latestSample = .unavailable
            nextCheckAt = nil
            captureWindow = nil
            engine.suspend()
            cancelCalibration()
        default: break
        }
    }

    func disableCamera() {
        wantedCamera = false
        defaults.set(false, forKey: "qx.checksStarted")
        nextCheckAt = nil
        activationGeneration += 1
        manualTimerRunning = true
        stopCapture()
        cancelCalibration()
        hideNonRestNotice()
    }

    private func stopCapture(preservingDistanceFollowUp: Bool = false) {
        latestSample = .unavailable
        lastSeen = nil
        observationMessage = "摄像头已关闭"
        captureWindow = nil
        scanSecondsRemaining = 0
        engine.suspend(preservingDistanceFollowUp: preservingDistanceFollowUp)
        detector.stop()
    }

    func toggleManualTimer() {
        if cameraActive || cameraBusy { disableCamera() }
        manualTimerRunning.toggle()
        if !manualTimerRunning {
            restUrgency = .none
            if notice?.kind == .rest { closeNotice() }
        } else { engine.rearmRestReminder() }
    }

    private func receive(_ sample: FrameFeatures, signature: String, message: String, postureMessage: String?) {
        guard cameraActive, wantedCamera, !isPaused, !isResting else { return }
        let now = observationTime()
        latestSample = sample
        observationMessage = message
        postureObservationMessage = postureMessage ?? ""
        if sample.isValid { lastSeen = now }
        if cameraSignature != signature {
            cameraSignature = signature
            scanObservation = ScanObservation()
            completedScan = nil
            engine.suspend()
            engine.calibration = savedCalibration?.cameraID == signature ? savedCalibration : nil
            syncPostureEngine()
            if calibrationSession != nil {
                calibrationSession = CalibrationSession()
                calibrationPhase = .collecting
                calibrationProgress = 0
                calibrationComplete = false
            }
        }
        scanObservation.add(sample, message: message, postureMessage: postureMessage)
        if calibrationSession == nil && engine.calibration == nil {
            calibrationIssue = "摄像头或画面规格已变化，请重新校准 5 秒。"
            wantedCamera = false
            defaults.set(false, forKey: "qx.checksStarted")
        }
        if let calibrationSession {
            calibrationSession.add(sample, at: now)
            calibrationPhase = calibrationSession.phase
            calibrationProgress = experimentalPosture ? (calibrationSession.progress + calibrationSession.headProgress) / 2 : calibrationSession.progress
            if let reference = calibrationSession.reference(cameraID: signature) {
                if savedCalibration != reference { defaults.set(try? JSONEncoder().encode(reference), forKey: "qx.calibration") }
                savedCalibration = reference
                engine.calibration = reference
                syncPostureEngine()
                calibrationComplete = true
            }
            return
        }
        handle(engine.observe(sample, at: now))

    }

    func beginCalibration() {
        guard !cameraActive, !cameraBusy, !isPaused, !isResting else { return }
        cancelDemo()
        hideNonRestNotice()
        prepareCalibration()
    }

    private func prepareCalibration() {
        wantedCamera = false
        defaults.set(false, forKey: "qx.checksStarted")
        nextCheckAt = nil
        activationGeneration += 1
        engine.suspend()
        engine.calibration = nil
        syncPostureEngine()
        completedScan = nil
        lastCheckedAt = nil
        calibrationSession = nil
        calibrationCaptureStarted = false
        calibrationIssue = nil
        postureCalibrationIssue = nil
        calibrationPhase = .collecting
        calibrationProgress = 0
        calibrationComplete = false
        page = .calibration
    }

    func cancelCalibration() {
        calibrationSession = nil
        calibrationCaptureStarted = false
        calibrationComplete = false
        engine.calibration = savedCalibration?.cameraID == cameraSignature ? savedCalibration : nil
        syncPostureEngine()
        page = .dashboard
    }

    func pause() {
        cancelDemo()
        restUrgency = .none
        pauseUntil = Date().addingTimeInterval(15 * 60)
        activationGeneration += 1
        nextCheckAt = nil
        stopCapture(preservingDistanceFollowUp: true)
        cancelCalibration()
        hideNotice()
    }

    func resume() {
        engine.rearmRestReminder()
        pauseUntil = nil
        scheduleNextScan()
    }

    func suspendForSystem(_ reason: SuspensionReason) {
        suspensionGate.suspend(reason)
        guard !systemSuspended else { return }
        systemSuspended = true
        restUrgency = .none
        suspendedAt = Date()
        activationGeneration += 1
        nextCheckAt = nil
        stopCapture(preservingDistanceFollowUp: true)
        cancelCalibration()
        cancelDemo()
        hideNotice()
    }

    func resumeFromSystem(_ reason: SuspensionReason) {
        suspensionGate.resume(reason)
        guard systemSuspended, !suspensionGate.isSuspended else { return }
        if let suspendedAt, Date().timeIntervalSince(suspendedAt) >= (engine.activeRestDuration ?? breakMinutes * 60) { engine.resetWork(preservingDistanceFollowUp: true) }
        systemSuspended = false
        engine.rearmRestReminder()
        self.suspendedAt = nil
        if let pauseUntil, pauseUntil <= Date() { self.pauseUntil = nil }
        scheduleNextScan()
    }

    func beginRest(at now: Date = Date()) {
        guard !isResting else { return }
        cancelDemo()
        hideNotice()
        activationGeneration += 1
        nextCheckAt = nil
        restStartingEnergy = healthEnergy
        engine.beginRest(at: now)
        restTargetDuration = engine.activeRestDuration ?? breakMinutes * 60
        restCompleted = false
        restUrgency = .none
        isResting = true
        restRemaining = engine.restRemaining(at: now)
        stopCapture(preservingDistanceFollowUp: true)
        cancelCalibration()
    }

    func finishRest(at now: Date = Date()) {
        completeRestIfReady(at: now)
        guard isResting, restCompleted else { return }
        isResting = false
        restCompleted = false
        restRemaining = 0
        hideNotice()
        scheduleNextScan()
    }

    private func completeRestIfReady(at now: Date) {
        guard isResting, !restCompleted, !systemSuspended else { return }
        let events = engine.finishRest(at: now)
        guard !events.isEmpty else { return }
        restCompleted = true
        restRemaining = 0
        workDuration = engine.workDuration
        handle(events)
    }

    func cancelRest(at now: Date = Date()) {
        completeRestIfReady(at: now)
        engine.cancelRest()
        isResting = false
        restCompleted = false
        restRemaining = 0
        hideNotice()
        scheduleNextScan()
    }

    func tick(at now: Date) {
        if day != Self.dayKey(now) { day = Self.dayKey(now); adjustments = 0; rests = 0; persistTotals() }
        if let pauseUntil, pauseUntil <= now { resume() }
        if let nextCheckAt, now >= nextCheckAt, wantedCamera, automaticChecks, !cameraActive, !cameraBusy, !isPaused, !isResting {
            self.nextCheckAt = nil
            startSelectedCamera()
        }
        if let captureWindow { scanSecondsRemaining = Int(ceil(captureWindow.remaining(at: ProcessInfo.processInfo.systemUptime))) }
        let working = !isPaused && !isResting && manualTimerRunning
        let events = engine.tick(at: now, working: working)
        workDuration = engine.workDuration
        restUrgency = working ? engine.restReminderLevel(at: now) : .none
        if restUrgency == .none, notice?.kind == .rest, notice?.isDemo == false { hideNotice() }
        handle(events)
        restRemaining = engine.restRemaining(at: now)
        completeRestIfReady(at: now)
        // A stalled stream must not leave an old observation looking current.
        if cameraActive, let lastSeen, now.timeIntervalSince(lastSeen) > 5, latestSample.isValid {
            latestSample = .unavailable
            observationMessage = "画面暂未更新，暂时无法判断"
            _ = engine.observe(.unavailable, at: now)
        }
    }

    private func finishScan() {
        captureWindow = nil
        scanSecondsRemaining = 0
        lastCheckedAt = Date()
        completedScan = scanObservation
        let wasRecovering = isRecovering
        let pendingDecision = engine.distanceDecisionExplanation
        let completionEvents = engine.completeObservationWindow()
        recoveryUnconfirmed = wasRecovering && completionEvents.isEmpty && engine.activeKind != nil
        handle(completionEvents)
        if calibrationSession == nil {
            let explanation = completionEvents.contains(.reminder(.distance)) ? "本轮已确认偏近" : pendingDecision
            let outcome = distanceDelivery ?? (quiet ? "安静模式已拦截弹窗" : (isPaused ? "暂停期间不弹窗" : explanation))
            lastDistanceDecision = outcome
            var report: [String: Any] = ["checkedAt": Date().timeIntervalSince1970, "samples": scanObservation.receivedSamples,
                "validSamples": scanObservation.validSamples, "decision": explanation, "delivery": outcome,
                "followUp": engine.distanceReminderLevel.rawValue]
            if let sample = scanObservation.lastValidSample, let offset = engine.calibration?.distanceOffsetCM(for: sample) { report["offsetCM"] = offset }
            defaults.set(report, forKey: "qx.lastScanDecision")
        }
        if let calibrationSession {
            let succeeded = calibrationComplete
            let postureFailure = calibrationSession.headFailureMessage ?? scanObservation.headFailureMessage ?? "头部角度尚未稳定，距离参考仍可使用。"
            let failure: String
            if scanObservation.receivedSamples == 0 {
                failure = scanObservation.failureMessage!
            } else if calibrationSession.validSampleCount == 0 && !observationMessage.isEmpty {
                failure = observationMessage
            } else { failure = calibrationSession.failureMessage }
            cancelCalibration()
            if !succeeded {
                wantedCamera = false
                defaults.set(false, forKey: "qx.checksStarted")
                calibrationIssue = failure
                observationMessage = failure
                show(.init(kind: .welcome, title: "校准尚未完成", message: failure + " 摄像头已关闭。"))
            } else {
                if experimentalPosture && !hasHeadReference { postureCalibrationIssue = postureFailure }
                let message = experimentalPosture && !hasHeadReference ? "距离已保存；\(postureFailure) 摄像头已关闭。" : "距离和已识别的头部参考已保存，摄像头已关闭。"
                show(.init(kind: .welcome, title: "认识你啦，校准完成", message: message))
            }
        }
        scheduleNextScan()
    }

    private func rememberStartedChecks() {
        guard wantedCamera, automaticChecks, calibrationSession == nil, !selectedCameraID.isEmpty,
              let reference = savedCalibration, reference.referenceDistanceCM != nil,
              reference.cameraID.hasPrefix(selectedCameraID + ":") else { return }
        defaults.set(true, forKey: "qx.checksStarted")
    }
    private func scheduleNextScan() {
        rememberStartedChecks()
        nextCheckAt = wantedCamera && automaticChecks && !isPaused && !isResting ? Date().addingTimeInterval(engine.nextCheckInterval) : nil
    }

    func handle(_ events: [ReminderEvent]) {
        for event in events {
            switch event {
            case .reminder(.distance):
                showDistanceReminder(level: max(.gentle, engine.distanceReminderLevel))
                if wantedCamera && automaticChecks && !isPaused && !isResting {
                    let check = Date().addingTimeInterval(engine.nextCheckInterval)
                    nextCheckAt = min(nextCheckAt ?? check, check)
                }
            case .reminder(.posture):
                switch engine.activePostureChange {
                case .headDown: show(.init(kind: .posture, title: "抬抬头，脖子放个假～", message: "低头比参考明显了，轻轻抬回舒服的看屏角度，保持一下。", expression: .headDown))
                case .headTilt: show(.init(kind: .posture, title: "小脑袋，扶正一下～", message: "头部比参考更侧倾，轻轻回正，放松着看屏幕。", expression: .headTilt))
                default: show(.init(kind: .posture, title: "小脑袋，归位啦～", message: "头部相对双肩的位置有变化，轻轻回到舒服的参考姿势。", expression: .posture))
                }
            case .reminder(.rest):
                cancelDemo()
                showRestReminder(level: strongRestReminders ? restUrgency : .due)
            case .adjusted:
                adjustments += 1
                persistTotals()
                scheduleNextScan()
                show(.init(kind: .reward, title: "调整成功，舒服多了！", message: "今天已主动调整 \(adjustments) 次" + (wantedCamera && automaticChecks ? " · 已恢复半小时检测" : ""), rewardKind: .adjustment))
            case .rested:
                rests += 1
                persistTotals()
                show(.init(kind: .reward, title: "满血状态，充能完成！", message: "健康环已充满 · 今天完成 \(rests) 次休息", rewardKind: .rest))
            }
        }
    }

    private func show(_ value: BuddyNotice) {
        guard !quiet, !isPaused, calibrationSession == nil || value.kind == .rest else { return }
        if notice?.kind == .rest && value.kind != .rest { return }
        notice = value
        onNotice?(value)
    }

    func expireNotice(id: UUID) {
        guard let notice, notice.id == id else { return }
        if notice.kind == .distance, !notice.isDemo {
            let outcome = "距离弹窗已自动收起（30 秒）"
            lastDistanceDecision = outcome
            if var report = defaults.dictionary(forKey: "qx.lastScanDecision") {
                report["delivery"] = outcome
                defaults.set(report, forKey: "qx.lastScanDecision")
            }
        }
        hideNotice()
    }

    func hideNotice() { notice = nil; onNotice?(nil) }
    private func hideNonRestNotice() {
        if notice?.isPersistentRest != true { hideNotice() }
    }
    func dismissReminder() {
        if notice?.isDemo == true { cancelDemo(); return }
        buddyResultDismissed = true
        engine.dismiss()
        hideNotice()
        scheduleNextScan()
    }
    func snooze() {
        if notice?.isDemo == true { cancelDemo(); return }
        let now = Date()
        if notice?.kind == .rest {
            engine.snoozeRest(at: now)
            restUrgency = .none
            hideNotice()
            return
        }
        if notice?.kind == .distance || (notice?.kind == .recovering && distanceFollowUpActive) {
            if cameraActive || cameraBusy {
                activationGeneration += 1
                stopCapture(preservingDistanceFollowUp: true)
            } else { engine.endObservationWindow() }
            hideNotice()
            scheduleNextScan()
            return
        }
        engine.snooze(at: now)
        if wantedCamera && automaticChecks && !isPaused && !isResting { nextCheckAt = now.addingTimeInterval(300) }
        hideNotice()
    }

    func tryDemo(expression: BuddyExpression = .tooClose) {
        guard canPreviewRestReminder else { return }
        if expression == .tooClose { tryDistanceDemo(); return }
        if expression == .restDue { tryRestDemo(); return }
        cancelDemo()
        demoRunning = expression != .happy
        let kind: BuddyNotice.Kind = expression == .happy ? .reward : (expression == .tooClose ? .distance : ([.headDown, .headTilt, .posture].contains(expression) ? .posture : .demo))
        show(.init(kind: kind, title: expression.title, message: "这是猫头鹰表情演示，不会开启摄像头，也不计入真实次数。", isDemo: true, expression: expression, rewardKind: kind == .reward ? .adjustment : nil))
    }
    func tryRestDemo(level: RestReminderLevel = .due) {
        guard canPreviewRestReminder else { return }
        cancelDemo()
        demoRunning = true
        showRestReminder(level: level, isDemo: true)
    }
    func advanceRestDemo() {
        guard notice?.isDemo == true, notice?.kind == .rest, strongRestReminders else { return }
        tryRestDemo(level: notice?.restLevel == .due ? .overdue : .urgent)
    }
    func completeDemo() {
        guard demoRunning else { return }
        let wasRest = notice?.kind == .rest
        hideNotice()
        demoRunning = false
        show(.init(kind: .reward, title: wasRest ? "满血状态，充能完成！" : "调整成功，舒服多了！",
            message: "奖励演示 · 不计入真实次数", isDemo: true, rewardKind: wasRest ? .rest : .adjustment))
    }
    func closeNotice() {
        if notice?.isDemo == true { cancelDemo() }
        else if notice?.kind == .rest || notice?.kind == .distance { snooze() }
        else { hideNotice() }
    }
    func tryDistanceDemo(level: DistanceReminderLevel = .gentle) {
        guard canPreviewRestReminder else { return }
        cancelDemo()
        demoRunning = true
        showDistanceReminder(level: level, isDemo: true)
    }
    func advanceDistanceDemo() {
        guard let notice, notice.kind == .distance, notice.isDemo, notice.distanceLevel < .urgent else { return }
        tryDistanceDemo(level: notice.distanceLevel.advanced)
    }
    private func showDistanceReminder(level: DistanceReminderLevel, isDemo: Bool = false) {
        let title: String
        let message: String
        switch level {
        case .none, .gentle:
            title = "靠太近啦，往后一点点"
            message = "比固定参考靠近约 5 cm 了，轻轻往后靠一点。"
        case .firm:
            title = "还是有点近，给眼睛腾点空间"
            message = "这次复查仍然偏近。先把身体轻轻靠回舒服的位置，再复查 5 秒。"
        case .urgent:
            title = "先往后靠，我们再确认一次"
            message = "已经多次确认距离偏近。现在靠回舒服的位置，稳定下来再复查；也可以稍后再查。"
        }
        let scheduleDetail = isDemo ? " 演示不启动摄像头，不记录真实次数。" : (automaticChecks && wantedCamera ? " 接下来每 5 分钟复查，确认恢复后改回半小时。" : " 自动检测已关闭，请手动复查。")
        let value = BuddyNotice(kind: .distance, title: title, message: message + scheduleDetail, isDemo: isDemo, distanceLevel: level)
        show(value)
        if !isDemo {
            if notice?.id == value.id { distanceDelivery = "已发出距离提醒，等待窗口显示" }
            else if quiet { distanceDelivery = "安静模式已拦截弹窗" }
            else if isPaused { distanceDelivery = "暂停期间不弹窗" }
            else if notice?.kind == .rest { distanceDelivery = "休息提醒优先，距离提醒未覆盖它" }
            else { distanceDelivery = "当前校准或休息状态拦截了弹窗" }
        }
    }
    private func showRestReminder(level: RestReminderLevel, isDemo: Bool = false) {
        let title: String
        let message: String
        switch level {
        case .none, .due:
            title = "陪我去倒杯水？"
            message = "休息时间到啦，离开屏幕 \(Int(breakMinutes)) 分钟，给眼睛和肩膀松口气。"
        case .overdue:
            title = "小猫头鹰已经伸翅膀啦～"
            message = "休息计划已超时。带我离开屏幕 \(Int(breakMinutes)) 分钟，把健康环补满吧。"
        case .urgent:
            title = "这一小局，先暂停一下"
            message = "休息计划已经超时一会儿了。现在起身走两步，\(Int(breakMinutes)) 分钟后再回来。"
        }
        show(.init(kind: .rest, title: title, message: message, isDemo: isDemo, restLevel: level))
    }
    private func cancelDemo() {
        demoRunning = false
        if notice?.isDemo == true { hideNotice() }
    }

    func clearLocalData() {
        disableCamera()
        hideNotice()
        manualTimerRunning = false
        engine.resetWork()
        engine.calibration = nil
        savedCalibration = nil
        postureCalibrationIssue = nil
        adjustments = 0
        rests = 0
        quiet = false
        strongRestReminders = true
        restUrgency = .none
        buddyResultDismissed = false
        workMinutes = 45
        breakMinutes = 5
        experimentalPosture = true
        automaticChecks = true
        selectedCameraID = ""
        pauseUntil = nil
        isResting = false
        restCompleted = false
        workDuration = 0
        restRemaining = 0
        engine.cancelRest()
        lastCheckedAt = nil
        completedScan = nil
        lastDistanceDecision = nil
        calibrationIssue = nil
        cameraIntroSeen = false
        theme = .mist
        ["quiet", "restMinutes", "breakMinutes", "posture", "camera", "calibration", "day", "adjustments", "rests", "automaticChecks", "checksStarted", "cameraIntroSeen", "shoulderDiagnostic", "restEmphasis", "lastScanDecision", "theme"].forEach {
            defaults.removeObject(forKey: "qx.\($0)")
        }
    }

    func openCameraPermissions() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    func shutdown() { clock?.invalidate(); activationGeneration += 1; wantedCamera = false; detector.stopSynchronously() }

    private func persistTotals() {
        defaults.set(day, forKey: "qx.day")
        defaults.set(adjustments, forKey: "qx.adjustments")
        defaults.set(rests, forKey: "qx.rests")
    }
    private static func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
