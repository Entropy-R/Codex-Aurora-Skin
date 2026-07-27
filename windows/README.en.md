# Codex Aurora Skin for Windows

The Windows package provides Inno Setup installation, a pinned Node.js runtime,
Microsoft Store package identity checks, loopback CDP injection, and complete
restoration.

Download Setup.exe from
[GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases).
The Start Menu entry opens the local browser manager and initializes the shared
offline catalog. No login startup item or online update check is created.

Runtime state is stored under `%LOCALAPPDATA%\CodexAuroraSkin`. Uninstall restores
the official appearance while preserving user themes, images, and overrides by
default.
