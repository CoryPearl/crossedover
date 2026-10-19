// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrossedOver",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CrossedOverCore", targets: ["CrossedOverCore"]),
        .executable(name: "CrossedOver", targets: ["CrossedOver"]),
        .executable(name: "CrossedOverCLI", targets: ["CrossedOverCLI"]),
        .executable(name: "CrossedOverSupervisor", targets: ["CrossedOverSupervisor"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.8.0")
    ],
    targets: [
        .target(name: "CArchive", linkerSettings: [.linkedLibrary("archive")]),
        .target(name: "CrossedOverCore", dependencies: ["CArchive", .product(name: "GRDB", package: "GRDB.swift")], resources: [.process("Resources")]),
        .executableTarget(name: "CrossedOver", dependencies: ["CrossedOverCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "CrossedOverCLI", dependencies: ["CrossedOverCore"]),
        .executableTarget(name: "CrossedOverSupervisor", dependencies: ["CrossedOverCore"]),
        .testTarget(name: "CrossedOverCoreTests", dependencies: ["CrossedOverCore"])
    ]
)
