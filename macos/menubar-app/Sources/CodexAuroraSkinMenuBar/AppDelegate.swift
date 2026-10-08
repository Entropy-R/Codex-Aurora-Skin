import AppKit
import AuroraSkinCore

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let fileManager = FileManager.default

  private var bundledEngineURL: URL? {
    Bundle.main.resourceURL?.appendingPathComponent("engine", isDirectory: true)
  }

  private var installedEngineURL: URL {
    fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex/codex-aurora-skin", isDirectory: true)
  }

  private var requiredPaths: [String] {
    [
      "VERSION",
      "ENGINE_BUILD",
      "assets/aurora-skin.css",
      "assets/renderer-inject.js",
      "assets/selectors.json",
      "library/catalog.json",
      "library/integrity.json",
      "library/preset-red-white-abstract/theme.json",
      "manager/heartbeat-lease.mjs",
      "manager/server.mjs",
      "manager/theme-store.mjs",
      "manager/web/api-client.mjs",
      "manager/web/index.html",
      "scripts/common-macos.sh",
      "scripts/injector.mjs",
      "scripts/launch-manager-macos.sh",
      "scripts/migrate-config-macos.sh",
      "scripts/restore-aurora-skin-macos.sh",
      "scripts/start-aurora-skin-macos.sh",
      "scripts/theme-config.mjs"
    ]
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    do {
      try installBundledEngine()
      try migrateLegacyConfiguration()
      try launchManager()
    } catch {
      let alert = NSAlert()
      alert.alertStyle = .critical
      alert.messageText = "Codex Aurora Skin 启动失败"
      alert.informativeText = error.localizedDescription
      alert.runModal()
    }
    NSApp.terminate(nil)
  }

  private func installBundledEngine() throws {
    guard let bundled = bundledEngineURL else {
      throw CocoaError(.fileNoSuchFile, userInfo: [
        NSLocalizedDescriptionKey: "安装包中缺少主题引擎。"
      ])
    }
    for relativePath in requiredPaths {
      guard fileManager.fileExists(atPath: bundled.appendingPathComponent(relativePath).path) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [
          NSLocalizedDescriptionKey: "安装包不完整：\(relativePath)"
        ])
      }
    }

    let bundledIdentity = try engineIdentity(at: bundled)
    if fileManager.fileExists(atPath: installedEngineURL.path) {
      let installedComplete = requiredPaths.allSatisfy { relativePath in
        fileManager.fileExists(
          atPath: installedEngineURL.appendingPathComponent(relativePath).path
        )
      }
      let installedIdentity = try? engineIdentity(at: installedEngineURL)
      if !EngineInstallPolicy.shouldReplace(
        installed: installedIdentity,
        bundled: bundledIdentity,
        installedComplete: installedComplete
      ) {
        return
      }
    }

    let parent = installedEngineURL.deletingLastPathComponent()
    try fileManager.createDirectory(
      at: parent,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let token = UUID().uuidString
    let staging = parent.appendingPathComponent(".aurora-skin-install-\(token)", isDirectory: true)
    let backup = parent.appendingPathComponent(".aurora-skin-backup-\(token)", isDirectory: true)
    defer {
      if fileManager.fileExists(atPath: staging.path) {
        try? fileManager.removeItem(at: staging)
      }
    }
    try fileManager.copyItem(at: bundled, to: staging)

    if fileManager.fileExists(atPath: installedEngineURL.path) {
      try fileManager.moveItem(at: installedEngineURL, to: backup)
    }
    do {
      try fileManager.moveItem(at: staging, to: installedEngineURL)
      if fileManager.fileExists(atPath: backup.path) {
        // 新引擎已经提交；旧备份清理失败不应把成功升级报告成失败。
        try? fileManager.removeItem(at: backup)
      }
    } catch {
      if fileManager.fileExists(atPath: backup.path),
         !fileManager.fileExists(atPath: installedEngineURL.path) {
        try? fileManager.moveItem(at: backup, to: installedEngineURL)
      }
      throw error
    }
  }

  private func engineIdentity(at root: URL) throws -> EngineReleaseIdentity {
    let version = try String(
      contentsOf: root.appendingPathComponent("VERSION"),
      encoding: .utf8
    )
    let build = try String(
      contentsOf: root.appendingPathComponent("ENGINE_BUILD"),
      encoding: .utf8
    )
    guard let identity = EngineReleaseIdentity(version: version, build: build) else {
      throw CocoaError(.fileReadCorruptFile, userInfo: [
        NSLocalizedDescriptionKey: "主题引擎版本标识无效。"
      ])
    }
    return identity
  }

  private func launchManager() throws {
    let launcher = installedEngineURL.appendingPathComponent(
      "scripts/launch-manager-macos.sh"
    )
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [launcher.path]
    try process.run()
    Thread.sleep(forTimeInterval: 0.25)
    if !process.isRunning && process.terminationStatus != 0 {
      throw CocoaError(.executableRuntimeMismatch, userInfo: [
        NSLocalizedDescriptionKey: "本地主题管理器未能启动。"
      ])
    }
  }

  private func migrateLegacyConfiguration() throws {
    let script = installedEngineURL.appendingPathComponent(
      "scripts/migrate-config-macos.sh"
    )
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path]
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
      throw CocoaError(.fileWriteUnknown, userInfo: [
        NSLocalizedDescriptionKey: "旧版外观配置迁移失败，原备份已保留。"
      ])
    }
  }
}
