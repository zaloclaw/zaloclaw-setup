// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZaloClawSwiftInstaller",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ZaloClawSwiftInstaller", targets: ["ZaloClawSwiftInstaller"])
    ],
    targets: [
        .executableTarget(
            name: "ZaloClawSwiftInstaller",
            path: "Sources/ZaloClawSwiftInstaller"
        )
    ]
)
