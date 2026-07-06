//
//  GitConfigService.swift
//  Toolbelt
//

import Foundation

struct GitIdentity: Equatable {
    let name: String
    let email: String
}

enum GitConfigError: LocalizedError, Equatable {
    case rejectedValue(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .rejectedValue(value):
            return "Значение «\(value)» начинается с дефиса и будет разобрано git как опция"
        case let .commandFailed(message):
            return message
        }
    }
}

protocol GitConfigService {
    func currentIdentity() async throws -> GitIdentity
    func apply(_ identity: GitIdentity) async throws
}

/// Читает и пишет `git config --global`.
struct SystemGitConfigService: GitConfigService {
    private let git = ExecutablePath.git

    func currentIdentity() async throws -> GitIdentity {
        async let name = value(forKey: "user.name")
        async let email = value(forKey: "user.email")
        return GitIdentity(name: try await name, email: try await email)
    }

    func apply(_ identity: GitIdentity) async throws {
        // git не умеет `--` перед значением, поэтому строку, начинающуюся с дефиса,
        // он разберёт как опцию. Отсекаем до запуска процесса.
        try validate(identity.name)
        try validate(identity.email)

        try await set(key: "user.name", value: identity.name)
        try await set(key: "user.email", value: identity.email)
    }

    private func validate(_ value: String) throws {
        guard !value.hasPrefix("-") else { throw GitConfigError.rejectedValue(value) }
    }

    private func value(forKey key: String) async throws -> String {
        let result = try await Shell.run(git, ["config", "--global", key])
        // Код 1 без вывода означает «значение не задано», это не ошибка.
        guard result.isSuccess || result.exitCode == 1 else {
            throw GitConfigError.commandFailed(result.combinedOutput)
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func set(key: String, value: String) async throws {
        let result = try await Shell.run(git, ["config", "--global", key, value])
        guard result.isSuccess else {
            throw GitConfigError.commandFailed(result.combinedOutput)
        }
    }
}
