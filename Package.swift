// swift-tools-version: 6.0
//
//  Tests for the pure logic of the app.
//
//  The Xcode project builds the whole Toolbelt/ folder through a
//  PBXFileSystemSynchronizedRootGroup. This package compiles only the SwiftUI-free
//  files out of that same folder, so `swift test` works locally and in CI without
//  touching project.pbxproj.
//

import PackageDescription

let package = Package(
    name: "ToolbeltCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ToolbeltCore",
            path: "Toolbelt",
            exclude: ["Assets.xcassets"],
            sources: [
                "Core/Locked.swift",
                "Core/Log.swift",
                "Core/Shell.swift",
                "DesignSystem/Formatters.swift",
                "Features/DeepLink/AndroidTools.swift",
                "Features/DeepLink/DeepLinkModels.swift",
                "Features/DeepLink/DeepLinkRunner.swift",
                "Features/ReleaseNotes/ReleaseNotesBuilder.swift",
                "Features/ReleaseNotes/ReleaseNotesModels.swift",
                "Features/Tracker/IssuesBoard.swift",
                "Features/Tracker/TrackerDuration.swift",
                "Features/Tracker/TrackerError.swift",
                "Features/Tracker/TrackerModels.swift",
                "Features/Tracker/WeekReport.swift"
            ],
            // The same language mode as the Xcode project: otherwise the package would
            // check the very same files under strict Swift 6 concurrency while the app
            // is built under Swift 5 rules.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ToolbeltCoreTests",
            dependencies: ["ToolbeltCore"],
            path: "Tests/ToolbeltCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
