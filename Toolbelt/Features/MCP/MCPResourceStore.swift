//
//  MCPResourceStore.swift
//  Toolbelt
//
//  MCP resources live in UserDefaults; their tokens and client secrets only in Keychain.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class MCPResourceStore {
    static let shared = MCPResourceStore()

    private static let storageKey = "mcp.resources"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored var onChange: (() -> Void)?

    private(set) var resources: [MCPResource]

    convenience init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "app.artdima.Toolbelt"
        self.init(defaults: .standard, keychain: KeychainStore(service: "\(bundleID).mcp"))
    }

    init(defaults: UserDefaults, keychain: KeychainStore) {
        self.defaults = defaults
        self.keychain = keychain
        resources = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    func resource(_ id: MCPResource.ID) -> MCPResource? {
        resources.first { $0.id == id }
    }

    func token(for id: MCPResource.ID) -> String? {
        read(account: Self.tokenAccount(id), what: "token")
    }

    func clientSecret(for id: MCPResource.ID) -> String? {
        read(account: Self.clientSecretAccount(id), what: "client secret")
    }

    /// Keychain goes first: a resource must not be listed with a secret that was never stored.
    func add(_ resource: MCPResource, token: String, clientSecret: String? = nil) throws {
        try keychain.write(token, account: Self.tokenAccount(resource.id))
        if let clientSecret = Self.nonEmpty(clientSecret) {
            do {
                try keychain.write(clientSecret, account: Self.clientSecretAccount(resource.id))
            } catch {
                try? keychain.delete(account: Self.tokenAccount(resource.id))
                throw error
            }
        }
        resources.append(resource)
        persist()
    }

    /// A nil or empty secret keeps the stored one.
    func update(_ resource: MCPResource, token: String?, clientSecret: String? = nil) throws {
        guard let index = resources.firstIndex(where: { $0.id == resource.id }) else { return }
        if let token = Self.nonEmpty(token) {
            try keychain.write(token, account: Self.tokenAccount(resource.id))
        }
        if let clientSecret = Self.nonEmpty(clientSecret) {
            try keychain.write(clientSecret, account: Self.clientSecretAccount(resource.id))
        }
        resources[index] = resource
        persist()
    }

    func delete(_ id: MCPResource.ID) throws {
        try keychain.delete(account: Self.tokenAccount(id))
        try keychain.delete(account: Self.clientSecretAccount(id))
        resources.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ isEnabled: Bool, for id: MCPResource.ID) {
        modify(id) { $0.isEnabled = isEnabled }
    }

    func setAllowWrite(_ allowWrite: Bool, for id: MCPResource.ID) {
        modify(id) { $0.allowWrite = allowWrite }
    }

    func setAccount(_ account: MCPAccount?, for id: MCPResource.ID) {
        modify(id) { $0.account = account }
    }

    func isNameTaken(_ name: String, except id: MCPResource.ID?) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return resources.contains { $0.id != id && $0.name.lowercased() == wanted }
    }

    private func read(account: String, what: String) -> String? {
        do {
            return try keychain.read(account: account)
        } catch {
            Log.mcp.error("Could not read a resource \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func tokenAccount(_ id: MCPResource.ID) -> String {
        id.uuidString
    }

    private static func clientSecretAccount(_ id: MCPResource.ID) -> String {
        "\(id.uuidString).client-secret"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func modify(_ id: MCPResource.ID, _ change: (inout MCPResource) -> Void) {
        guard let index = resources.firstIndex(where: { $0.id == id }) else { return }
        var resource = resources[index]
        change(&resource)
        guard resource != resources[index] else { return }
        resources[index] = resource
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(resources), forKey: Self.storageKey)
        } catch {
            Log.mcp.error("Could not save MCP resources: \(error.localizedDescription, privacy: .public)")
        }
        onChange?()
    }

    private static func decode(_ data: Data?) -> [MCPResource] {
        guard let data else { return [] }
        do {
            return try JSONDecoder().decode([MCPResource].self, from: data)
        } catch {
            Log.mcp.error("MCP resources are corrupted, starting empty: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
