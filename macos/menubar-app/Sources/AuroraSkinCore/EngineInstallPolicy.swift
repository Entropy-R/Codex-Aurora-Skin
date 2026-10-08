import Foundation

public struct EngineReleaseIdentity: Comparable, Sendable {
  public let version: SemanticVersion
  public let build: Int

  public init?(version: String, build: String) {
    guard let semanticVersion = SemanticVersion(version),
          let buildNumber = Int(build.trimmingCharacters(in: .whitespacesAndNewlines)),
          buildNumber > 0 else {
      return nil
    }
    self.version = semanticVersion
    self.build = buildNumber
  }

  public static func < (lhs: EngineReleaseIdentity, rhs: EngineReleaseIdentity) -> Bool {
    if lhs.version != rhs.version { return lhs.version < rhs.version }
    return lhs.build < rhs.build
  }
}

public enum EngineInstallPolicy {
  public static func shouldReplace(
    installed: EngineReleaseIdentity?,
    bundled: EngineReleaseIdentity,
    installedComplete: Bool
  ) -> Bool {
    guard installedComplete, let installed else { return true }
    return installed < bundled
  }
}
