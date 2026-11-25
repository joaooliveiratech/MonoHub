# Agent Guidance — MonoHub

Read [`RULES.md`](./RULES.md) and [`../RULES.md`](../RULES.md) before modifying this repository.

## Project Summary

**MonoHub** is a native **Swift 6.4** macOS utility suite targeting **macOS 27+ (Apple Silicon ARM64)** with **Liquid Glass** (`NSGlassEffectView`) UI, on-demand modules, and **Zero Telemetry** (outbound network restricted exclusively to enabled providers in `AIQuota/`).

## Architecture

```text
Sources/MonoHub/
├── App/                        # MonoHubApp, AppDelegate, AppInfo (version/build)
├── Core/                       # FeatureManager, PreferencesManager, Localization (EN/PT),
│                               # PermissionsManager, WhitelistManager, OperationLogger, HardwareInfo
├── UI/
│   ├── Components/             # Shared Liquid Glass panels, cards, badges, controls
│   ├── Main/                   # DashboardView, SidebarView, ModulesView, MainWindowController
│   └── Settings/               # Preferences, hotkeys, language, and whitelist views
└── Features/
    ├── AIQuota/                # Models, Services (Keychain + provider usage readers), UI
    ├── AudioControl/           # Engine (CoreAudio device & per-app volume), Models, UI
    ├── Cleanup/                # Engine (Uninstaller, Orphans, SystemClean, Snapshots, DevEnv, Dupes, Startup), Models, UI
    ├── DisplayControl/         # Engine (DDC/CI, Sub-Zero Dimming, XDR, HiDPI, Virtual Display, PiP, EDID), Models, UI
    ├── DynamicNotch/           # Engine (Media, Calendar, Reminders, Camera, Teleprompter, Clipboard, HUD), Models, UI
    ├── MediaConverter/         # Engine (AVFoundation/VideoToolbox + ImageIO), Models, UI
    ├── Productivity/           # URLRouter, Snippets, BluetoothQuickConnect, UI
    ├── Screenshot/             # Models, Services (ScreenCaptureKit, ScrollingCapture, ScreenRecorder, OCR), UI
    ├── SystemMonitor/          # Engine (Sampler, BatteryHealth, Ports/Bandwidth), Readers (Mach/IOKit), Models, UI
    ├── WindowSwitcher/         # Engine (EventTap, ScreenCaptureKit ThumbnailStore), Models, UI
    └── WindowTiling/           # Engine (AX batching, EdgeSnap, MRU Focus Queue, Hotkeys), Models, UI

Tests/MonoHubTests/             # Swift Testing suite covering all modules & invariants
Resources/                      # AppIcon.icns, Info.plist, Entitlements.plist
scripts/                        # generate_icon.swift
```

## Non-Negotiables

1. **Zero Telemetry & Network Isolation**: Never add analytics, crash reporting, or network calls outside `Features/AIQuota/`. Keep `com.apple.security.network.server` omitted from `Resources/Entitlements.plist`.
2. **Keychain-Only Secrets**: Never store API keys, tokens, or credentials in `UserDefaults`, files, or logs.
3. **Confirmation Guards**: Every destructive action (file/cache removal, process kill, snapshot purge, LaunchAgent deletion) must list explicit paths/sizes and require modal confirmation.
4. **Zero-Cost Disabled Modules & Lock Suspension**: Disabled modules must stop their engines, timers, observers, and event taps completely. All background engines must pause while the Mac is locked or asleep.
5. **Swift 6.4 Strict Concurrency**: Respect `MainActor` default isolation and keep blocking I/O, transcoding, and hashing off the main thread.
6. **Bilingual Parity**: Keep English and Portuguese strings (`Core/Localization.swift`, `Core/PortugueseStrings.swift`) in sync for all user-facing text.
7. **Clean Install Invariant**: Always install exclusively to `/Applications/MonoHub.app` via `make install` and never leave `.app` bundles in the repository root.
8. **Source-Only Releases**: Never attach binaries, `.app` bundles, or `.zip` archives to GitHub Releases.

## Standard Commands

```bash
# Run the full test suite (must pass with 0 failures)
make test

# Build release binary for Apple Silicon (arm64)
make build

# Build, sign, clean previous installs/caches, and install to /Applications/MonoHub.app
make install

# Regenerate AppIcon.icns from scripts/generate_icon.swift
make icon
```
