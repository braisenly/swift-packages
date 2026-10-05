# CLAUDE_NOTES

- 2026-10-05: Repo created as the skeleton for the drop-in architecture POC (Master Plan v1 step E3). Zero capability targets; ARCH_CHECK is layer 1 only (`Scripts/arch_check.py`, copied from the drop-in-pack-swift-spm skill). swift-bylaws and Harmonize layers come later.
- Consumers (playground `AppFeatures/`) set `BRAISENLY_SWIFT_PACKAGES_PATH` to a local checkout until tag `0.1.0` exists; after that they pin `exact: "0.1.0"`.
- `swift test` is skipped in CI until a test target exists (SwiftPM errors on a package with no tests).
