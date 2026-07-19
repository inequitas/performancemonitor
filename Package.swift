// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PerformanceApp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PerformanceAppCore",
            path: "Sources/PerformanceAppCore"
        ),
        .executableTarget(
            name: "PerformanceApp",
            dependencies: ["PerformanceAppCore"],
            path: "Sources/PerformanceApp",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreWLAN")
            ]
        ),
        .testTarget(
            name: "PerformanceAppCoreTests",
            dependencies: ["PerformanceAppCore"],
            path: "Tests/PerformanceAppCoreTests"
        )
    ]
)
