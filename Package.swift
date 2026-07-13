// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexQuotaMenu",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]),
        .executable(name: "codex-quota-menu", targets: ["CodexQuotaMenu"])
    ],
    targets: [
        .target(name: "CodexQuotaCore"),
        .executableTarget(name: "CodexQuotaMenu", dependencies: ["CodexQuotaCore"]),
        .testTarget(name: "CodexQuotaCoreTests", dependencies: ["CodexQuotaCore"])
    ]
)
