//
//  Shell.swift
//  Toolbelt
//
//  Запуск внешних команд: git, xcrun, adb.
//

import SwiftUI

enum Shell {
    /// Task.detached обязателен: при NonisolatedNonsendingByDefault одна лишь
    /// пометка nonisolated наследует изоляцию вызывающего, и ожидание процесса
    /// осталось бы на главном потоке.
    nonisolated static func run(
        _ executable: String,
        _ arguments: [String]
    ) async -> (out: String, err: String, code: Int32) {
        await Task.detached {
            runSynchronously(executable, arguments)
        }.value
    }

    private nonisolated static func runSynchronously(
        _ executable: String,
        _ arguments: [String]
    ) -> (out: String, err: String, code: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ("", error.localizedDescription, -1)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    /// Аргумент для `adb shell`: команда собирается на устройстве заново,
    /// поэтому `&` и пробелы в ссылке нужно закрыть кавычками.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func display(_ executable: String, _ arguments: [String]) -> String {
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
