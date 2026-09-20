import XCTest
@testable import AuroraSkinCore

final class CoreTests: XCTestCase {
  func testSemanticVersionParsingAndComparison() throws {
    XCTAssertEqual(SemanticVersion("v1.3")?.description, "1.3.0")
    XCTAssertEqual(SemanticVersion(" 2.0.1\n")?.description, "2.0.1")
    XCTAssertTrue(try XCTUnwrap(SemanticVersion("1.3.1")) > SemanticVersion("1.3.0")!)
    XCTAssertTrue(try XCTUnwrap(SemanticVersion("2.0.0")) > SemanticVersion("1.99.99")!)
    XCTAssertNil(SemanticVersion("1.3.0-beta"))
    XCTAssertNil(SemanticVersion("1..3"))
    XCTAssertNil(SemanticVersion("1.2.3.4"))
  }

  func testStatusSnapshotParsesChineseTheme() throws {
    let data = Data(#"{"session":"active","operation":"","operationMessage":"","port":9341,"injectorAlive":true,"cdpOk":true,"codexRunning":true,"themeName":"中文主题","appliedThemeName":"中文主题"}"#.utf8)
    let snapshot = try XCTUnwrap(StatusSnapshot(jsonData: data))
    XCTAssertEqual(snapshot.session, "active")
    XCTAssertEqual(snapshot.themeName, "中文主题")
    XCTAssertEqual(snapshot.title, "Skin ON")
    XCTAssertFalse(snapshot.busy)
  }

  func testBusyAndFailureLabels() {
    var snapshot = StatusSnapshot(session: "active", operation: "applying")
    XCTAssertTrue(snapshot.busy)
    XCTAssertEqual(snapshot.title, "Skin 应用中")
    snapshot.operation = "failed"
    XCTAssertEqual(snapshot.title, "Skin ON · 操作失败")
  }

  func testEngineInstallPolicyPreventsDowngradesAndSameBuildReinstalls() throws {
    let bundled = try XCTUnwrap(EngineReleaseIdentity(version: "1.0.2", build: "10002"))
    let same = try XCTUnwrap(EngineReleaseIdentity(version: "1.0.2", build: "10002"))
    let newerBuild = try XCTUnwrap(EngineReleaseIdentity(version: "1.0.2", build: "10003"))
    let newerVersion = try XCTUnwrap(EngineReleaseIdentity(version: "1.1.0", build: "11000"))
    let older = try XCTUnwrap(EngineReleaseIdentity(version: "1.0.1", build: "10001"))

    XCTAssertFalse(EngineInstallPolicy.shouldReplace(
      installed: same,
      bundled: bundled,
      installedComplete: true
    ))
    XCTAssertFalse(EngineInstallPolicy.shouldReplace(
      installed: newerBuild,
      bundled: bundled,
      installedComplete: true
    ))
    XCTAssertFalse(EngineInstallPolicy.shouldReplace(
      installed: newerVersion,
      bundled: bundled,
      installedComplete: true
    ))
    XCTAssertTrue(EngineInstallPolicy.shouldReplace(
      installed: older,
      bundled: bundled,
      installedComplete: true
    ))
    XCTAssertTrue(EngineInstallPolicy.shouldReplace(
      installed: same,
      bundled: bundled,
      installedComplete: false
    ))
    XCTAssertTrue(EngineInstallPolicy.shouldReplace(
      installed: nil,
      bundled: bundled,
      installedComplete: true
    ))
  }
}
