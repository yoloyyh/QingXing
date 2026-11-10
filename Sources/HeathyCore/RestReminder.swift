public enum RestReminderLevel: Int, Comparable, CaseIterable {
    case none, due, overdue, urgent
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
