//
//  GitProfile.swift
//  Toolbelt
//

import Foundation
import Observation
import OSLog

struct GitProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var email: String
    var displayName: String

    var title: String { displayName.isEmpty ? name : displayName }

    var identity: GitIdentity { GitIdentity(name: name, email: email) }

    var isComplete: Bool { !name.isEmpty && !email.isEmpty }

    func trimmed() -> GitProfile {
        GitProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

@Observable
final class GitProfileStore {
    static let shared = GitProfileStore()

    private static let storageKey = "git.profiles"

    private let defaults: UserDefaults
    private(set) var profiles: [GitProfile]

    /// `defaults` is the seam for tests: they pass a separate suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    func replace(with newProfiles: [GitProfile]) {
        profiles = newProfiles
        do {
            defaults.set(try JSONEncoder().encode(newProfiles), forKey: Self.storageKey)
        } catch {
            Log.storage.error("Could not save profiles: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ data: Data?) -> [GitProfile] {
        guard let data else { return [] }
        do {
            return try JSONDecoder().decode([GitProfile].self, from: data)
        } catch {
            Log.storage.error("Profiles are corrupted, starting empty: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
