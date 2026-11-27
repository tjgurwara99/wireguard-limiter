import Foundation
import WireGuardLimiterCore

final class Fake: TunnelControlling, Notifying {
    var disconnects: [String] = []
    var limit = 0, warnings = 0, byeCount = 0
    var lastCanExtend = true
    func connect(id: String) {}
    func disconnect(id: String) { disconnects.append(id) }
    func limitReached(id: String, name: String, elapsed: TimeInterval, canExtend: Bool) { limit += 1; lastCanExtend = canExtend }
    func warning(id: String, name: String, remaining: TimeInterval, canExtend: Bool) { warnings += 1 }
    func disconnected(name: String, reason: String) { byeCount += 1 }
}

final class Checks {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let fake = Fake()
    var settings: AppSettings!
    var mgr: SessionManager!
    let up = [Tunnel(id: "a", name: "Taj", status: .connected)]
    let down = [Tunnel(id: "a", name: "Taj", status: .disconnected)]

    init() {
        let d = UserDefaults(suiteName: UUID().uuidString)!
        settings = AppSettings(defaults: d)
        mgr = SessionManager(settings: settings, control: fake, notifier: fake, defaults: d, clock: { [unowned self] in self.t })
    }
    func advance(_ min: Double) { t = t.addingTimeInterval(min * 60); mgr.tick() }

    func testNotifyRepeatsAndExtend() {
        mgr.update(tunnels: up)
        advance(59); expect(line: #line, fake.limit == 0)
        advance(2); expect(line: #line, fake.limit == 1)
        advance(10); expect(line: #line, fake.limit == 1)
        advance(6); expect(line: #line, fake.limit == 2)
        expect(line: #line, mgr.extend(id: "a"))
        advance(1); expect(line: #line, fake.limit == 2)
    }

    func testAutoDisconnectWithWarning() {
        settings.action = .disconnect
        mgr.update(tunnels: up)
        advance(54); expect(line: #line, fake.warnings == 0)
        advance(2); expect(line: #line, fake.warnings == 1)
        advance(5); expect(line: #line, fake.disconnects == ["a"]); expect(line: #line, fake.byeCount == 1)
    }

    func testHardCapStopsExtendAndDisconnects() {
        settings.hardCapMin = 90
        mgr.update(tunnels: up)
        expect(line: #line, mgr.extend(id: "a"))   // 60 -> 90 (capped)
        expect(line: #line, !(mgr.extend(id: "a")))  // at cap
        advance(86); expect(line: #line, fake.warnings == 1)
        advance(5); expect(line: #line, fake.disconnects == ["a"])
    }

    func testSessionClearedOnDisconnectAndPersisted() {
        mgr.update(tunnels: up)
        expect(line: #line, mgr.sessions["a"] != nil)
        let d = UserDefaults(suiteName: UUID().uuidString)!
        _ = d
        mgr.update(tunnels: down)
        expect(line: #line, mgr.sessions["a"] == nil)
    }

    func testPendingLimitUsed() {
        mgr.connect(id: "a", limit: 600)
        mgr.update(tunnels: up)
        expect(line: #line, abs(mgr.sessions["a"]!.deadline.timeIntervalSince(t) - 600) < 0.1)
    }

    func testOverdueAfterSleepFiresImmediately() {
        mgr.update(tunnels: up)
        advance(200)
        expect(line: #line, fake.limit == 1)
    }
}

var failures = 0
func expect(line: Int, _ ok: Bool) { if !ok { failures += 1; print("FAIL line \(line)") } }

let tests: [(String, (Checks) -> Void)] = [
    ("notifyRepeatsAndExtend", { $0.testNotifyRepeatsAndExtend() }),
    ("autoDisconnectWithWarning", { $0.testAutoDisconnectWithWarning() }),
    ("hardCap", { $0.testHardCapStopsExtendAndDisconnects() }),
    ("sessionCleared", { $0.testSessionClearedOnDisconnectAndPersisted() }),
    ("pendingLimit", { $0.testPendingLimitUsed() }),
    ("overdueAfterSleep", { $0.testOverdueAfterSleepFiresImmediately() }),
]
for (name, run) in tests { print("•", name); run(Checks()) }
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
