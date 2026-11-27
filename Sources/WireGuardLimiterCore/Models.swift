import Foundation

public enum TunnelStatus: String, Codable {
    case disconnected, connecting, connected, disconnecting, invalid

    public var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting…"
        case .invalid: return "Unavailable"
        }
    }
}

public struct Tunnel: Identifiable, Equatable {
    public let id: String
    public var name: String
    public var status: TunnelStatus
    public init(id: String, name: String, status: TunnelStatus) {
        self.id = id; self.name = name; self.status = status
    }
}

public protocol TunnelControlling: AnyObject {
    func connect(id: String)
    func disconnect(id: String)
}

public protocol Notifying: AnyObject {
    /// Notify mode: limit reached (repeats). `canExtend` false once hard cap hit.
    func limitReached(id: String, name: String, elapsed: TimeInterval, canExtend: Bool)
    /// Auto mode: disconnect coming in `remaining` seconds.
    func warning(id: String, name: String, remaining: TimeInterval, canExtend: Bool)
    func disconnected(name: String, reason: String)
}

public func formatDuration(_ t: TimeInterval) -> String {
    let s = Int(max(0, t).rounded())
    let h = s / 3600, m = (s % 3600) / 60
    if h > 0 { return m == 0 ? "\(h)h" : "\(h)h \(m)m" }
    if m > 0 { return "\(m)m" }
    return "\(s)s"
}

public func formatClock(_ t: TimeInterval) -> String {
    let m = Int(max(0, t)) / 60
    return String(format: "%d:%02d", m / 60, m % 60)
}
