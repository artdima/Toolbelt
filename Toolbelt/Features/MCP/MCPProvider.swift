//
//  MCPProvider.swift
//  Toolbelt
//
//  What a kind of resource has to offer to become a set of MCP tools.
//

import Foundation
import MCP

/// What a resource is checked with: the editor's fields, or what is stored for it.
nonisolated struct MCPSetup: Sendable {
    let baseURL: URL
    let token: String
    var clientID: String?
    var clientSecret: String?
}

nonisolated struct MCPCredential: Sendable {
    let resource: MCPResource
    /// nil while the resource is turned off: its secrets are not even read.
    let token: String?
    var clientSecret: String?

    /// Everything to scrub from tool answers and the call log.
    var secrets: [String] {
        [token, clientSecret].compactMap { $0 }
    }
}

nonisolated struct MCPToolOutput: Sendable {
    let text: String
    let isError: Bool

    static func success(_ text: String) -> MCPToolOutput {
        MCPToolOutput(text: MCPText.limited(text), isError: false)
    }

    static func failure(_ text: String) -> MCPToolOutput {
        MCPToolOutput(text: MCPText.limited(text), isError: true)
    }
}

nonisolated struct MCPToolError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

nonisolated struct MCPValidation: Sendable {
    let account: MCPAccount
    let warnings: [String]
}

nonisolated struct MCPTokenHint: Sendable {
    let text: String
    let url: URL?
    var linkTitle = "Open the token page"
    var placeholder = "Paste the token"
}

nonisolated protocol MCPProvider: Sendable {
    var kind: MCPResourceKind { get }
    var defaultBaseURL: String { get }
    /// The provider has tools that change data, so Allow write means something.
    var supportsWrite: Bool { get }
    /// false for a service with a single address: the editor does not ask for one.
    var asksForAddress: Bool { get }
    /// The service needs the OAuth app's Client ID and Client Secret besides the token.
    var asksForClientCredentials: Bool { get }

    func tokenHint(for baseURL: URL?) -> MCPTokenHint
    func validate(_ setup: MCPSetup) async throws -> MCPValidation
    /// The second line of the resource in the MCP window.
    func accountLine(_ resource: MCPResource) -> String
    /// Who the token belongs to, after a check in the editor.
    func accountSummary(_ account: MCPAccount) -> String
    /// Shown before Allow write is turned on.
    func writeAccessWarning(for resource: MCPResource) -> String
    func owns(toolName: String) -> Bool
    func tools(for resources: [MCPResource]) -> [Tool]
    func call(_ name: String, arguments: [String: Value], credentials: [MCPCredential]) async -> MCPToolOutput
}

nonisolated enum MCPProviders {
    static let all: [any MCPProvider] = [GitLabProvider()]

    static func provider(for kind: MCPResourceKind) -> any MCPProvider {
        switch kind {
        case .gitlab: GitLabProvider()
        }
    }
}

/// Lenient on types: models send numbers as strings and the other way round.
nonisolated struct ToolArguments: Sendable {
    let values: [String: Value]

    func string(_ key: String) -> String? {
        guard let value = values[key], !value.isNull else { return nil }
        let text = String(value, strict: false)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    func requiredString(_ key: String) throws -> String {
        guard let text = string(key) else { throw MCPToolError("“\(key)” is required") }
        return text
    }

    func int(_ key: String) throws -> Int? {
        guard let value = values[key], !value.isNull else { return nil }
        if let number = Int(value, strict: false) { return number }
        if let number = Double(value, strict: false), let exact = Int(exactly: number) { return exact }
        throw MCPToolError("“\(key)” has to be a whole number")
    }

    func requiredInt(_ key: String) throws -> Int {
        guard let number = try int(key) else { throw MCPToolError("“\(key)” is required") }
        return number
    }

    func int(_ key: String, default fallback: Int, in range: ClosedRange<Int>) throws -> Int {
        min(max(try int(key) ?? fallback, range.lowerBound), range.upperBound)
    }

    static func compactJSON(_ values: [String: Value]) -> String {
        guard !values.isEmpty else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(values) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

nonisolated enum JSONSchema {
    static func object(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": "object",
            "properties": .object(properties)
        ]
        if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
        return .object(schema)
    }

    static func string(_ description: String, values: [String]? = nil) -> Value {
        var schema: [String: Value] = ["type": "string", "description": .string(description)]
        if let values { schema["enum"] = .array(values.map { .string($0) }) }
        return .object(schema)
    }

    static func integer(_ description: String, minimum: Int? = nil, maximum: Int? = nil, default fallback: Int? = nil) -> Value {
        var schema: [String: Value] = ["type": "integer", "description": .string(description)]
        if let minimum { schema["minimum"] = .int(minimum) }
        if let maximum { schema["maximum"] = .int(maximum) }
        if let fallback { schema["default"] = .int(fallback) }
        return .object(schema)
    }

    /// Ids and iids come as numbers or as strings copied from a link.
    static func identifier(_ description: String) -> Value {
        .object([
            "type": .array(["integer", "string"]),
            "description": .string(description)
        ])
    }
}
