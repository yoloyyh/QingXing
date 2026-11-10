public enum DistanceReminderLevel: Int, Comparable, CaseIterable {
    case none, gentle, firm, urgent
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var advanced: Self { Self(rawValue: min(Self.urgent.rawValue, rawValue + 1))! }
}
