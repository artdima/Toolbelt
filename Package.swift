// swift-tools-version: 6.0
//
//  Тесты чистой логики приложения.
//
//  Xcode-проект собирает всю папку Toolbelt/ (PBXFileSystemSynchronizedRootGroup),
//  а этот пакет отдельно компилирует из неё файлы без SwiftUI и AppKit —
//  так `swift test` работает и локально, и в CI, не трогая project.pbxproj.
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
            // Тот же языковой режим, что у Xcode-проекта: иначе пакет собирал бы
            // те же файлы со строгими проверками конкурентности Swift 6,
            // а приложение — по правилам Swift 5.
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
