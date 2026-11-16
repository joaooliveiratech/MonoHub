// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "MonoHub",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .executable(
            name: "MonoHub",
            targets: ["MonoHub"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MonoHub",
            path: "Sources/MonoHub",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility")
            ]
        ),
        .testTarget(
            name: "MonoHubTests",
            dependencies: ["MonoHub"],
            path: "Tests/MonoHubTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
