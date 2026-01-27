// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeetingRecorder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MeetingRecorder", targets: ["MeetingRecorder"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MeetingRecorder",
            dependencies: [],
            path: "Sources"
        )
    ]
)
