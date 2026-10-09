// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MotoNavigationCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MotoNavigationCore", targets: ["MotoNavigationCore"]),
        .executable(name: "MotoNavigationCoreChecks", targets: ["MotoNavigationCoreChecks"]),
    ],
    targets: [
        .target(name: "MotoNavigationCore"),
        .target(name: "MotoDisplayPreferences", path: "App/DisplayPreferences",
                exclude: ["MotoAmbientPreview.h", "MotoAmbientPreview.mm"]),
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "MotoMapGeometry", dependencies: ["CSQLite"], path: "App/Adapters/OfflineMap",
                exclude: ["OfflineMapSceneCoordinator.swift", "SurroundingMapStore.swift", "MapTilePlanner.swift"],
                sources: ["OfflineMapScene.swift", "SQLiteOfflineMapSceneIndex.swift"]),
        .executableTarget(
            name: "MotoNavigationCoreChecks",
            dependencies: ["MotoNavigationCore"]
        ),
        .testTarget(
            name: "MotoNavigationCoreTests",
            dependencies: ["MotoNavigationCore"]
        ),
        .testTarget(name: "MotoMapGeometryTests", dependencies: ["MotoMapGeometry"]),
        .testTarget(name: "MotoDisplayPreferencesTests", dependencies: ["MotoDisplayPreferences"]),
    ]
)
