// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Keep the ordinary local build completely offline. Sparkle is resolved only
// for an explicit direct-distribution build:
//   CLASP_DIRECT_DISTRIBUTION=1 swift build -Xswiftc -DCLASP_DIRECT_DISTRIBUTION
let directDistribution = ProcessInfo.processInfo.environment["CLASP_DIRECT_DISTRIBUTION"] == "1"

let package = Package(
    name: "PersonalNotepad",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clasp", targets: ["PersonalNotepad"])
    ],
    dependencies: directDistribution ? [
        // Exact pin. Sparkle 2.9.6's SwiftPM artifact checksum is
        // 8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ] : [],
    targets: [
        .executableTarget(
            name: "PersonalNotepad",
            dependencies: directDistribution ? [
                .product(name: "Sparkle", package: "Sparkle")
            ] : [],
            path: "Sources/PersonalNotepad",
            linkerSettings: directDistribution ? [
                .linkedFramework("Security"),
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ] : [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "PersonalNotepadTests",
            dependencies: ["PersonalNotepad"],
            path: "Tests/PersonalNotepadTests"
        )
    ]
)
