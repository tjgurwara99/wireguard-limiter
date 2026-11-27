import SwiftUI
import AppKit
import WireGuardLimiterCore

struct WireGuardLimiterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            MenuLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.iconName)
            if let t = model.labelText { Text(t) }
        }
    }
}

/// Settings window is hosted manually: SwiftUI's Settings scene is unreliable for menu-bar-only apps.
enum SettingsWindow {
    private static var window: NSWindow?
    static func show(settings: AppSettings) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            w.title = "WireGuard Limiter Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 440, height: 380))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
