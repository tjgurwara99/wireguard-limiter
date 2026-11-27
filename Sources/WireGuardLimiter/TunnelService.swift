import Foundation
import SystemConfiguration
import Combine
import WireGuardLimiterCore

private let provider = "com.wireguard.macos"

private final class Box { weak var service: TunnelService?; let id: String
    init(_ s: TunnelService, _ id: String) { service = s; self.id = id } }

private func statusCallback(_ conn: SCNetworkConnection, _ status: SCNetworkConnectionStatus, _ info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
    DispatchQueue.main.async { box.service?.refreshStatus(id: box.id) }
}

/// Lists WireGuard VPN services via SystemConfiguration and controls them.
final class TunnelService: ObservableObject, TunnelControlling {
    @Published private(set) var tunnels: [Tunnel] = []
    /// Called on the main thread after any change to the list or statuses.
    var onChange: (([Tunnel]) -> Void)?

    private var connections: [String: SCNetworkConnection] = [:]
    private var boxes: [String: Unmanaged<Box>] = [:]
    private var initial: [String: TunnelStatus] = [:]
    private var rescanTimer: Timer?

    func start() {
        rescan()
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.rescan() }
    }

    static func status(of conn: SCNetworkConnection) -> TunnelStatus {
        switch SCNetworkConnectionGetStatus(conn) {
        case .connected: return .connected
        case .connecting: return .connecting
        case .disconnecting: return .disconnecting
        case .disconnected: return .disconnected
        default: return .invalid
        }
    }

    /// Enumerate (id, name) of WireGuard services.
    static func listServices() -> [(id: String, name: String)] {
        guard let prefs = SCPreferencesCreate(nil, "WireGuardLimiter" as CFString, nil),
              let all = SCNetworkServiceCopyAll(prefs) as? [SCNetworkService] else { return [] }
        var out: [(String, String)] = []
        for svc in all {
            guard let iface = SCNetworkServiceGetInterface(svc),
                  (SCNetworkInterfaceGetInterfaceType(iface) as String?) == "VPN",
                  let id = SCNetworkServiceGetServiceID(svc) as String? else { continue }
            // Third-party VPNs expose the provider bundle id as the interface subtype.
            let sub = SCNetworkInterfaceGetInterfaceType(SCNetworkInterfaceGetInterface(iface) ?? iface) as String?
            let isWG = sub == provider || vpnProvider(serviceID: id) == provider
            guard isWG else { continue }
            out.append((id, (SCNetworkServiceGetName(svc) as String?) ?? id))
        }
        return out.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    /// Fallback: read provider from `scutil --nc list`.
    private static func vpnProvider(serviceID: String) -> String? {
        scutilList().first { $0.id == serviceID }?.provider
    }

    private static func scutilList() -> [(id: String, provider: String)] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        p.arguments = ["--nc", "list"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").compactMap { line in
            guard let r = line.range(of: #"[0-9A-F]{8}-[0-9A-F-]{27}"#, options: .regularExpression),
                  let pr = line.range(of: #"\(([^)]+)\)\s+""#, options: .regularExpression) else { return nil }
            let prov = line[pr].dropFirst().prefix { $0 != ")" }
            return (String(line[r]), String(prov))
        }
    }

    func rescan() {
        let services = Self.listServices()
        let ids = Set(services.map(\.id))
        for id in connections.keys where !ids.contains(id) { unwatch(id) }
        for s in services where connections[s.id] == nil { watch(s.id) }
        tunnels = services.compactMap { s in
            connections[s.id].map { Tunnel(id: s.id, name: s.name, status: initial.removeValue(forKey: s.id) ?? Self.status(of: $0)) }
        }
        onChange?(tunnels)
    }

    private func watch(_ id: String) {
        let box = Unmanaged.passRetained(Box(self, id))
        var ctx = SCNetworkConnectionContext(version: 0, info: box.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        guard let conn = SCNetworkConnectionCreateWithServiceID(nil, id as CFString, statusCallback, &ctx) else {
            box.release(); return
        }
        // Read before scheduling: right after scheduling the status reads as disconnected.
        initial[id] = Self.status(of: conn)
        SCNetworkConnectionScheduleWithRunLoop(conn, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        connections[id] = conn
        boxes[id] = box
    }

    private func unwatch(_ id: String) {
        if let c = connections[id] { SCNetworkConnectionUnscheduleFromRunLoop(c, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) }
        connections[id] = nil
        boxes[id]?.release(); boxes[id] = nil
    }

    func refreshStatus(id: String) {
        guard let conn = connections[id], let i = tunnels.firstIndex(where: { $0.id == id }) else { return }
        tunnels[i].status = Self.status(of: conn)
        onChange?(tunnels)
    }

    // MARK: TunnelControlling

    func connect(id: String) {
        if let c = connections[id], SCNetworkConnectionStart(c, nil, false) { return }
        runScutil("start", id)
    }

    func disconnect(id: String) {
        if let c = connections[id], SCNetworkConnectionStop(c, true) { return }
        runScutil("stop", id)
    }

    private func runScutil(_ verb: String, _ id: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        p.arguments = ["--nc", verb, id]
        try? p.run()
    }
}
