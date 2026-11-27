import Foundation
import AppKit
import Combine
import WireGuardLimiterCore

final class AppModel: ObservableObject {
    let settings = AppSettings()
    let tunnelService = TunnelService()
    let notifier = Notifier()
    let sessions: SessionManager

    private var bag = Set<AnyCancellable>()
    private var timer: Timer?

    init() {
        sessions = SessionManager(settings: settings, control: tunnelService, notifier: notifier)
        notifier.extensionLength = { [settings] in settings.extensionLength }
        notifier.onAction = { [weak self] action, id in
            switch action {
            case .extend: self?.sessions.extend(id: id)
            case .disconnect: self?.sessions.disconnect(id: id)
            }
        }
        tunnelService.onChange = { [weak self] tunnels in
            self?.sessions.update(tunnels: tunnels)
            self?.objectWillChange.send()
        }
        // Forward nested changes so views redraw.
        sessions.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        // Clear stale notifications when a session ends.
        sessions.$sessions.scan(([String](), [String]())) { ($0.1, Array($1.keys)) }
            .sink { [weak self] old, new in old.filter { !new.contains($0) }.forEach { self?.notifier.clear(id: $0) } }
            .store(in: &bag)

        notifier.start()
        tunnelService.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sessions.tick() }
        timer?.tolerance = 0.2
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.tunnelService.rescan()
            self?.sessions.tick()
        }
    }

    // MARK: Menu bar label

    var iconName: String { sessions.sessions.isEmpty ? "lock.open" : "lock.fill" }

    var labelText: String? {
        guard let rem = sessions.sessions.keys.compactMap({ sessions.remaining(id: $0) }).min() else { return nil }
        return rem >= 0 ? formatDuration(rem + 30 > 60 ? rem.rounded(.up) : rem) : "+" + formatDuration(-rem)
    }
}
