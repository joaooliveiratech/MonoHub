# MonoHub Rules & Engineering Guidelines

Mandatory rules for developing, maintaining, testing, securing, and releasing **MonoHub**.

---

## 1. Project Identity & Integrated Modules

**MonoHub** is a unified, native macOS utility suite built in **Swift 6.4** exclusively for **macOS 27+ (Apple Silicon ARM64)** with a **macOS 27 Liquid Glass** (`NSGlassEffectView`) design language and **Zero Telemetry**.

It consolidates the following on-demand modules into a single modular application:

1. **System Monitor & Menu Bar (`SystemMonitor/`)**: Real-time kernel-level telemetry widgets in the menu bar and dashboard (CPU P/E cores, RAM, GPU, Disk I/O, Network, Battery & Power in Watts, HID Thermal Sensors, per-process Network Bandwidth & Ports, and Battery Health diagnostics).
2. **Dynamic Notch & Dynamic Island (`DynamicNotch/`)**: Native Dynamic Island experience on physical MacBook notches and virtual floating notches on external displays — media Live Activities with equalizer, AI Quota & heavy-process wings/peek alerts, EventKit Calendar & Reminders with 1-click meeting joins, low-latency Camera Mirror with Studio Controls, Teleprompter & Scratchpad, Bluetooth battery telemetry, File Shelf with AirDrop, Clipboard Manager, and compact HUD replacements.
3. **Window Switcher (`WindowSwitcher/`)**: High-speed `⌥ Tab` / `⌘ Tab` window switcher with hardware-accelerated `ScreenCaptureKit` thumbnails in ephemeral RAM cache, Vim (`hjkl`) & numeric (`1–9`) navigation, fuzzy search (`f` / `/`), Quick Look (`Space`), and direct window actions.
4. **Window Tiling & Management (`WindowTiling/`)**: Magnetic edge-drag snapping with Liquid Glass previews, smart MRU focus queue (`⌃⌥⌘⇥`, `⌃⌥⌘]`, `⌃⌥⌘[`, `⌃⌥⌘↩`), directional focus, 30+ global shortcuts, modifier drag/resize, multi-monitor support, CLI (`monohub` / `monotile`), and URL schemes.
5. **Cleanup, Uninstaller & Maintenance (`Cleanup/`)**: Transparent app uninstaller, orphan residue hunter, deep system cache cleaner, Time Machine APFS local snapshot purger, dev project artifact purger (`node_modules`, `.build`, `target`, `.venv`), Dev Environments inspector (Xcode, Node, Python/ML, Homebrew, Rust, Go, Docker), Duplicate Files & Similar Photos (`CryptoKit` + `Vision`), Startup Items & LaunchAgents manager, Disk Analyzer, and System Optimization.
6. **AI Quotas (`AIQuota/`)**: Menu bar progress ring/badge and Liquid Glass cards tracking usage, pacing, credits, and rate-limit resets for Claude, Codex, Antigravity, Copilot, Cursor, DeepSeek, Kimi, GLM, and more — without sending prompts or consuming tokens.
7. **Screenshots, Scrolling Capture & Screen Recording (`Screenshot/`)**: Region, window, and fullscreen capture via `ScreenCaptureKit`, pixel magnifier + HEX picker, annotation editor (arrows, rectangles, numbering, text, destructive blur/pixelate), local Vision OCR, hardware-stitched Scrolling Capture (up to 32,000 px), quick GIF / MP4 / WebM screen recording, and floating pinned images.
8. **Media Converter (`MediaConverter/`)**: Apple Silicon Media Engine (`AVFoundation` / VideoToolbox) and `ImageIO` hardware-accelerated batch video transcoding and image optimization (HEIC, AVIF, WebP, JPEG, PNG, TIFF) with optional EXIF stripping.
9. **Display Control (`DisplayControl/`)**: Opt-in (disabled by default) native display control suite with DDC/CI hardware backlight/volume/input control, sub-zero dimming & blackout, XDR/HDR extra brightness upscaling, HiDPI scaling & rotation, Kelvin color calibration, virtual displays (`CGVirtualDisplay`), hardware PiP / teleprompter stream, layout protection, and EDID inspector/override export.
10. **Audio Control (`AudioControl/`)**: Native CoreAudio output/input device management, per-app volume control, and quick audio routing.
11. **Productivity & Clipboard (`Productivity/`)**: URL Router & UTM tracker stripper (native routing for Zoom, Teams, Figma, Notion, Telegram, plus source-app/domain rules), system-wide Text Expansion / Snippets with dynamic variables (`{date}`, `{time}`, `{clipboard}`, `{uuid}`), and 1-tap Bluetooth Quick Connect (`⌥ B`) with automatic CoreAudio routing.
12. **Smart Hybrid Lifecycle**: Appears in the Dock while the main window is open; closing the main window (`⌘W`) transitions to `.accessory` mode and continues running silently in the Menu Bar and Notch.

---

## 2. Critical Privacy, Security & Performance Invariants

### Privacy & Network Isolation
- **Zero Telemetry**: No analytics SDKs, remote crash reporters, tracking beacons, or usage telemetry of any kind.
- **Network Restricted to AI Quotas**: Every module operates 100% offline except `AIQuota/`.
  - `Resources/Entitlements.plist` declares `com.apple.security.network.client` solely for enabled AI quota providers and intentionally omits `com.apple.security.network.server`.
  - When AI Quotas is disabled in **Modules**, zero outbound network connections are made.
- **Keychain-Only Credentials**: Provider API keys and tokens live exclusively in the macOS Keychain — never in `UserDefaults`, plists, or plain-text files. Never send prompts, consume tokens, or refresh OAuth sessions owned by other tools.
- **Permitted Subprocesses in AI Quotas**: Only via `CommandRunner` (`agy -p /usage`) and Claude Code Keychain synchronization.
- **Local-Only Audit Log**: Cleanup history is stored strictly locally at `~/Library/Logs/MonoHub/operations.log`.

### Safe & Transparent Destructive Actions
- **No Silent Deletion**: Every file, directory, snapshot, duplicate, or LaunchAgent scheduled for removal must be explicitly listed with its full path, computed size, and individual checkbox.
- **Mandatory Confirmation Modals**: All destructive operations (deletions, process termination, system purges) require explicit modal confirmation.
- **Trash First**: Prefer moving items to the macOS Trash (`trashItem`) whenever applicable.
- **Whitelist Protection**: Respect user-protected paths in `~/.config/monohub/whitelist` and strictly protect Apple system services (`com.apple.*`).

### Battery, CPU & Concurrency Efficiency
- **On-Demand Zero-Cost Modules**: Disabling a module (or an individual Dynamic Notch feature) must tear down its underlying engine, timers, event taps, and observers — not merely hide its UI.
- **Lock-Screen & Display-Sleep Suspension**: All background engines, timers, and animations must suspend when the Mac is locked or the display sleeps.
- **Kernel-Direct Telemetry**: Zero subprocesses for system monitoring. All metrics come directly from Mach/Darwin and IOKit (`host_statistics64`, `host_processor_info`, `vm_statistics64`, `statvfs`, `getifaddrs`, `IOKit`, `libproc`, Darwin `NetworkStatistics`).
- **E-Core Scheduling**: Run background sampling on `.utility` queues targeting Apple Silicon Efficiency Cores; scan process lists (`proc_listpids`) on demand only when a detail panel or System Monitor view is visible.
- **Swift 6.4 Strict Concurrency**: Conform to Swift 6 strict concurrency (`MainActor` default isolation, `Sendable`, `async/await`, `actor`). Never block the main thread with synchronous disk I/O, media transcoding, or cryptographic hashing.

---

## 3. Screenshot Module Rules (`Screenshot/`)

- **Instant `ESC`**: `ESC` immediately dismisses the capture overlay, editor, and pinned images on the first press (except while typing inline text, where it cancels the text input).
- **Silent Startup**: Never open windows on launch; register only global hotkeys and the menu bar icon.
- **Strict Offline & Privacy**: Zero network calls, no disk writes without explicit user action, strip EXIF/GPS metadata on export, mark OCR clipboard output as sensitive/concealed, and never log captured screen content or OCR text.
- **Carbon Hotkeys**: Every `kEventHotKeyPressed` handler must verify the `EventHotKeyID` signature and return `eventNotHandledErr` for events belonging to other modules (e.g., `WindowTiling`).
- **Editor Window Policy**: Keep the app in `.regular` activation policy while any screenshot editor is open (`MainWindowController.updateActivationPolicy()` checks `ScreenshotController.hasOpenEditors`).
- **Preferences**: Use `MonoHub_Screenshot_*` keys; standalone MonoShot preferences (`com.antigravity.monoshot`) are migrated once on first run.

---

## 4. Semantic Versioning (SemVer) & Release Procedure

MonoHub strictly follows **Semantic Versioning (`MAJOR.MINOR.PATCH`)**:
- **PATCH (`0.x.Y`)**: Bug fixes, UI polish, battery/performance optimizations.
- **MINOR (`0.X.0`)**: New modules or major user-facing features.
- **MAJOR (`X.0.0`)**: Breaking architectural overhauls.

### Mandatory Version Bump Checklist
Whenever a release is prepared:
1. Update `AppInfo.version` and increment `AppInfo.build` in `Sources/MonoHub/App/AppInfo.swift`.
2. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
3. Update the version badge in `README.md`.
4. Run `make test` and verify **0 failures**.
5. Run `make install` to verify release compilation, code signing, bundle packaging, and clean installation to `/Applications/MonoHub.app`.
6. Commit with Conventional Commits (`feat:`, `fix:`, `perf:`, `docs:`, `chore:`) and create an annotated SemVer Git tag (`git tag -a vX.Y.Z -m "MonoHub vX.Y.Z"`).

---

## 5. Clean Installation & Cache Hygiene Invariant

- **Single Install Location**: Always install exclusively to `/Applications/MonoHub.app`. Never leave duplicate bundles in `~/Applications/` or in the repository root.
- **Mandatory Clean Install (`make install`)**:
  1. Terminate running instances (`MonoHub` and legacy standalone Mono apps).
  2. Remove previous/duplicate bundles from `/Applications/` and `~/Applications/`.
  3. Clear application caches (`~/Library/Caches/com.antigravity.monohub`).
  4. Unregister obsolete LaunchServices paths (`lsregister -u`).
  5. Copy `MonoHub.app` to `/Applications/` and delete the local `.app` bundle from the repository root.
  6. Symlink CLI tools (`monohub`, `monotile`, `monotab`, `mononotch`, `monoaibar`, `monoshot`) into `~/.local/bin`.
  7. Re-register `/Applications/MonoHub.app` in LaunchServices (`lsregister -f`) and flush system caches (`qlmanage -r`, `killall Finder`).

---

## 6. Release Asset Prohibition (CRITICAL)

- **NEVER** upload compiled binaries, `.app` bundles, `.zip` archives, `.dmg` images, or any build artifacts as GitHub Release assets.
- Releases must consist **strictly of Git tags, commits, and Markdown release notes** (source-only releases).
