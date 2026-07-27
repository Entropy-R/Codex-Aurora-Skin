// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "CodexAuroraSkinMenuBar",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(
      name: "CodexAuroraSkinMenuBar",
      targets: ["CodexAuroraSkinMenuBar"]
    )
  ],
  targets: [
    .target(
      name: "AuroraSkinCore",
      path: "Sources/AuroraSkinCore"
    ),
    .executableTarget(
      name: "CodexAuroraSkinMenuBar",
      dependencies: ["AuroraSkinCore"],
      path: "Sources/CodexAuroraSkinMenuBar"
    ),
    .testTarget(
      name: "AuroraSkinCoreTests",
      dependencies: ["AuroraSkinCore"],
      path: "Tests/AuroraSkinCoreTests"
    )
  ]
)
