# Notices

Codex Aurora Skin is an **unofficial** customization project and is **not affiliated with, endorsed by, or sponsored by OpenAI**.

## Software license

The MIT License in `LICENSE` applies to the **software source code** in this repository (scripts, CSS, injectors, docs that describe the software, and the abstract demo asset generated for this repo).

It does **not** grant rights to:

- OpenAI or Codex trademarks, product names, logos, or trade dress
- Official Codex / ChatGPT application binaries, `.app` bundles, or `app.asar`
- Any user-supplied images or third-party artwork you drop into a theme
- Character likenesses, franchise art, or celebrity imagery

## Demo artwork

`library/preset-red-white-abstract/background.png` is original abstract geometric
art generated for this open-source repository (no characters).

## Runtime

- The macOS package does not redistribute Node.js. It validates and uses the
  Node.js executable already signed and bundled inside the user's official
  Codex desktop application.
- The Windows Setup.exe redistributes only `node.exe` and `LICENSE` from the
  pinned official Node.js v22.23.1 win-x64 archive after verifying its published
  SHA-256. Node.js is distributed under its own license; that license is kept
  beside the bundled executable in `runtime/node/LICENSE`.

## Inno Setup Simplified Chinese messages

The Windows installer is compiled with Inno Setup. Its Simplified Chinese
messages file is vendored unchanged from the official Inno Setup source tag
`is-6_7_1` at
`windows/installer/languages/ChineseSimplified.isl`, maintained by Zhenghan
Yang and distributed under the Inno Setup License. The full license is retained
at `windows/installer/languages/Inno-Setup-License.txt`.

## Security model

Themes are applied through Chromium DevTools Protocol on **loopback only**. While a themed session is running, treat the local debugging port as sensitive: do not run untrusted local software that could attach to it. Use the Restore launcher to tear down the themed session and debugging port.
