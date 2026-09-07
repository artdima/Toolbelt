//
//  DerivedDataCleaner.swift
//  Toolbelt
//

import Foundation

nonisolated enum DerivedDataCleanOutcome {
    case removed
    case nothingToRemove
}

protocol DerivedDataCleaning {
    func clean() async throws -> DerivedDataCleanOutcome
}

struct DerivedDataCleaner: DerivedDataCleaning {
    /// The folder is often moved to another volume with a symlink. `fileExists`
    /// follows the link and `removeItem` does not, so the path is resolved up front:
    /// otherwise only the symlink would be deleted while the user is told "done".
    func clean() async throws -> DerivedDataCleanOutcome {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
            .resolvingSymlinksInPath()

        // The folder weighs tens of gigabytes: deleting it on the main thread
        // freezes the app.
        return try await Task.detached(priority: .utility) { () throws -> DerivedDataCleanOutcome in
            let manager = FileManager.default
            guard manager.fileExists(atPath: url.path) else { return .nothingToRemove }
            try manager.removeItem(at: url)
            return .removed
        }.value
    }
}
