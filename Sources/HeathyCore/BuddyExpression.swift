public enum BuddyExpression: String, CaseIterable {
    case calm, checking, tooClose, headDown, headTilt, posture, restDue, resting, happy, unclear, paused

    public static func reminder(_ kind: ReminderKind, change: PostureChange? = nil) -> BuddyExpression {
        switch kind {
        case .distance: return .tooClose
        case .rest: return .restDue
        case .posture:
            switch change {
            case .headDown: return .headDown
            case .headTilt: return .headTilt
            default: return .posture
            }
        }
    }
    public static func result(distanceWarning: Bool, posture: PostureAssessment) -> BuddyExpression {
        if distanceWarning { return .tooClose }
        if case .changed(let change) = posture { return reminder(.posture, change: change) }
        return .calm
    }
}
