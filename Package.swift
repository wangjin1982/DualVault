// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DualVault",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DualVault",
            path: "Sources/DualVault",
            linkerSettings: [.linkedLibrary("z")] // 系统 libz：zip 需要的 raw deflate（Compression 框架仅提供 zlib 包装流）
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["DualVault"],
            path: "Tests/CoreTests"
        )
    ]
)
