// swift-tools-version: 6.4
import PackageDescription

// Shared Swift capability packages (drop-in architecture).
// Each capability X ships targets XInterface, XCore, XUI, XLive, XTesting and umbrella X;
// architecture.json declares every target and Scripts/arch-check enforces the layer rules.

/// Code moved from an app keeps the app's concurrency semantics (playground: Swift 6,
/// default MainActor isolation, approachable-concurrency upcoming features).
let appIsolation: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "swift-packages",
    defaultLocalization: "en",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "VoiceCommand", targets: ["VoiceCommand"]),
        .library(name: "VoiceCommandCore", targets: ["VoiceCommandCore"]),
        .library(name: "VoiceCommandInterface", targets: ["VoiceCommandInterface"]),
        .library(name: "VoiceCommandTesting", targets: ["VoiceCommandTesting"]),
    ],
    dependencies: [],
    targets: [
        // MARK: VoiceCommand — trigger word + spoken commands (Live and UI are iOS-only)
        .target(name: "VoiceCommandInterface", swiftSettings: appIsolation),
        .target(name: "VoiceCommandCore", dependencies: ["VoiceCommandInterface"], swiftSettings: appIsolation),
        .target(name: "VoiceCommandUI", dependencies: ["VoiceCommandCore", "VoiceCommandInterface"], swiftSettings: appIsolation),
        .target(name: "VoiceCommandLive", dependencies: ["VoiceCommandInterface"], swiftSettings: appIsolation),
        .target(name: "VoiceCommandTesting", dependencies: ["VoiceCommandInterface"], swiftSettings: appIsolation),
        .target(
            name: "VoiceCommand",
            dependencies: ["VoiceCommandCore", "VoiceCommandUI", "VoiceCommandLive", "VoiceCommandInterface"],
            swiftSettings: appIsolation
        ),
        .testTarget(
            name: "VoiceCommandCoreTests",
            dependencies: ["VoiceCommand", "VoiceCommandCore", "VoiceCommandInterface", "VoiceCommandTesting"],
            swiftSettings: appIsolation
        ),
    ]
)
