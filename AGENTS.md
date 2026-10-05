# AGENTS.md — braisenly/swift-packages

Shared Swift capability packages for Luke's drop-in architecture. Every capability ships as SwiftPM products another app can add and use through one entry point.

## Package map
| Capability | Products | Platforms | Status |
|---|---|---|---|
| VoiceCommand | `VoiceCommand`, `VoiceCommandCore`, `VoiceCommandInterface`, `VoiceCommandTesting` | iOS (full); macOS: Interface + Core + Testing | POC, extracted from `zautke/playground` with history. Host must declare `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`. Example: `Examples/VoiceCommandExample` |

## Capability anatomy
Capability `X` → targets `XInterface` (protocols, Sendable values; Foundation only), `XCore` (logic; no SwiftUI/UIKit/AppKit), `XUI` (SwiftUI, `@MainActor @Observable` models), `XLive` (adapters over Apple/third-party SDKs), `XTesting` (fakes for every port), umbrella `X` (entry point; the only place `@_exported import` is allowed). Products: `X`, `XCore`, `XInterface`, `XTesting`. Example host: `Examples/XExample`, using only product `X`.

Resources load from `Bundle.module`. Cross-target internals use `package` access; only real API is `public`. Hosts never have to inject environment values: the entry point does it.

## Rules
- `ARCH_CHECK=Scripts/arch-check`. Run it after every manifest or import change; it must exit 0. Never weaken `architecture.json` to make it pass; `exceptions` entries need Luke's approval.
- Every target is declared in `architecture.json`.
- Code moved from an app keeps its concurrency semantics: mirror the app's isolation settings per target. VoiceCommand targets use `appIsolation` in Package.swift (Swift 6, `.defaultIsolation(MainActor.self)`, `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`), matching playground's app target.
- Extractions follow the kb protocol `projects/drop-in-architecture/protocols/factor-out-rewire-app-protocol-v1`: move and change never share a commit; gates are captured evidence.
- Foundation UI capabilities (allowed as UI dependencies): none yet (DesignSystem and Typography are planned).

## Floors and toolchain
iOS 27.0, macOS 27.0, `swift-tools-version: 6.4`, Swift 6 language mode.

## Commands
```bash
swift build && swift test            # macOS
Scripts/arch-check                    # layer-1 architecture check
xcodebuild -scheme swift-packages-Package -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build test
```
