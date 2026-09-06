// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShotKey",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ShotKey",
            path: "Sources/ShotKey",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
