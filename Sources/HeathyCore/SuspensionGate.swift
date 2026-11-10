public enum SuspensionReason: Hashable { case screenLock, sleep }

public struct SuspensionGate {
    private var reasons: Set<SuspensionReason> = []
    public var isSuspended: Bool { !reasons.isEmpty }
    public init() {}
    public mutating func suspend(_ reason: SuspensionReason) { reasons.insert(reason) }
    public mutating func resume(_ reason: SuspensionReason) { reasons.remove(reason) }
}
