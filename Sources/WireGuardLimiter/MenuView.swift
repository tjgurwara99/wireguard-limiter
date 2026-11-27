import SwiftUI
import WireGuardLimiterCore

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let tunnels = model.tunnelService.tunnels
        if tunnels.isEmpty { Text("No WireGuard tunnels found") }
        ForEach(tunnels) { t in
            section(t)
            Divider()
        }
        Button("Settings…") { SettingsWindow.show(settings: model.settings) }
            .keyboardShortcut(",")
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private func section(_ t: Tunnel) -> some View {
        let sessions = model.sessions
        let ext = model.settings.extensionMin
        switch t.status {
        case .connected:
            Text(header(t))
            Button("Disconnect") { sessions.disconnect(id: t.id) }
            if let s = sessions.sessions[t.id], s.canExtend(now: Date()) {
                Button("Extend +\(formatDuration(TimeInterval(ext * 60)))") { sessions.extend(id: t.id) }
            }
        case .disconnected:
            Text("\(t.name) — Disconnected")
            Button("Connect") { sessions.connect(id: t.id) }
            Menu("Connect for") {
                ForEach([30, 60, 120, 240], id: \.self) { m in
                    Button(formatDuration(TimeInterval(m * 60))) { sessions.connect(id: t.id, limit: TimeInterval(m * 60)) }
                }
            }
        default:
            Text("\(t.name) — \(t.status.label)")
        }
    }

    private func header(_ t: Tunnel) -> String {
        guard let s = model.sessions.sessions[t.id] else { return "\(t.name) — Connected" }
        let now = Date()
        let rem = s.deadline.timeIntervalSince(now)
        let left = rem >= 0 ? "\(formatDuration(rem)) left" : "\(formatDuration(-rem)) over"
        return "\(t.name) — Connected \(formatClock(now.timeIntervalSince(s.connectedAt))) · \(left)"
    }
}
