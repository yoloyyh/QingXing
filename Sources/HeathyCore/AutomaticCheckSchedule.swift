import Foundation

public enum AutomaticCheckSchedule {
    public static let interval: TimeInterval = 30 * 60
    public static func restoredCheck(at now: Date, previouslyEnabled: Bool, automatic: Bool, authorized: Bool, hasReference: Bool) -> Date? {
        guard previouslyEnabled, automatic, authorized, hasReference else { return nil }
        return now.addingTimeInterval(interval)
    }
}
