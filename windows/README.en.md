# Codex Aurora Skin for Windows

The Windows package provides Inno Setup installation, a pinned Node.js runtime,
Microsoft Store package identity checks, loopback CDP injection, and complete
restoration.

Download Setup.exe from
[GitHub Releases](https://github.com/Entropy-R/Codex-Aurora-Skin/releases).
The Start Menu entry opens the local browser manager and initializes the shared
offline catalog. No login startup item or online update check is created.

Source verification:

```powershell
node tools/check-project-consistency.mjs
node --test manager/*.test.mjs
pwsh -NoProfile -File windows/tests/run-tests.ps1
pwsh -NoProfile -File windows/tests/installer-static.tests.ps1
```

Runtime state is stored under `%LOCALAPPDATA%\CodexAuroraSkin`. Uninstall restores
the official appearance while preserving user themes, images, and overrides by
default.

Continue cross-device work on the existing release integration branch rather than a
Windows-specific copy. The current v1.0.1 Windows gate uses
`codex/v1.0.1-fixes`; see `docs/DEVELOPMENT_WORKFLOW.md`.
