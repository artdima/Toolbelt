//
//  GitProfiles.swift
//  Toolbelt
//
//  Профили git-пользователей: модель и хранение в UserDefaults.
//  Редактирование — в разделе «Профили Git» общих настроек.
//

import Observation
import SwiftUI

struct GitProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var displayName: String
}

@Observable
final class GitProfileStore {
    static let shared = GitProfileStore()

    private static let storageKey = "git.profiles"

    private(set) var profiles: [GitProfile]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey)
        profiles = data.flatMap { try? JSONDecoder().decode([GitProfile].self, from: $0) } ?? []
    }

    func replace(with newProfiles: [GitProfile]) {
        profiles = newProfiles
        guard let data = try? JSONEncoder().encode(newProfiles) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
