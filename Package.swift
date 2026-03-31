// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingRecorder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MeetingRecorder", targets: ["MeetingRecorder"]),
        .library(name: "MeetingRecorderCore", targets: ["MeetingRecorderCore"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MeetingRecorderCore",
            dependencies: [],
            path: "Sources",
            exclude: ["AppEntry"]
        ),
        .executableTarget(
            name: "MeetingRecorder",
            dependencies: ["MeetingRecorderCore"],
            path: "Sources/AppEntry"
        ),
        .testTarget(
            name: "MeetingRecorderTests",
            dependencies: ["MeetingRecorderCore"],
            path: "Tests"
        )
    ]
)
