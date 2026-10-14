// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallpaperManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WallpaperManager", targets: ["WallpaperApp"]),
        .library(name: "WallpaperCore", targets: ["WallpaperCore"]),
    ],
    targets: [
        .target(name: "WallpaperCore"),
        .executableTarget(
            name: "WallpaperApp",
            dependencies: ["WallpaperCore"]
        ),
        .testTarget(
            name: "WallpaperCoreTests",
            dependencies: ["WallpaperCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
