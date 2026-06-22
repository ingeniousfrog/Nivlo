// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Nivlo",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "NivloDomain", targets: ["NivloDomain"]),
    .library(name: "NivloIndexing", targets: ["NivloIndexing"]),
    .library(name: "NivloImaging", targets: ["NivloImaging"]),
    .library(name: "NivloPersistence", targets: ["NivloPersistence"]),
    .executable(name: "Nivlo", targets: ["NivloApp"]),
  ],
  targets: [
    .target(name: "NivloDomain"),
    .target(
      name: "NivloIndexing",
      dependencies: ["NivloDomain"]
    ),
    .target(
      name: "NivloImaging",
      dependencies: ["NivloDomain"],
      linkerSettings: [
        .linkedFramework("AppKit")
      ]
    ),
    .target(
      name: "NivloPersistence",
      dependencies: ["NivloDomain"],
      linkerSettings: [.linkedLibrary("sqlite3")]
    ),
    .executableTarget(
      name: "NivloApp",
      dependencies: [
        "NivloDomain",
        "NivloImaging",
        "NivloIndexing",
        "NivloPersistence",
      ],
      linkerSettings: [
        .linkedFramework("AVKit")
      ]
    ),
    .testTarget(
      name: "NivloDomainTests",
      dependencies: ["NivloDomain"]
    ),
    .testTarget(
      name: "NivloIndexingTests",
      dependencies: ["NivloDomain", "NivloIndexing"]
    ),
    .testTarget(
      name: "NivloPersistenceTests",
      dependencies: ["NivloDomain", "NivloPersistence"]
    ),
    .testTarget(
      name: "NivloImagingTests",
      dependencies: ["NivloDomain", "NivloImaging"]
    ),
  ]
)
