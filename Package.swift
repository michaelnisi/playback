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
    .package(name: "FeedKit", url: "https://github.com/michaelnisi/feedkit", from: "17.0.0"),
    .package(name: "Nuke", url: "https://github.com/kean/nuke", from: "9.0.0")
  ],
  targets: [
    .target(
      name: "Playback",
      dependencies: ["FeedKit", "Nuke"]),
    .testTarget(
      name: "PlaybackTests",
      dependencies: ["Playback"]),
  ]
)
