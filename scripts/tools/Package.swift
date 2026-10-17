// swift-tools-version: 6.0
// Build tools run from scripts: the OpenAPI generator, XcodeGen and the example extractor.
import PackageDescription

let package = Package(
  name: "IanTools",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator", exact: "1.14.1"),
    .package(url: "https://github.com/yonaskolb/XcodeGen", exact: "2.46.0"),
    .package(url: "https://github.com/jpsim/Yams.git", exact: "5.4.0"),
  ],
  targets: [
    .executableTarget(
      name: "extract-examples",
      dependencies: [.product(name: "Yams", package: "Yams")]
    )
  ]
)
