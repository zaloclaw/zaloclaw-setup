// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZClawInstaller",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ZClawInstaller", targets: ["ZClawInstaller"])
    ],
    targets: [
        .executableTarget(
            name: "ZClawInstaller",
            path: "Sources/ZClawInstaller",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
