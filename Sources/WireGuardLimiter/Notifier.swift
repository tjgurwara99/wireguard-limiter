import Foundation
import UserNotifications
import WireGuardLimiterCore

final class Notifier: NSObject, Notifying, UNUserNotificationCenterDelegate {
    enum Action: String { case extend = "EXTEND", disconnect = "DISCONNECT" }

    var onAction: ((Action, String) -> Void)?
    var extensionLength: () -> TimeInterval = { 1800 }

    // UNUserNotificationCenter crashes without a bundle (e.g. `swift run`).
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func start() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        registerCategories()
    }

    private func registerCategories() {
        let ext = UNNotificationAction(identifier: Action.extend.rawValue,
                                       title: "Extend +\(formatDuration(extensionLength()))", options: [])
        let off = UNNotificationAction(identifier: Action.disconnect.rawValue, title: "Disconnect", options: [.destructive])
        let offNow = UNNotificationAction(identifier: Action.disconnect.rawValue, title: "Disconnect now", options: [.destructive])
        center?.setNotificationCategories([
            UNNotificationCategory(identifier: "limit", actions: [ext, off], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "warn", actions: [ext, offNow], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "noext", actions: [offNow], intentIdentifiers: [], options: []),
        ])
    }

    private func post(id: String, title: String, body: String, category: String?) {
        guard let center else { return }
        registerCategories()
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        c.userInfo = ["tunnelID": id]
        if let category { c.categoryIdentifier = category }
        center.add(UNNotificationRequest(identifier: "wg-\(id)", content: c, trigger: nil))
    }

    func limitReached(id: String, name: String, elapsed: TimeInterval, canExtend: Bool) {
        post(id: id, title: "\(name) has been connected for \(formatDuration(elapsed))",
             body: canExtend ? "Extend or disconnect?" : "Hard cap reached.",
             category: canExtend ? "limit" : "noext")
    }

    func warning(id: String, name: String, remaining: TimeInterval, canExtend: Bool) {
        post(id: id, title: "\(name) disconnects in \(formatDuration(remaining))",
             body: canExtend ? "Extend or disconnect now?" : "Hard cap — can't be extended.",
             category: canExtend ? "warn" : "noext")
    }

    func disconnected(name: String, reason: String) {
        post(id: "bye-\(name)", title: "Disconnected \(name)", body: reason, category: nil)
    }

    func clear(id: String) {
        center?.removeDeliveredNotifications(withIdentifiers: ["wg-\(id)"])
    }

    // MARK: Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if let action = Action(rawValue: response.actionIdentifier),
           let id = response.notification.request.content.userInfo["tunnelID"] as? String {
            DispatchQueue.main.async { self.onAction?(action, id) }
        }
        done()
    }
}
