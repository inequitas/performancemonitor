// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PerformanceApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PerformanceApp",
            path: "Sources/PerformanceApp",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreWLAN")
            ]
        )
    ]
)
