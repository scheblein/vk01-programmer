// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VK01Programmer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "VK01Core", targets: ["VK01Core"]),
        .executable(name: "vk01-cli", targets: ["VK01CLI"]),
        .executable(name: "VK01Programmer", targets: ["VK01Programmer"])
    ],
    targets: [
        .target(
            name: "VK01Core",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("Foundation")
            ]
        ),
        .executableTarget(
            name: "VK01CLI",
            dependencies: ["VK01Core"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/CLIInfo.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "VK01Programmer",
            dependencies: ["VK01Core"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
