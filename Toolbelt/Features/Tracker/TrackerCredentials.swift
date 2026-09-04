//
//  TrackerCredentials.swift
//  Toolbelt
//

import Observation
import OSLog
import SwiftUI

struct TrackerCredentials: Equatable {
    var token = ""
    var orgId = ""
    var orgKind: TrackerOrgKind = .yandex360

    var isConfigured: Bool { !token.isEmpty && !orgId.isEmpty }

    func trimmed() -> TrackerCredentials {
        TrackerCredentials(
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            orgId: orgId.trimmingCharacters(in: .whitespacesAndNewlines),
            orgKind: orgKind
        )
    }
}

protocol TrackerCredentialsProviding {
    var credentials: TrackerCredentials { get }
}

/// Единственный источник правды: и UI, и сетевой клиент читают отсюда.
/// Токен лежит в Keychain, остальное — в UserDefaults.
@Observable
@MainActor
final class TrackerCredentialsStore: TrackerCredentialsProviding {
    static let shared = TrackerCredentialsStore()

    private static let service = "app.dima.Toolbelt.tracker"
    private static let account = "oauth-token"
    private static let orgIdKey = "tracker.orgId"
    private static let orgKindKey = "tracker.orgKind"

    /// Хранилища до переименования проекта в Toolbelt.
    private static let legacyService = "app.dima.GitSwitcher.tracker"
    private static let legacySuite = "app.dima.GitSwitcher"
    private static let migrationKey = "tracker.migratedFromGitSwitcher"

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    private(set) var credentials: TrackerCredentials

    convenience init() {
        self.init(defaults: .standard, keychain: KeychainStore(service: Self.service))
    }

    init(defaults: UserDefaults, keychain: KeychainStore) {
        self.defaults = defaults
        self.keychain = keychain
        credentials = TrackerCredentials()
        credentials = load()
    }

    func save(_ newCredentials: TrackerCredentials) throws {
        let trimmed = newCredentials.trimmed()
        // Keychain пишется первым: если он откажет, в памяти и в UserDefaults
        // не должно остаться состояния, которого нет на диске.
        try keychain.write(trimmed.token, account: Self.account)
        defaults.set(trimmed.orgId, forKey: Self.orgIdKey)
        defaults.set(trimmed.orgKind.rawValue, forKey: Self.orgKindKey)
        credentials = trimmed
    }

    /// Однократный перенос со старого bundle id. Флаг ставится только после успеха:
    /// иначе сбой Keychain навсегда оставил бы пользователя без токена.
    func migrateLegacyStorageIfNeeded() {
        guard !defaults.bool(forKey: Self.migrationKey) else { return }

        do {
            if try keychain.read(account: Self.account) == nil {
                let legacyKeychain = KeychainStore(service: Self.legacyService)
                if let legacyToken = try legacyKeychain.read(account: Self.account) {
                    try keychain.write(legacyToken, account: Self.account)
                }
            }

            if let legacy = UserDefaults(suiteName: Self.legacySuite) {
                if defaults.string(forKey: Self.orgIdKey) == nil,
                   let value = legacy.string(forKey: Self.orgIdKey) {
                    defaults.set(value, forKey: Self.orgIdKey)
                }
                if defaults.string(forKey: Self.orgKindKey) == nil,
                   let value = legacy.string(forKey: Self.orgKindKey) {
                    defaults.set(value, forKey: Self.orgKindKey)
                }
            }

            defaults.set(true, forKey: Self.migrationKey)
            credentials = load()
        } catch {
            Log.storage.error("Миграция настроек Трекера не удалась: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() -> TrackerCredentials {
        let token: String
        do {
            token = try keychain.read(account: Self.account) ?? ""
        } catch {
            Log.storage.error("Не удалось прочитать токен: \(error.localizedDescription, privacy: .public)")
            token = ""
        }

        return TrackerCredentials(
            token: token,
            orgId: defaults.string(forKey: Self.orgIdKey) ?? "",
            orgKind: TrackerOrgKind(rawValue: defaults.string(forKey: Self.orgKindKey) ?? "") ?? .yandex360
        )
    }
}
