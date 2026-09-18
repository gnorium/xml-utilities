// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "XMLUtilities",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "XMLUtilities", targets: ["XMLUtilities"])
  ],
  targets: [
    .target(
      name: "XMLUtilities",
      swiftSettings: [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("StrictConcurrency"),
        .enableExperimentalFeature("Embedded", .when(platforms: [.wasi])),
        .define("CLIENT", .when(platforms: [.wasi])),
        .define("SERVER", .when(platforms: [.macOS, .linux, .windows])),
      ]
    )
  ]
)
