// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "IanKit",
  platforms: [.macOS(.v14)],
  products: [
    .library(
      name: "IanKit",
      targets: ["Contract", "Auth", "Client", "Store", "Attention", "Surface", "Features"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-http-types", .upToNextMinor(from: "1.8.0")),
    .package(url: "https://github.com/apple/swift-openapi-runtime", .upToNextMinor(from: "1.13.1")),
    .package(
      url: "https://github.com/apple/swift-openapi-urlsession", .upToNextMinor(from: "1.3.2")),
  ],
  targets: [
    .target(
      name: "Contract",
      dependencies: [
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
      ],
      exclude: ["openapi-generator-config.yaml"]
    ),
    .target(name: "Auth"),
    .target(
      name: "Client",
      dependencies: [
        "Contract",
        "Auth",
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
      ]
    ),
    .target(name: "Store", dependencies: ["Contract", "Client"]),
    .target(name: "Attention", dependencies: ["Store"]),
    .target(name: "Surface", dependencies: ["Store", "Attention"]),
    .target(name: "Features", dependencies: ["Store", "Surface", "Attention"]),
    .testTarget(
      name: "ContractTests",
      dependencies: [
        "Contract",
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
      ],
      resources: [.copy("Fixtures")]
    ),
    .target(
      name: "TestSupport",
      dependencies: [
        "Auth", "Client", "Contract",
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
      ],
      path: "Tests/TestSupport"
    ),
    .testTarget(name: "AuthTests", dependencies: ["Auth", "TestSupport"]),
    .testTarget(
      name: "ClientTests",
      dependencies: [
        "Auth", "Client", "Contract", "TestSupport",
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
      ]
    ),
    .testTarget(
      name: "StoreTests",
      dependencies: ["Client", "Contract", "Store", "TestSupport"]
    ),
    .testTarget(name: "AttentionTests", dependencies: ["Attention"]),
    .testTarget(name: "SurfaceTests", dependencies: ["Surface"]),
    .testTarget(name: "FeaturesTests", dependencies: ["Features"]),
  ],
  swiftLanguageModes: [.v6]
)
