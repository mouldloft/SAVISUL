// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SAVISUL",
    platforms: [.macOS("14.2")],
    products: [
        .executable(name: "SAVISUL", targets: ["SAVISUL"])
    ],
    targets: [
        .target(
            name: "SMCBridge",
            path: "Sources/SMCBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "SAVISUL",
            dependencies: ["SMCBridge"],
            path: "Sources/SAVISUL",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuickLookThumbnailing"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("EventKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreMediaIO")
            ]
        ),
        .testTarget(
            name: "SAVISULTests",
            dependencies: ["SAVISUL"],
            path: "Tests/SAVISULTests"
        )
    ]
)
