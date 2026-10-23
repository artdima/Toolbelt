//
//  LinkedInAccess.swift
//  Toolbelt
//
//  Which LinkedIn tools Claude sees, and which account a call acts as. Writing is
//  behind Allow write on the resource, checked both when tools are listed and when
//  one is called: a client may still hold a list from before the switch went off.
//

import Foundation

nonisolated enum LinkedInAccessError: LocalizedError, Equatable {
    case noneEnabled
    case accountRequired(enabled: [String])
    case unknownAccount(String, enabled: [String])
    case turnedOff(String)
    case writeNotAllowed(String)
    case dailyLimit(Int)

    var errorDescription: String? {
        switch self {
        case .noneEnabled:
            return "No LinkedIn account is turned on in Toolbelt."
        case let .accountRequired(enabled):
            return "Several LinkedIn accounts are enabled, so pass account: one of \(Self.list(enabled))."
        case let .unknownAccount(name, enabled):
            return "Toolbelt has no LinkedIn account “\(name)”. Enabled: \(Self.list(enabled))."
        case let .turnedOff(name):
            return "The LinkedIn account “\(name)” is turned off in Toolbelt."
        case let .writeNotAllowed(name):
            return "Allow write is off for the LinkedIn account “\(name)”. The user turns it on in Toolbelt → MCP."
        case let .dailyLimit(limit):
            return "Toolbelt already published \(limit) posts through this account in the last 24 hours, its own limit. Try again later."
        }
    }

    private static func list(_ names: [String]) -> String {
        names.isEmpty ? "none" : names.joined(separator: ", ")
    }
}

nonisolated enum LinkedInAccess {
    static let readTools = ["linkedin_accounts", "linkedin_profile", "linkedin_recent_posts"]
    static let writeTools = ["linkedin_create_post", "linkedin_delete_post"]

    static func isWriteTool(_ name: String) -> Bool {
        writeTools.contains(name)
    }

    /// For the enabled resources: the write tools only while one of them allows writing.
    static func toolNames(for enabled: [MCPResource]) -> [String] {
        guard !enabled.isEmpty else { return [] }
        return enabled.contains(where: \.allowWrite) ? readTools + writeTools : readTools
    }

    /// `account` may be left out while a single resource is enabled; it is matched against
    /// resource names, ignoring case.
    static func resource(
        account: String?,
        in resources: [MCPResource],
        forWriting: Bool
    ) throws -> MCPResource {
        let enabled = resources.filter(\.isEnabled)
        let names = enabled.map(\.name)

        let resource: MCPResource
        if let account = account?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty {
            guard let match = resources.first(where: { $0.name.lowercased() == account.lowercased() }) else {
                throw LinkedInAccessError.unknownAccount(account, enabled: names)
            }
            guard match.isEnabled else { throw LinkedInAccessError.turnedOff(match.name) }
            resource = match
        } else {
            guard !enabled.isEmpty else { throw LinkedInAccessError.noneEnabled }
            guard enabled.count == 1 else { throw LinkedInAccessError.accountRequired(enabled: names) }
            resource = enabled[0]
        }

        if forWriting, !resource.allowWrite {
            throw LinkedInAccessError.writeNotAllowed(resource.name)
        }
        return resource
    }
}
