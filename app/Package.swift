// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CopyTrading",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "DesktopCore", targets: ["DesktopCore"]),
        .executable(name: "CopyTrading", targets: ["CopyTrading"]),
    ],
    targets: [
        .target(
            name: "DesktopCore",
            path: ".",
            exclude: [
                "Sources/CopyTrading", "Sources/AppLocalizationCore", "Tests", ".build", "Resources/Contracts", "Resources/Helpers",
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
        .executableTarget(
            name: "CopyTrading",
            dependencies: ["DesktopCore", "AppLocalizationCore"],
            path: "Sources/CopyTrading"
        ),
        .testTarget(
            name: "DesktopCoreTests",
            dependencies: ["DesktopCore"],
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
            dependencies: ["DesktopCore", "AppLocalizationCore"],
            path: "Tests/CopyTradingContractTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
