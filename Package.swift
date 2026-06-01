// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LutrisForMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LutrisForMac", targets: ["LutrisForMacApp"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LutrisForMacApp",
            dependencies: [],
            path: "Sources/LutrisForMacApp",
            exclude: ["Info.plist"],
            resources: [.copy("Locals")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/LutrisForMacApp/Info.plist"])
            ]
        )
    ]
)
