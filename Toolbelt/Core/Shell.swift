//
//  Shell.swift
//  Toolbelt
//
//  Запуск внешних команд: git, xcrun, adb.
//

import Foundation

nonisolated struct ShellResult: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32

    var isSuccess: Bool { exitCode == 0 }

    /// Вывод для показа пользователю: stdout и stderr подряд, без пустых строк.
    var combinedOutput: String {
        [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

nonisolated enum ShellError: LocalizedError, Equatable {
    case launchFailed(command: String, reason: String)
    case timedOut(command: String, seconds: Int)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(command, reason):
            return "Не удалось запустить \(command): \(reason)"
        case let .timedOut(command, seconds):
            return "\(command) не ответил за \(seconds) с и был остановлен"
        }
    }
}

nonisolated enum Shell {
    static let defaultTimeout: TimeInterval = 30

    /// Работа целиком уходит в `Task.detached`: при `NonisolatedNonsendingByDefault`
    /// одной пометки `nonisolated` мало — функция унаследовала бы изоляцию вызывающего
    /// и ждала бы процесс на главном потоке.
    nonisolated static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = defaultTimeout
    ) async throws -> ShellResult {
        try await Task.detached(priority: .userInitiated) {
            try runBlocking(executable, arguments, timeout: timeout)
        }.value
    }

    private nonisolated static func runBlocking(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(
                command: (executable as NSString).lastPathComponent,
                reason: error.localizedDescription
            )
        }

        // stdout и stderr вычитываются параллельно. Если читать их по очереди,
        // процесс, заполнивший второй пайп, заблокируется на записи и не завершится.
        let output = Locked(Data())
        let errorOutput = Locked(Data())
        let readers = DispatchGroup()

        DispatchQueue.global().async(group: readers) {
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            output.withLock { $0 = data }
        }
        DispatchQueue.global().async(group: readers) {
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            errorOutput.withLock { $0 = data }
        }

        let didTimeOut = Locked(false)
        let watchdog = DispatchWorkItem {
            guard process.isRunning else { return }
            didTimeOut.withLock { $0 = true }
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        readers.wait()
        process.waitUntilExit()
        watchdog.cancel()

        let command = (executable as NSString).lastPathComponent
        if didTimeOut.withLock({ $0 }) {
            throw ShellError.timedOut(command: command, seconds: Int(timeout))
        }

        return ShellResult(
            standardOutput: output.withLock { String(decoding: $0, as: UTF8.self) },
            standardError: errorOutput.withLock { String(decoding: $0, as: UTF8.self) },
            exitCode: process.terminationStatus
        )
    }

    /// Аргумент для `adb shell`: команда собирается на устройстве заново,
    /// поэтому `&` и пробелы в ссылке нужно закрыть кавычками.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Команда в виде, пригодном для вставки в терминал.
    static func displayCommand(_ executable: String, _ arguments: [String]) -> String {
        let special: Set<Character> = [" ", "&", "?", ";", "|", "<", ">", "(", ")", "$", "*"]
        return ([executable] + arguments)
            .map { argument in
                if argument.hasPrefix("'") || argument.contains(where: { special.contains($0) }) {
                    return "\"\(argument)\""
                }
                return argument
            }
            .joined(separator: " ")
    }
}

enum ExecutablePath {
    static let git = "/usr/bin/git"
    static let xcrun = "/usr/bin/xcrun"
}
