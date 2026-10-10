// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CopyTrading",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DesktopCore", targets: ["DesktopCore"]),
        .library(name: "CopyTradingUI", targets: ["CopyTradingUI"]),
        .executable(name: "CopyTrading", targets: ["CopyTrading"]),
    ],
    dependencies: [
        // Updates: the standard updater for Mac apps outside the App Store (ADR-0009).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(
            name: "DesktopCore",
            path: ".",
            exclude: [
                "Sources/CopyTrading", "Sources/CopyTradingApp", "Sources/AppLocalizationCore", "Tests", ".build", "Resources/Contracts",
                "Resources/Helpers",
                "Resources/Info.plist",
                "Resources/AppIcon.icns", "Resources/DMG", "scripts",
            ],
            sources: ["Sources/DesktopCore"],
            resources: [.copy("Resources/Runtime")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "AppLocalizationCore",
            path: "Sources/AppLocalizationCore",
            resources: [.process("Resources")]
        ),
        // Every screen lives in a library so Xcode can preview it; the app is only its entry point.
        .target(
            name: "CopyTradingUI",
            dependencies: ["DesktopCore", "AppLocalizationCore"],
            path: "Sources/CopyTrading",
            resources: [.copy("Resources/Fonts")]
        ),
        .executableTarget(
            name: "CopyTrading",
            dependencies: ["CopyTradingUI", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/CopyTradingApp",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .target(
            name: "CopyTradingTestSupport",
            dependencies: ["DesktopCore"],
            path: "Tests/TestSupport"
        ),
        .testTarget(
            name: "DesktopCoreTests",
            dependencies: ["DesktopCore", "CopyTradingTestSupport"],
            path: "Tests/DesktopCoreTests"
        ),
        .testTarget(
            name: "DesktopCoreXCTests",
            dependencies: ["DesktopCore", "AppLocalizationCore"],
            path: "Tests/DesktopCoreXCTests",
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "CopyTradingContractTests",
            dependencies: ["DesktopCore", "AppLocalizationCore", "CopyTradingTestSupport"],
            path: "Tests/CopyTradingContractTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
