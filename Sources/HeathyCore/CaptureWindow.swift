import Foundation

public struct CaptureWindow {
    public static let duration: TimeInterval = 5
    public let startedAt: TimeInterval
    public init(startedAt: TimeInterval) { self.startedAt = startedAt }
    public func remaining(at uptime: TimeInterval) -> TimeInterval { max(0, min(Self.duration, Self.duration - (uptime - startedAt))) }
    public func hasExpired(at uptime: TimeInterval) -> Bool { uptime - startedAt >= Self.duration }
}
