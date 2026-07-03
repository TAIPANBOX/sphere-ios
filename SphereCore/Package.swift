// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SphereCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "SphereCore", targets: ["SphereCore"]),
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
        .testTarget(
            name: "SphereCoreTests",
            dependencies: ["SphereCore"]
        ),
    ]
)
