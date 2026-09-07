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

/// The single source of truth: both the UI and the network client read from here.
/// The token lives in Keychain, everything else in UserDefaults.
@Observable
@MainActor
final class TrackerCredentialsStore: TrackerCredentialsProviding {
    static let shared = TrackerCredentialsStore()

    private static let service = "app.dima.Toolbelt.tracker"
    private static let account = "oauth-token"
    private static let orgIdKey = "tracker.orgId"
    private static let orgKindKey = "tracker.orgKind"

    /// Storage used before the project was renamed to Toolbelt.
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
        // Keychain goes first: if it refuses, memory and UserDefaults must not hold
        // state that never made it to disk.
        try keychain.write(trimmed.token, account: Self.account)
        defaults.set(trimmed.orgId, forKey: Self.orgIdKey)
        defaults.set(trimmed.orgKind.rawValue, forKey: Self.orgKindKey)
        credentials = trimmed
    }

    /// A one-off move from the old bundle id. The flag is set only after success:
    /// otherwise a Keychain failure would leave the user without a token forever.
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
            Log.storage.error("Tracker settings migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() -> TrackerCredentials {
        let token: String
        do {
            token = try keychain.read(account: Self.account) ?? ""
        } catch {
            Log.storage.error("Could not read the token: \(error.localizedDescription, privacy: .public)")
            token = ""
        }

        return TrackerCredentials(
            token: token,
            orgId: defaults.string(forKey: Self.orgIdKey) ?? "",
            orgKind: TrackerOrgKind(rawValue: defaults.string(forKey: Self.orgKindKey) ?? "") ?? .yandex360
        )
    }
}
