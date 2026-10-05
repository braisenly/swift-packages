// swift-tools-version: 6.4
import PackageDescription

// Shared Swift capability packages (drop-in architecture).
// Each capability X ships targets XInterface, XCore, XUI, XLive, XTesting and umbrella X;
// architecture.json declares every target and Scripts/arch-check enforces the layer rules.
let package = Package(
    name: "swift-packages",
    defaultLocalization: "en",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [],
    dependencies: [],
    targets: []
)
