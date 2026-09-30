// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GMSnagNav",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "GMSnagNav", targets: ["GMSnagNav"])
    ],
    targets: [
        .target(name: "GMSnagNav"),
        .testTarget(
            name: "GMSnagNavTests",
            dependencies: ["GMSnagNav"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
