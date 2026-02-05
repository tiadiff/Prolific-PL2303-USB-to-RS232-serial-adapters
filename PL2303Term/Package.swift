// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PL2303Term",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PL2303Term", targets: ["PL2303Term"])
    ],
    targets: [
        .target(
            name: "PL2303DriverCore",
            dependencies: [],
            path: "Sources/PL2303DriverCore",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .executableTarget(
            name: "PL2303Term",
            dependencies: ["PL2303DriverCore"],
            path: "Sources/PL2303Term"
        ),
    ]
)
