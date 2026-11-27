import Foundation

// Read-only probe: `WireGuardLimiter --list`
if CommandLine.arguments.contains("--list") {
    for s in TunnelService.listServices() { print(s.id, s.name) }
    exit(0)
}
WireGuardLimiterApp.main()
