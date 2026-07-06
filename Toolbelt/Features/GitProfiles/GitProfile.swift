//
//  GitProfile.swift
//  Toolbelt
//

import Foundation

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

    /// `defaults` — шов для тестов: в них подставляется отдельный suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    func replace(with newProfiles: [GitProfile]) {
        profiles = newProfiles
        do {
            defaults.set(try JSONEncoder().encode(newProfiles), forKey: Self.storageKey)
        } catch {
            Log.storage.error("Не удалось сохранить профили: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ data: Data?) -> [GitProfile] {
        guard let data else { return [] }
        do {
            return try JSONDecoder().decode([GitProfile].self, from: data)
        } catch {
            Log.storage.error("Профили повреждены, начинаем с пустого списка: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
