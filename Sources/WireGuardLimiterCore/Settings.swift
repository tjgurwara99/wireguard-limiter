import Foundation
import Combine

public enum LimitAction: String, CaseIterable, Identifiable {
    case notify, disconnect
    public var id: String { rawValue }
    public var label: String {
        self == .notify ? "Notify with Extend button" : "Disconnect automatically"
    }
}

/// UserDefaults-backed settings. All durations are stored in minutes.
public final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published public var defaultLimitMin: Int { didSet { defaults.set(defaultLimitMin, forKey: "defaultLimitMin") } }
    @Published public var action: LimitAction { didSet { defaults.set(action.rawValue, forKey: "action") } }
    @Published public var reminderMin: Int { didSet { defaults.set(reminderMin, forKey: "reminderMin") } }
    @Published public var warningMin: Int { didSet { defaults.set(warningMin, forKey: "warningMin") } }
    @Published public var extensionMin: Int { didSet { defaults.set(extensionMin, forKey: "extensionMin") } }
    @Published public var hardCapEnabled: Bool { didSet { defaults.set(hardCapEnabled, forKey: "hardCapEnabled") } }
    @Published public var hardCapMin: Int { didSet { defaults.set(hardCapMin, forKey: "hardCapMin") } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func int(_ k: String, _ d: Int) -> Int { defaults.object(forKey: k) as? Int ?? d }
        defaultLimitMin = int("defaultLimitMin", 60)
        action = LimitAction(rawValue: defaults.string(forKey: "action") ?? "") ?? .notify
        reminderMin = int("reminderMin", 15)
        warningMin = int("warningMin", 5)
        extensionMin = int("extensionMin", 30)
        hardCapEnabled = defaults.object(forKey: "hardCapEnabled") as? Bool ?? true
        hardCapMin = int("hardCapMin", 480)
    }

    public var defaultLimit: TimeInterval { TimeInterval(defaultLimitMin * 60) }
    public var reminder: TimeInterval { TimeInterval(max(1, reminderMin) * 60) }
    public var warning: TimeInterval { TimeInterval(warningMin * 60) }
    public var extensionLength: TimeInterval { TimeInterval(extensionMin * 60) }
    public var hardCap: TimeInterval? { hardCapEnabled ? TimeInterval(hardCapMin * 60) : nil }
}
