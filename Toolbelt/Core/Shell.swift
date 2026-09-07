//
//  Shell.swift
//  Toolbelt
//
//  Running external commands: git, xcrun, adb.
//

import Foundation

nonisolated struct ShellResult: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32

    var isSuccess: Bool { exitCode == 0 }

    /// Output to show the user: stdout and stderr back to back, blank lines dropped.
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
            return "Could not launch \(command): \(reason)"
        case let .timedOut(command, seconds):
            return "\(command) did not respond within \(seconds)s and was terminated"
        }
    }
}

nonisolated enum Shell {
    static let defaultTimeout: TimeInterval = 30

    /// The work goes into `Task.detached` on purpose: with `NonisolatedNonsendingByDefault`
    /// a `nonisolated` marker alone is not enough — the function would inherit the
    /// caller's isolation and wait for the process on the main thread.
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

        // stdout and stderr are drained in parallel. Read them one after the other and
        // a child that fills the second pipe blocks on write and never exits.
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

    /// An argument for `adb shell`: the command is reassembled on the device,
    /// so ampersands and spaces in a link have to stay inside quotes.
    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The command in a form that can be pasted into a terminal as is.
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
