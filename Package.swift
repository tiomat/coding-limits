// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CodingLimitsMenuBar",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "CodingLimitsMenuBar", targets: ["CodingLimitsMenuBar"]),
  ],
  targets: [
    .executableTarget(name: "CodingLimitsMenuBar"),
  ]
)
