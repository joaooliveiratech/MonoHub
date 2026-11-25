# Privacy Policy — MonoHub

**MonoHub** was designed from its very first commit around **Strict Privacy & Zero Telemetry**.

## 1. Network Access Restricted to AI Quotas
- Every module in MonoHub operates **100% offline**, except **AI Quotas** (`AIQuota/`).
- `Resources/Entitlements.plist` declares only `com.apple.security.network.client` (for AI Quotas) and intentionally omits `com.apple.security.network.server`.
- When enabled, AI Quotas queries only the usage/balance endpoints of the providers you explicitly activate (e.g., Anthropic, OpenAI/ChatGPT, DeepSeek, Kimi, Z.ai). It never sends prompts, never consumes tokens, and never transmits data to any third party.
- Disabling **AI Quotas** in **Modules** guarantees zero outbound network connections.
- API keys and tokens are stored exclusively in the **macOS Keychain**. Account email addresses are stripped from the UI and local disk caches.
- No hardware metrics, installed app lists, file paths, or preferences ever leave your Mac.

## 2. Zero Data Collection or Analytics
- MonoHub contains **no third-party analytics SDKs**, usage trackers, telemetry beacons, or remote crash reporting services.
- All hardware telemetry (CPU, RAM, GPU, Disk, Network, Battery, Thermal Sensors, and per-process bandwidth) is read locally via direct Darwin/Mach/IOKit kernel APIs and discarded in memory.

## 3. Strictly Local Storage
- **Screenshots & Screen Recording**: Captured frames remain in volatile memory and are only written to disk when you explicitly save or export. Exports strip EXIF, GPS, and device metadata; opened images larger than 256 MB or 120 megapixels are rejected. OCR runs 100% locally via Apple's `Vision` framework on the Neural Engine, and recognized text is placed on the clipboard only when requested (marked as sensitive/concealed). No screen content or OCR text is ever written to system logs.
- **Clipboard Manager**: Ignores concealed and password-manager items (`org.nspasteboard.ConcealedType`). Pinned items are stored strictly locally.
- **AI Quotas**: Last fetched provider state (with zero credentials or personal data) is cached locally at `~/Library/Application Support/MonoAiBar` with `0600` permissions.
- **Preferences**: Stored locally in `UserDefaults` (`com.antigravity.monohub`).
- **Whitelist**: Stored locally at `~/.config/monohub/whitelist`.
- **Cleanup Audit Log**: Stored locally at `~/Library/Logs/MonoHub/operations.log` and can be cleared or disabled at any time in Settings.

## 4. Real-Time Window Previews (`ScreenCaptureKit`)
- Window thumbnails used by the **Window Switcher** (`MonoTab`) are processed strictly in ephemeral RAM via native `ScreenCaptureKit` APIs.
- No images, text, or screenshots are written to disk or transmitted anywhere.
- Cached thumbnails are purged from memory as soon as windows close or the switcher resets.

## 5. Camera, Microphone, Calendar & Reminders (`DynamicNotch`)
- The camera is used solely for the real-time **Camera Mirror** inside the notch via `AVCaptureSession` and is shut down immediately when the notch closes (turning off the green hardware LED instantly).
- Microphone access is used solely for local voice-level monitoring and quick global mute in the notch; no audio is recorded or transmitted.
- Calendar and Reminders access runs 100% locally via `EventKit` to display upcoming events, 1-click meeting links, and tasks in the notch. No calendar or reminder data ever leaves your device.
