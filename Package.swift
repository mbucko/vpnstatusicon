// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VPNStatusIcon",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VPNStatusIcon",
            path: "VPNStatusIcon",
            exclude: ["Info.plist"]
        ),
    ]
)
