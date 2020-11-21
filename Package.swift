// swift-tools-version:5.3

import PackageDescription

let package = Package(
  name: "Playback",
  platforms: [
    .iOS(.v13), .macOS(.v10_15)
  ],
  products: [
    .library(
      name: "Playback",
      targets: ["Playback"]),
  ],
  dependencies: [
  ],
  targets: [
    .target(
      name: "Playback",
      dependencies: []),
    .testTarget(
      name: "PlaybackTests",
      dependencies: ["Playback"]),
  ]
)
