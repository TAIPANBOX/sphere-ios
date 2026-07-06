// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SphereCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v11),
    ],
    products: [
        .library(name: "SphereCore", targets: ["SphereCore"]),
        .library(name: "SphereUI", targets: ["SphereUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "SphereCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "SphereUI",
            dependencies: ["SphereCore"],
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "SphereCoreTests",
            dependencies: ["SphereCore", "SphereUI"]
        ),
    ]
)
