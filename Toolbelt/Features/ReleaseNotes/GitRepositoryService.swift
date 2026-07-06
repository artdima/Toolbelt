//
//  GitRepositoryService.swift
//  Toolbelt
//

import Foundation

enum GitRepositoryError: LocalizedError, Equatable {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message): return message
        }
    }
}

protocol GitRepositoryReading {
    func isRepository(at path: String) async -> Bool
    func tags(at path: String) async throws -> [String]
    func commitSubjects(at path: String, from: String?, to: String) async throws -> [String]
}

struct GitRepositoryService: GitRepositoryReading {
    static let headRef = "HEAD"

    /// git читает конфиг открываемого репозитория, а `core.fsmonitor` и хуки
    /// умеют запускать внешние команды. Для чужого репозитория это исполнение кода,
    /// поэтому обе точки расширения выключаются явно.
    private var safeArguments: [String] {
        ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"]
    }

    func isRepository(at path: String) async -> Bool {
        let result = try? await Shell.run(
            ExecutablePath.git,
            safeArguments + ["-C", path, "rev-parse", "--is-inside-work-tree"]
        )
        return result?.isSuccess ?? false
    }

    func tags(at path: String) async throws -> [String] {
        let result = try await Shell.run(
            ExecutablePath.git,
            safeArguments + ["-C", path, "tag", "--sort=-creatordate"]
        )
        guard result.isSuccess else { return [] }
        return lines(from: result.standardOutput)
    }

    func commitSubjects(at path: String, from: String?, to: String) async throws -> [String] {
        let range = from.map { "\($0)..\(to)" } ?? to
        let result = try await Shell.run(
            ExecutablePath.git,
            safeArguments + [
                "-C", path,
                "log", "--no-merges", "--pretty=format:%s",
                // Имя тега, начинающееся с дефиса, иначе будет разобрано как опция.
                "--end-of-options", range, "--"
            ]
        )

        guard result.isSuccess else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitRepositoryError.commandFailed(
                message.isEmpty ? "git завершился с кодом \(result.exitCode)" : message
            )
        }
        return lines(from: result.standardOutput)
    }

    private func lines(from output: String) -> [String] {
        output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
