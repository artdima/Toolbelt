//
//  SocketTransport.swift
//  Toolbelt
//
//  An MCP transport over one accepted socket: newline-delimited JSON-RPC, as on stdio.
//

import Dispatch
import Foundation
import Logging
import MCP

nonisolated enum SocketTransportError: LocalizedError {
    case notConnected
    case readFailed(Int32)
    case writeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "The MCP connection is closed"
        case let .readFailed(code):
            return "Reading from the MCP socket failed: \(String(cString: strerror(code)))"
        case let .writeFailed(code):
            return "Writing to the MCP socket failed: \(String(cString: strerror(code)))"
        }
    }
}

actor SocketTransport: Transport {
    nonisolated let logger: Logging.Logger

    private let channel: DispatchIO
    private let queue: DispatchQueue
    private let messages: AsyncThrowingStream<Data, Swift.Error>
    private let continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private var isConnected = false
    private var isClosed = false

    /// Takes ownership of `fileDescriptor`: the channel closes it once it is torn down.
    init(fileDescriptor: Int32) {
        logger = Logging.Logger(label: "app.artdima.Toolbelt.mcp.socket") { _ in SwiftLogNoOpLogHandler() }
        let queue = DispatchQueue(label: "app.artdima.Toolbelt.mcp.connection")
        self.queue = queue
        channel = DispatchIO(type: .stream, fileDescriptor: fileDescriptor, queue: queue) { _ in
            close(fileDescriptor)
        }
        channel.setLimit(lowWater: 1)
        (messages, continuation) = AsyncThrowingStream.makeStream(of: Data.self, throwing: Swift.Error.self)
    }

    deinit {
        channel.close(flags: .stop)
        continuation.finish()
    }

    func connect() async throws {
        guard !isConnected, !isClosed else { return }
        isConnected = true

        let continuation = continuation
        let framer = Locked(LineFramer())
        channel.read(offset: 0, length: Int.max, queue: queue) { done, data, error in
            if let data, !data.isEmpty {
                let lines = framer.withLock { framer in Result { try framer.append(Data(data)) } }
                switch lines {
                case let .success(lines):
                    for line in lines { continuation.yield(line) }
                case let .failure(error):
                    continuation.finish(throwing: error)
                    return
                }
            }
            guard done else { return }
            if error == 0 || error == ECANCELED {
                continuation.finish()
            } else {
                continuation.finish(throwing: SocketTransportError.readFailed(error))
            }
        }
    }

    func disconnect() async {
        guard !isClosed else { return }
        isClosed = true
        isConnected = false
        channel.close(flags: .stop)
        continuation.finish()
    }

    func send(_ data: Data) async throws {
        guard isConnected else { throw SocketTransportError.notConnected }

        var message = data
        message.append(0x0A)
        let payload = message.withUnsafeBytes { DispatchData(bytes: $0) }
        let channel = channel
        let queue = queue

        try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, Swift.Error>) in
            channel.write(offset: 0, data: payload, queue: queue) { done, _, error in
                guard done else { return }
                if error == 0 {
                    resume.resume()
                } else {
                    resume.resume(throwing: SocketTransportError.writeFailed(error))
                }
            }
        }
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        messages
    }
}
