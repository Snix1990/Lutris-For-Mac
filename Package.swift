// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LutrisForMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],

    products: [
        .executable(name: "LutrisForMac", targets: ["LutrisForMacApp"]),
        .executable(name: "LutrisForMacConsole", targets: ["LutrisForMacConsole"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LutrisForMacCore",
            dependencies: [],
            path: "Sources/LutrisForMacCore"
        ),
        .executableTarget(
            name: "LutrisForMacApp",
            dependencies: ["LutrisForMacCore"],
            path: "Sources/LutrisForMacApp",
            exclude: ["Info.plist"],
            resources: [.copy("Locals")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/LutrisForMacApp/Info.plist"])
            ]
        ),
        .executableTarget(
            name: "LutrisForMacConsole",
            dependencies: ["LutrisForMacCore"],
            path: "Sources/LutrisForMacConsole",
            exclude: ["Info.plist"],
            resources: [.copy("Locals")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/LutrisForMacConsole/Info.plist"])
            ]
        ),
        .testTarget(
            name: "LutrisForMacTests",
            dependencies: ["LutrisForMacCore"],
            path: "Tests/LutrisForMacTests"
        ),
    ]
)
