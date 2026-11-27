// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WireGuardLimiter",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (settings, sessions) so it can be unit tested with a fake clock.
        .target(name: "WireGuardLimiterCore"),
        .executableTarget(
            name: "WireGuardLimiter",
            dependencies: ["WireGuardLimiterCore"]
        ),
        // XCTest/Testing aren't available with Command Line Tools only,
        // so logic checks are a plain executable: `swift run CoreChecks`.
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["WireGuardLimiterCore"]
        ),
    ]
)
