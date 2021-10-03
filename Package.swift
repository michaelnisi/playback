// swift-tools-version:5.3
//===----------------------------------------------------------------------===//
//
// This source file is part of the Playback open source project
//
// Copyright (c) 2021 Michael Nisi and collaborators
// Licensed under MIT License
//
// See https://github.com/michaelnisi/epic/blob/main/LICENSE for license information
//
//===----------------------------------------------------------------------===//

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
    .package(name: "Nuke", url: "https://github.com/kean/nuke", from: "9.0.0")
  ],
  targets: [
    .target(
      name: "Playback",
      dependencies: ["Nuke"]),
    .testTarget(
      name: "PlaybackTests",
      dependencies: ["Playback"]),
  ]
)
