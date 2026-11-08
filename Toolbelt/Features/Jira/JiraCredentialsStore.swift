//
//  JiraCredentialsStore.swift
//  Toolbelt
//

import Foundation
import Observation
import OSLog

protocol JiraCredentialsProviding {
    var credentials: JiraCredentials { get }
}

/// The token lives in Keychain, everything else in UserDefaults.
@Observable
@MainActor
final class JiraCredentialsStore: JiraCredentialsProviding {
    static let shared = JiraCredentialsStore()

    private static let service = "app.dima.Toolbelt.jira"
    private static let account = "api-token"
    private static let siteKey = "jira.site"
    private static let emailKey = "jira.email"
    private static let deploymentKey = "jira.deployment"

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    private(set) var credentials: JiraCredentials

    convenience init() {
        self.init(defaults: .standard, keychain: KeychainStore(service: Self.service))
    }

    init(defaults: UserDefaults, keychain: KeychainStore) {
        self.defaults = defaults
        self.keychain = keychain
        credentials = JiraCredentials()
        credentials = load()
    }

    func save(_ newCredentials: JiraCredentials) throws {
        let trimmed = newCredentials.trimmed()
        try keychain.write(trimmed.token, account: Self.account)
        defaults.set(trimmed.site, forKey: Self.siteKey)
        defaults.set(trimmed.email, forKey: Self.emailKey)
        defaults.set(trimmed.deployment.rawValue, forKey: Self.deploymentKey)
        credentials = trimmed
    }

    private func load() -> JiraCredentials {
        let token: String
        do {
            token = try keychain.read(account: Self.account) ?? ""
        } catch {
            Log.storage.error("Could not read the Jira token: \(error.localizedDescription, privacy: .public)")
            token = ""
        }

        return JiraCredentials(
            site: defaults.string(forKey: Self.siteKey) ?? "",
            email: defaults.string(forKey: Self.emailKey) ?? "",
            token: token,
            deployment: JiraDeployment(rawValue: defaults.string(forKey: Self.deploymentKey) ?? "") ?? .cloud
        )
    }
}
