// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PerformanceApp",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PerformanceAppCore",
            path: "Sources/PerformanceAppCore"
        ),
        .target(
            name: "CNVMeSMART",
            path: "Sources/CNVMeSMART"
        ),
        .target(
            name: "CIOReport",
            path: "Sources/CIOReport"
        ),
        .executableTarget(
            name: "PerformanceApp",
            dependencies: ["PerformanceAppCore", "CNVMeSMART", "CIOReport"],
            path: "Sources/PerformanceApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOKit"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "PerformanceAppCoreTests",
            dependencies: ["PerformanceAppCore"],
            path: "Tests/PerformanceAppCoreTests"
        )
    ]
)
