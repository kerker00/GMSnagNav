// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "GMSnagNav",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    .library(name: "GMSnagNav", targets: ["GMSnagNav"])
  ],
  targets: [
    .target(
      name: "GMSnagNav",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "GMSnagNavTests",
      dependencies: ["GMSnagNav"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
