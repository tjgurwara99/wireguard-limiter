import Foundation
import Combine

public struct Session: Codable, Equatable {
    public var id: String
    public var name: String
    public var connectedAt: Date
    public var deadline: Date
    public var hardDeadline: Date?
    var lastReminder: Date?
    var warned = false
    var hardWarned = false

    public func canExtend(now: Date) -> Bool {
        guard let hard = hardDeadline else { return true }
        return now < hard && deadline < hard
    }
}

public final class SessionManager: ObservableObject {
    public static let hardWarning: TimeInterval = 5 * 60

    @Published public private(set) var sessions: [String: Session] = [:]
    /// Bumped every tick so views refresh countdowns.
    @Published public private(set) var now: Date

    private let settings: AppSettings
    private let defaults: UserDefaults
    private let clock: () -> Date
    private weak var control: TunnelControlling?
    private weak var notifier: Notifying?
    private var pendingLimits: [String: TimeInterval] = [:]
    private let storeKey = "sessions"

    public init(settings: AppSettings, control: TunnelControlling?, notifier: Notifying?,
                defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.control = control
        self.notifier = notifier
        self.defaults = defaults
        self.clock = clock
        self.now = clock()
        if let data = defaults.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([String: Session].self, from: data) {
            sessions = saved
        }
    }

    public func attach(control: TunnelControlling, notifier: Notifying) {
        self.control = control
        self.notifier = notifier
    }

    // MARK: Tunnel events

    /// Reconcile sessions with the current tunnel list (call on launch and every status change).
    public func update(tunnels: [Tunnel]) {
        let t = clock()
        var changed = false
        let byID = Dictionary(uniqueKeysWithValues: tunnels.map { ($0.id, $0) })
        // Drop sessions whose tunnel is no longer connected (or was removed).
        for id in Array(sessions.keys) where byID[id]?.status != .connected {
            sessions[id] = nil; changed = true
        }
        for tun in tunnels where tun.status == .connected {
            if sessions[tun.id] == nil {
                let limit = pendingLimits.removeValue(forKey: tun.id) ?? settings.defaultLimit
                sessions[tun.id] = makeSession(id: tun.id, name: tun.name, start: t, limit: limit)
                changed = true
            } else if sessions[tun.id]?.name != tun.name {
                sessions[tun.id]?.name = tun.name; changed = true
            }
        }
        if changed { persist() }
        now = t
    }

    private func makeSession(id: String, name: String, start: Date, limit: TimeInterval) -> Session {
        var hard = settings.hardCap.map { start.addingTimeInterval($0) }
        var deadline = start.addingTimeInterval(limit)
        if let h = hard, deadline > h { deadline = h }
        if settings.hardCap == nil { hard = nil }
        return Session(id: id, name: name, connectedAt: start, deadline: deadline, hardDeadline: hard)
    }

    // MARK: User actions

    public func connect(id: String, limit: TimeInterval? = nil) {
        pendingLimits[id] = limit ?? settings.defaultLimit
        control?.connect(id: id)
    }

    public func disconnect(id: String) {
        control?.disconnect(id: id)
    }

    @discardableResult
    public func extend(id: String) -> Bool {
        guard var s = sessions[id] else { return false }
        let t = clock()
        guard s.canExtend(now: t) else { return false }
        var d = max(s.deadline, t).addingTimeInterval(settings.extensionLength)
        if let h = s.hardDeadline, d > h { d = h }
        s.deadline = d
        s.lastReminder = nil
        s.warned = false
        sessions[id] = s
        persist()
        now = t
        return true
    }

    // MARK: Timer

    /// Call about once a second and on wake.
    public func tick() {
        let t = clock()
        defer { now = t }
        var changed = false
        for (id, var s) in sessions {
            let before = s
            evaluate(&s, at: t)
            if s != before { sessions[id] = s; changed = true }
        }
        if changed { persist() }
    }

    private func evaluate(_ s: inout Session, at t: Date) {
        // Hard cap always wins.
        if let hard = s.hardDeadline {
            if t >= hard {
                if let last = s.lastReminder, t.timeIntervalSince(last) < 30 { return }
                s.lastReminder = t
                control?.disconnect(id: s.id)
                notifier?.disconnected(name: s.name, reason: "Hard cap reached")
                return
            }
            if !s.hardWarned, t >= hard.addingTimeInterval(-Self.hardWarning) {
                s.hardWarned = true
                notifier?.warning(id: s.id, name: s.name, remaining: hard.timeIntervalSince(t), canExtend: false)
            }
        }

        switch settings.action {
        case .notify:
            guard t >= s.deadline else { return }
            if let last = s.lastReminder, t.timeIntervalSince(last) < settings.reminder { return }
            s.lastReminder = t
            notifier?.limitReached(id: s.id, name: s.name,
                                   elapsed: t.timeIntervalSince(s.connectedAt),
                                   canExtend: s.canExtend(now: t))
        case .disconnect:
            if t >= s.deadline {
                if let last = s.lastReminder, t.timeIntervalSince(last) < 30 { return }
                s.lastReminder = t
                control?.disconnect(id: s.id)
                notifier?.disconnected(name: s.name, reason: "Time limit reached")
            } else if settings.warning > 0, !s.warned, !(s.hardWarned && s.deadline >= (s.hardDeadline ?? .distantFuture)), t >= s.deadline.addingTimeInterval(-settings.warning) {
                s.warned = true
                notifier?.warning(id: s.id, name: s.name, remaining: s.deadline.timeIntervalSince(t),
                                  canExtend: s.canExtend(now: t))
            }
        }
    }

    // MARK: Display helpers

    /// Remaining until the deadline (negative when overdue).
    public func remaining(id: String) -> TimeInterval? {
        sessions[id].map { $0.deadline.timeIntervalSince(now) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) { defaults.set(data, forKey: storeKey) }
    }
}
