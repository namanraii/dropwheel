// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dropwheel",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Dropwheel", targets: ["Dropwheel"])
    ],
    targets: [
        .target(
            name: "DropwheelCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
            ]
        ),
        .executableTarget(
            name: "Dropwheel",
            dependencies: ["DropwheelCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ]
)
