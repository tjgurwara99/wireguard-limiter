# WireGuard Limiter

A small wrapper around the wireguard utilities that allow us to connects/disconnects WireGuard tunnels and limit them on how long they stay up and connected.

    ./scripts/build-app.sh && cp -R build/WireGuardLimiter.app /Applications/

- `swift run CoreChecks` runs the session-logic checks (XCTest isn't available with Command Line Tools only).
- `.build/debug/WireGuardLimiter --list` prints detected tunnels (read-only).
