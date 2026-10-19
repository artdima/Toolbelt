//
//  MCPSocket.swift
//  Toolbelt
//
//  The unix socket toolbelt-mcp connects to. Only processes of the same user get through.
//

import Foundation

nonisolated enum MCPSocketError: LocalizedError, Equatable {
    case pathTooLong(String)
    case alreadyServed(String)
    case system(String, Int32)

    var errorDescription: String? {
        switch self {
        case let .pathTooLong(path):
            return "The socket path is too long for a unix socket: \(path)"
        case .alreadyServed:
            return "Another copy of Toolbelt is already serving MCP"
        case let .system(call, code):
            return "\(call) failed: \(String(cString: strerror(code)))"
        }
    }
}

nonisolated enum MCPSocket {
    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "Toolbelt/mcp.sock")
    }

    static func dial(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let connected = (try? withAddress(path) { address, length in
            connect(fd, address, length) == 0
        }) ?? false
        guard connected else {
            close(fd)
            return nil
        }
        return fd
    }

    static func peerUID(of fd: Int32) -> uid_t? {
        var uid = uid_t(0)
        var gid = gid_t(0)
        guard getpeereid(fd, &uid, &gid) == 0 else { return nil }
        return uid
    }

    /// A write to a peer that has gone away must fail with EPIPE, not kill the app with SIGPIPE.
    static func configureConnection(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }
    }

    static func withAddress<Result>(
        _ path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result
    ) throws -> Result {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw MCPSocketError.pathTooLong(path)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }

        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}

nonisolated final class MCPSocketListener: @unchecked Sendable {
    let path: String

    private let queue = DispatchQueue(label: "app.artdima.Toolbelt.mcp.listener")
    private let onAccept: @Sendable (Int32) -> Void
    private let source = Locked<DispatchSourceRead?>(nil)

    init(path: String, onAccept: @escaping @Sendable (Int32) -> Void) {
        self.path = path
        self.onAccept = onAccept
    }

    deinit {
        stop()
    }

    func start() throws {
        guard source.withLock({ $0 == nil }) else { return }

        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = chmod(directory, 0o700)

        if FileManager.default.fileExists(atPath: path) {
            if let fd = MCPSocket.dial(path) {
                close(fd)
                throw MCPSocketError.alreadyServed(path)
            }
            unlink(path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MCPSocketError.system("socket", errno) }

        let inode: ino_t
        do {
            _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
            try MCPSocket.withAddress(path) { address, length in
                guard bind(fd, address, length) == 0 else { throw MCPSocketError.system("bind", errno) }
            }
            // The directory is already 0700; this closes the socket itself as well.
            guard chmod(path, 0o600) == 0 else { throw MCPSocketError.system("chmod", errno) }
            guard listen(fd, 16) == 0 else { throw MCPSocketError.system("listen", errno) }
            let flags = fcntl(fd, F_GETFL)
            guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw MCPSocketError.system("fcntl", errno)
            }
            var info = stat()
            guard stat(path, &info) == 0 else { throw MCPSocketError.system("stat", errno) }
            inode = info.st_ino
        } catch {
            close(fd)
            unlink(path)
            throw error
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let path = path
        let onAccept = onAccept
        readSource.setEventHandler {
            Self.acceptPending(on: fd, onAccept: onAccept)
        }
        readSource.setCancelHandler {
            close(fd)
            Self.removeSocket(at: path, ifInode: inode)
        }
        source.withLock { $0 = readSource }
        readSource.resume()
    }

    func stop() {
        source.withLock { current in
            current?.cancel()
            current = nil
        }
    }

    private static func acceptPending(on listener: Int32, onAccept: @Sendable (Int32) -> Void) {
        while true {
            let fd = accept(listener, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                return
            }
            MCPSocket.configureConnection(fd)
            guard MCPSocket.peerUID(of: fd) == getuid() else {
                close(fd)
                continue
            }
            onAccept(fd)
        }
    }

    /// A second Toolbelt may have replaced the file meanwhile; its socket is not ours to remove.
    private static func removeSocket(at path: String, ifInode inode: ino_t) {
        var info = stat()
        guard stat(path, &info) == 0, info.st_ino == inode else { return }
        unlink(path)
    }
}
