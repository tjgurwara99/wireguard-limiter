import SwiftUI
import ServiceManagement
import WireGuardLimiterCore

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            SnapStepper("Default limit: \(settings.defaultLimitMin) min", value: $settings.defaultLimitMin, in: 1...1440, step: 5)
            Picker("When limit is reached", selection: $settings.action) {
                ForEach(LimitAction.allCases) { Text($0.label).tag($0) }
            }
            if settings.action == .notify {
                Stepper("Reminder every: \(settings.reminderMin) min", value: $settings.reminderMin, in: 1...240)
            } else {
                Stepper("Warn before disconnect: \(settings.warningMin == 0 ? "off" : "\(settings.warningMin) min")",
                        value: $settings.warningMin, in: 0...60)
            }
            SnapStepper("Extension length: \(settings.extensionMin) min", value: $settings.extensionMin, in: 1...480, step: 5)
            Toggle("Hard cap", isOn: $settings.hardCapEnabled)
            if settings.hardCapEnabled {
                SnapStepper("Hard cap length: \(formatDuration(TimeInterval(settings.hardCapMin * 60)))",
                            value: $settings.hardCapMin, in: 10...1440, step: 30)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 380)
    }
}

/// Like Stepper(step:), but steps land on multiples of `step` (1 -> 5 -> 10, not 1 -> 6 -> 11).
/// Values below the first multiple are still reachable at the range's lower bound.
struct SnapStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>, step: Int) {
        self.title = title; self._value = value; self.range = range; self.step = step
    }

    var body: some View {
        Stepper(title,
                onIncrement: { value = min(range.upperBound, (value / step + 1) * step) },
                onDecrement: { value = max(range.lowerBound, value % step == 0 ? value - step : (value / step) * step) })
    }
}
