//
//  MCPViewModel.swift
//  Toolbelt
//

import AppKit
import Observation
import SwiftUI

struct MCPNotice: Equatable {
    let text: String
    let isError: Bool
}

@Observable
@MainActor
final class MCPViewModel {
    let hub: MCPHub
    let store: MCPResourceStore
    let helperPath: String?

    private(set) var desktopStatus = ClaudeDesktopConfig.Status.notConnected
    private(set) var desktopNotice: MCPNotice?
    private(set) var isCommandCopied = false
    private(set) var accountErrors: [MCPResource.ID: String] = [:]
    private(set) var isChecking = false

    convenience init() {
        self.init(hub: .shared, store: .shared)
    }

    init(hub: MCPHub, store: MCPResourceStore) {
        self.hub = hub
        self.store = store
        helperPath = Bundle.main.url(forAuxiliaryExecutable: "toolbelt-mcp")?.path(percentEncoded: false)
        refreshDesktopStatus()
    }

    var claudeCodeCommand: String? {
        helperPath.map(ClaudeCodeCommand.add(helperPath:))
    }

    var desktopStatusText: String {
        switch desktopStatus {
        case .notInstalled: "Not installed"
        case .notConnected: "Not connected"
        case .connected: "Connected"
        case .otherPath: "Points at another copy of Toolbelt"
        case .unreadable: "Its config is unreadable"
        }
    }

    var desktopButtonTitle: String {
        switch desktopStatus {
        case .connected: "Connected"
        case .otherPath: "Point It Here"
        default: "Connect to Claude Desktop"
        }
    }

    // MARK: Claude

    func refreshDesktopStatus() {
        guard let helperPath else { return }
        desktopStatus = ClaudeDesktopConfig.status(helperPath: helperPath)
    }

    func connectClaudeDesktop() {
        guard let helperPath else {
            desktopNotice = MCPNotice(text: "toolbelt-mcp is missing from the app bundle. Rebuild Toolbelt.", isError: true)
            return
        }
        do {
            let result = try ClaudeDesktopConfig.install(helperPath: helperPath)
            var text = "Quit and reopen Claude Desktop to load Toolbelt."
            if let backup = result.backupURL {
                text += " The previous config is saved as \(backup.lastPathComponent)."
            }
            desktopNotice = MCPNotice(text: text, isError: false)
        } catch {
            desktopNotice = MCPNotice(text: error.localizedDescription, isError: true)
        }
        refreshDesktopStatus()
    }

    func dismissDesktopNotice() {
        desktopNotice = nil
    }

    func copyClaudeCodeCommand() {
        guard let claudeCodeCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(claudeCodeCommand, forType: .string)
        isCommandCopied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            isCommandCopied = false
        }
    }

    // MARK: Resources

    /// Re-reads the user and the token expiry, so a token that expired or was revoked shows up.
    func recheckAccounts() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        for resource in store.resources where resource.isEnabled {
            guard let token = store.token(for: resource.id) else {
                accountErrors[resource.id] = "No token in Keychain"
                continue
            }
            let provider = MCPProviders.provider(for: resource.kind)
            let clientSecret = provider.asksForClientCredentials ? store.clientSecret(for: resource.id) : nil
            let setup = MCPSetup(baseURL: resource.baseURL, token: token, clientID: resource.clientID, clientSecret: clientSecret)
            do {
                let validation = try await provider.validate(setup)
                store.setAccount(validation.account, for: resource.id)
                accountErrors[resource.id] = nil
            } catch {
                let secrets = [token, clientSecret].compactMap { $0 }
                accountErrors[resource.id] = MCPText.redacting(secrets, in: error.localizedDescription)
            }
        }
    }

    func forgetError(for id: MCPResource.ID) {
        accountErrors[id] = nil
    }

    static func expiryText(_ account: MCPAccount, now: Date = Date()) -> (text: String, tint: Color?) {
        switch account.expiry {
        case .unknown:
            return ("token expiry unknown", nil)
        case .never:
            return ("token never expires", nil)
        case let .on(date):
            let day = AppFormatters.shortDay.string(from: date)
            if account.isExpired(now: now) { return ("token expired \(day)", .red) }
            let days = account.daysLeft(now: now) ?? 0
            let left = days == 0 ? "today" : "in \(Plural.counted(days, "day", "days"))"
            return ("token expires \(day), \(left)", account.expiresSoon(now: now) ? .orange : nil)
        }
    }
}
