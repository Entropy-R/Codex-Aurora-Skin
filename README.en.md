# Codex Aurora Skin

Codex Aurora Skin is an unofficial theme manager for the Codex workspace in the
ChatGPT desktop app on Windows, macOS, and Linux. It injects background styling
through a loopback-only CDP session. It does not modify the Codex application,
account data, model configuration, plugins, or tasks.

> This project is not affiliated with, sponsored by, or endorsed by OpenAI.

## Downloads

Download the public package for your platform from
[GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases):

- Windows: `CodexAuroraSkin-Setup-v*.exe`
- macOS: `CodexAuroraSkin-v*.dmg`
- Linux: `CodexAuroraSkin-v*-linux.tar.gz`, `.deb`, or `.rpm`
- Checksums: `SHA256SUMS.txt`

The public artifacts do not currently use commercial code signing. The macOS
app has an ad-hoc signature and is not notarized by Apple, so its first launch
requires explicit approval in System Settings > Privacy & Security. The product
starts only when requested, does not create a login item, and does not check
for updates online.

### First use on macOS

1. Open the downloaded DMG and drag **Codex Aurora Skin** to **Applications**.
2. Try to launch it once. If macOS blocks it, verify its SHA-256 against the
   release, then use **Open Anyway** in System Settings > Privacy & Security.
3. Launch the app again to open the local theme manager in your browser.
4. Choose a theme and apply it. Approve the Codex restart when prompted.
5. Use **Restore official appearance** in the manager to end the themed session.

See the [macOS installation guide](./docs/install-macos.md) and
[Apple's official safety guidance](https://support.apple.com/en-us/102445).

## Theme manager

The local Simplified Chinese manager provides:

- separate built-in and user theme libraries;
- independent light/dark brightness, background dimming, and surface-strength controls;
- local PNG, JPEG, and WebP imports with browser-generated thumbnails;
- apply, rename, and delete operations for user themes;
- explicit confirmation before restarting Codex for a CDP session;
- complete restoration of the official appearance.

The offline catalog contains the original Red & White Abstract preset.
Built-in themes are read-only. User themes and overrides remain in the
platform state directory across upgrades and default uninstall.

Brightness ranges from `0.35` to `1.20`. In dark mode, background dimming ranges
from `0` to `0.70` and surface strength from `0.20` to `1.00`; light mode uses
safe minimums of `0.32` and `0.60` respectively for text contrast. Image controls affect
only the background layer, while surface strength changes panel translucency
without filtering text or icons. Themes always use `appearance: auto` and
follow the official Codex light/dark appearance.

## Security boundary

- The manager binds only to `127.0.0.1` on an ephemeral port.
- Each launch creates a random 256-bit token and validates Host, Origin, and
  Bearer authentication.
- Strict CSP and `Referrer-Policy: no-referrer` are enabled.
- Imports are limited to 16 MB, 16384px per side, and 50 megapixels.
- Theme and override updates use staging and atomic replacement.
- The manager exits after 120 seconds without an authenticated client; the
  independent injector keeps the current theme active.
- Restore stops the injector, closes the CDP session, and relaunches Codex
  normally.

See the [Windows](./docs/install-windows.md) and
[macOS](./docs/install-macos.md) and
[Linux](./docs/install-linux.md) installation guides.

## Development roadmap

Bug fixes, optimizations, and new development work for Windows, macOS, Linux,
and shared modules are maintained in the unified
[development roadmap](./docs/ROADMAP.md). Its priorities, target versions, and
acceptance criteria define the follow-up work. Cross-device handoff and release
integration branch rules are documented in the
[development workflow](./docs/DEVELOPMENT_WORKFLOW.md).
