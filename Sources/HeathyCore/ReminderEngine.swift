import Foundation

public final class ReminderEngine {
    public var calibration: Calibration?
    public var restInterval: TimeInterval = 45 * 60
    public var restDuration: TimeInterval = 5 * 60
    public var postureEnabled = false {
        didSet {
            if !postureEnabled && (activeKind == .posture || pending == .posture) { suspend() }
        }
    }
    public private(set) var workDuration: TimeInterval = 0
    public private(set) var activeKind: ReminderKind?
    public private(set) var distanceReminderLevel: DistanceReminderLevel = .none
    public var nextCheckInterval: TimeInterval { distanceReminderLevel == .none ? AutomaticCheckSchedule.interval : 300 }
    public private(set) var activePostureChange: PostureChange?
    public private(set) var restStarted: Date?
    public private(set) var activeRestDuration: TimeInterval?
    private var lastTick: Date?
    private var lastSample: Date?
    private var pending: ReminderKind?
    private var pendingPostureChange: PostureChange?
    private var pendingSince: Date?
    private var pendingSamples = 0
    private var recoverySince: Date?
    private var recoverySamples = 0
    private var dismissedEpisode = false
    private var lastAlerts: [ReminderKind: Date] = [:]
    private var snoozedUntil: Date?
    private var lastRestLevel: RestReminderLevel = .none
    private var restSnoozedUntil: Date?
    private var distanceAlertIssuedInWindow = false

    public init() {}

    public func restReminderLevel(at time: Date) -> RestReminderLevel {
        guard restStarted == nil, workDuration >= restInterval,
              restSnoozedUntil.map({ time >= $0 }) ?? true else { return .none }
        let overdue = workDuration - restInterval
        if overdue >= 10 * 60 { return .urgent }
        if overdue >= 3 * 60 { return .overdue }
        return .due
    }
    public func snoozeRest(at time: Date) {
        restSnoozedUntil = time.addingTimeInterval(300)
        lastRestLevel = .none
    }
    public func rearmRestReminder() { lastRestLevel = .none }

    public var distanceDecisionExplanation: String {
        if dismissedEpisode { return "已选择这个判断不准，本轮未重新提醒" }
        if restStarted != nil { return "正在休息，未判断距离提醒" }
        if let last = lastSample, let until = snoozedUntil, last < until { return "提醒暂缓中" }
        if pending == .distance, let since = pendingSince, let last = lastSample {
            let seconds = max(0, last.timeIntervalSince(since))
            return "末尾连续偏近 \(pendingSamples) 个样本 / \(String(format: "%.1f", seconds)) 秒；尚未确认"
        }
        if activeKind == .distance { return "距离待复查，本轮未形成新的稳定偏近证据" }
        return "本轮未形成稳定偏近证据"
    }

    public func completeObservationWindow() -> [ReminderEvent] {
        // Only a naturally completed capture may confirm a stable tail. Never
        // combine separate scans, or treat cancellation / missing frames as proof.
        let confirmed = activeKind != nil && !dismissedEpisode && recoverySamples >= 4
            && recoverySince.flatMap { since in lastSample.map { $0.timeIntervalSince(since) >= 1.5 } } == true
        if confirmed {
            if activeKind == .distance {
                distanceReminderLevel = .none
                lastAlerts[.distance] = nil
            }
            activeKind = nil
            activePostureChange = nil
            dismissedEpisode = false
        }
        var events: [ReminderEvent] = confirmed ? [.adjusted] : []
        // The same bounded stable-tail rule applies to proximity alerts, not
        // just recovery: camera startup must not consume the whole proof window.
        if !confirmed, pending == .distance, pendingSamples >= 4,
           !dismissedEpisode, !distanceAlertIssuedInWindow,
           activeKind == nil || activeKind == .distance || activeKind == .posture,
           let since = pendingSince, let last = lastSample,
           last.timeIntervalSince(since) >= 1.5,
           snoozedUntil.map({ last >= $0 }) ?? true,
           activeKind == .distance || lastAlerts[.distance].map({ last.timeIntervalSince($0) >= 300 }) ?? true {
            distanceReminderLevel = activeKind == .distance ? distanceReminderLevel.advanced : .gentle
            activeKind = .distance
            activePostureChange = nil
            lastAlerts[.distance] = last
            events = [.reminder(.distance)]
        }
        endObservationWindow()
        return events
    }

    public func endObservationWindow() {
        distanceAlertIssuedInWindow = false
        pending = nil
        pendingPostureChange = nil
        pendingSince = nil; pendingSamples = 0
        recoverySince = nil; recoverySamples = 0
        lastSample = nil
    }

    public func isRecovering(_ sample: FrameFeatures) -> Bool {
        activeKind != nil && !dismissedEpisode && isRecovered(sample)
    }

    private func isRecovered(_ sample: FrameFeatures) -> Bool {
        guard sample.isValid, let reference = calibration,
              reference.isWithinRecoveryDistance(sample) else { return false }
        if activeKind == .distance { return true }
        if postureEnabled, reference.headReference != nil || reference.postureReference != nil {
            return PostureAssessment.isRecovered(sample, reference: reference, for: activePostureChange)
        }
        if activeKind == .posture && !sample.supportsPosture { return false }
        if let current = sample.faceShoulderRatio, let baseline = reference.faceShoulderRatio {
            return !postureEnabled || current / baseline < 1.10
        }
        return activeKind != .posture
    }

    public func observe(_ sample: FrameFeatures, at time: Date) -> [ReminderEvent] {
        if let previous = lastSample, time.timeIntervalSince(previous) > 3.5 {
            pending = nil
            pendingPostureChange = nil
            pendingSince = nil; pendingSamples = 0
            recoverySince = nil; recoverySamples = 0
        }
        lastSample = time
        guard sample.isValid, let reference = calibration, restStarted == nil else {
            pending = nil
            pendingPostureChange = nil
            pendingSince = nil; pendingSamples = 0
            recoverySince = nil; recoverySamples = 0
            return []
        }
        if let until = snoozedUntil, time < until { return [] }

        var kind: ReminderKind?
        var postureChange: PostureChange?
        if reference.isTooClose(sample) {
            kind = .distance
        } else if postureEnabled {
            if case .changed(let change) = PostureAssessment.evaluate(sample, reference: reference) { kind = .posture; postureChange = change }
        }

        // Hysteresis prevents jitter near the boundary from earning rewards.
        let recovered = isRecovered(sample)
        if recovered {
            pending = nil
            pendingPostureChange = nil
            pendingSince = nil; pendingSamples = 0
            if recoverySince == nil { recoverySince = time }
            recoverySamples += 1
            if time.timeIntervalSince(recoverySince!) >= 3 {
                let earned = activeKind != nil && !dismissedEpisode
                if activeKind == .distance {
                    distanceReminderLevel = .none
                    lastAlerts[.distance] = nil
                }
                activeKind = nil
                activePostureChange = nil
                dismissedEpisode = false
                if earned { return [.adjusted] }
            }
            return []
        }

        recoverySince = nil; recoverySamples = 0
        guard let kind else { pending = nil; pendingPostureChange = nil; pendingSince = nil; pendingSamples = 0; return [] }
        let repeatingDistance = activeKind == .distance && kind == .distance
        let supersedingPosture = activeKind == .posture && kind == .distance
        guard !dismissedEpisode, activeKind == nil || repeatingDistance || supersedingPosture else {
            pending = nil; pendingPostureChange = nil; pendingSince = nil; pendingSamples = 0
            return []
        }
        if repeatingDistance && distanceAlertIssuedInWindow { return [] }
        if pending != kind || pendingPostureChange != postureChange { pending = kind; pendingPostureChange = postureChange; pendingSince = time; pendingSamples = 0 }
        pendingSamples += 1
        let duration: TimeInterval = 3
        guard let since = pendingSince, time.timeIntervalSince(since) >= duration else { return [] }
        if !repeatingDistance, let last = lastAlerts[kind], time.timeIntervalSince(last) < 300 { return [] }
        if kind == .distance {
            distanceReminderLevel = repeatingDistance ? distanceReminderLevel.advanced : .gentle
            distanceAlertIssuedInWindow = true
        }
        lastAlerts[kind] = time
        activeKind = kind
        activePostureChange = postureChange
        return [.reminder(kind)]
    }

    public func tick(at time: Date, working: Bool) -> [ReminderEvent] {
        let previous = lastTick
        lastTick = time
        guard working, restStarted == nil else { lastTick = nil; lastRestLevel = .none; return [] }
        if let previous {
            let delta = time.timeIntervalSince(previous)
            if delta > 0 && delta <= 3.5 { workDuration += delta }
        }
        if let until = restSnoozedUntil, time >= until {
            restSnoozedUntil = nil
            lastRestLevel = .none
        }
        let level = restReminderLevel(at: time)
        guard level != lastRestLevel else { return [] }
        lastRestLevel = level
        guard level != .none else { return [] }
        return [.reminder(.rest)]
    }

    public func beginRest(at time: Date) {
        restStarted = time
        activeRestDuration = restDuration
        lastRestLevel = .none
        restSnoozedUntil = nil
        suspend(preservingDistanceFollowUp: true)
    }

    public func restRemaining(at time: Date) -> TimeInterval {
        guard let start = restStarted, let duration = activeRestDuration else { return 0 }
        return max(0, duration - time.timeIntervalSince(start))
    }

    public func finishRest(at time: Date) -> [ReminderEvent] {
        guard let start = restStarted, let duration = activeRestDuration,
              time.timeIntervalSince(start) >= duration else { return [] }
        restStarted = nil
        activeRestDuration = nil
        resetWork(preservingDistanceFollowUp: true)
        return [.rested]
    }

    public func cancelRest() { restStarted = nil; activeRestDuration = nil; lastTick = nil }

    public func resetWork(preservingDistanceFollowUp: Bool = false) {
        workDuration = 0
        lastTick = nil
        lastRestLevel = .none
        restSnoozedUntil = nil
        suspend(preservingDistanceFollowUp: preservingDistanceFollowUp)
    }

    public func dismiss() {
        distanceReminderLevel = .none
        distanceAlertIssuedInWindow = false
        if activeKind != nil { dismissedEpisode = true }
        activeKind = nil
        activePostureChange = nil
        pending = nil
        pendingPostureChange = nil
        pendingSince = nil; pendingSamples = 0
    }

    public func snooze(at time: Date) {
        if let activeKind { lastAlerts[activeKind] = nil }
        suspend()
        snoozedUntil = time.addingTimeInterval(300)
        restSnoozedUntil = time.addingTimeInterval(300)
        lastRestLevel = .none
    }

    public func suspend(preservingDistanceFollowUp: Bool = false) {
        let retainedDistance = preservingDistanceFollowUp && activeKind == .distance ? distanceReminderLevel : .none
        activeKind = nil
        activePostureChange = nil
        pending = nil
        pendingPostureChange = nil
        pendingSince = nil; pendingSamples = 0
        recoverySince = nil; recoverySamples = 0
        lastSample = nil
        lastTick = nil
        dismissedEpisode = false
        distanceReminderLevel = retainedDistance
        distanceAlertIssuedInWindow = false
        if retainedDistance != .none { activeKind = .distance }
    }
}
