//
//  main.swift
//  toolbelt-mcp
//
//  Claude starts this as a stdio MCP server. It has no logic and no Keychain access of its own:
//  it relays stdin to the socket of the running Toolbelt and the socket to stdout, and
//  starts Toolbelt in the background when it is not running.
//

import AppKit
import Foundation

@MainActor
enum Relay {
    static let fallbackBundleID = "app.artdima.Toolbelt"
    static let startupTimeout: TimeInterval = 10

    static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)

        let path = socketPath()
        let socket = connect(to: path)
        let input = InputState()

        Thread.detachNewThread {
            if !pump(from: STDIN_FILENO, to: socket) {
                report("could not forward a request to Toolbelt: \(String(cString: strerror(errno)))")
            }
            input.markClosed()
            // Lets Toolbelt end the session; its answers still arrive on the read side.
            shutdown(socket, SHUT_WR)
        }

        let readCleanly = pump(from: socket, to: STDOUT_FILENO)
        if input.isClosed { exit(0) }
        fail(readCleanly
            ? "Toolbelt closed the connection: it quit or MCP was turned off in it."
            : "the connection to Toolbelt broke: \(String(cString: strerror(errno)))")
    }

    // MARK: Connecting

    private static func connect(to path: String) -> Int32 {
        if let fd = dial(path) { return fd }

        let app = containingApp()
        let bundleID = app.flatMap { Bundle(url: $0)?.bundleIdentifier } ?? fallbackBundleID
        launch(app: app, bundleID: bundleID)

        let deadline = Date().addingTimeInterval(startupTimeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            if let fd = dial(path) { return fd }
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            fail("Toolbelt is running, but its MCP server is off. Turn on “MCP enabled” in the Toolbelt menu.")
        }
        fail("Toolbelt did not open \(path) within \(Int(startupTimeout)) s.")
    }

    /// The copy of Toolbelt this helper ships in, so a build from Xcode does not start the one in /Applications.
    private static func launch(app: URL?, bundleID: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if let app {
            process.arguments = ["-g", app.path(percentEncoded: false)]
        } else {
            process.arguments = ["-g", "-b", bundleID]
        }
        // stdout belongs to the MCP protocol: nothing else may be written there.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fail("could not launch Toolbelt: \(error.localizedDescription)")
        }
        if process.terminationStatus != 0 {
            fail("could not launch Toolbelt: open exited with \(process.terminationStatus)")
        }
    }

    private static func containingApp() -> URL? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        let macOS = executable.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents", app.pathExtension == "app" else {
            return nil
        }
        return app
    }

    private static func socketPath() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "Toolbelt/mcp.sock").path(percentEncoded: false)
    }

    private static func dial(_ path: String) -> Int32? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            fail("the socket path is too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard connected else {
            close(fd)
            return nil
        }
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    // MARK: Relaying

    /// true at end of input, false on an error.
    nonisolated private static func pump(from source: Int32, to destination: Int32) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(source, $0.baseAddress, $0.count) }
            if count == 0 { return true }
            if count < 0 {
                if errno == EINTR { continue }
                return false
            }
            let written = buffer.withUnsafeBytes { writeAll(destination, UnsafeRawBufferPointer(rebasing: $0[..<count])) }
            if !written { return false }
        }
    }

    nonisolated private static func writeAll(_ fd: Int32, _ bytes: UnsafeRawBufferPointer) -> Bool {
        guard let base = bytes.baseAddress else { return true }
        var offset = 0
        while offset < bytes.count {
            let written = write(fd, base + offset, bytes.count - offset)
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }

    nonisolated private static func report(_ message: String) {
        FileHandle.standardError.write(Data("toolbelt-mcp: \(message)\n".utf8))
    }

    nonisolated private static func fail(_ message: String) -> Never {
        report(message)
        exit(1)
    }
}

private final class InputState: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false

    var isClosed: Bool {
        lock.withLock { closed }
    }

    func markClosed() {
        lock.withLock { closed = true }
    }
}

Relay.run()
