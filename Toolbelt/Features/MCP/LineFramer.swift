//
//  LineFramer.swift
//  Toolbelt
//
//  Splits a byte stream into newline-delimited messages, the way MCP's stdio transport does.
//

import Foundation

nonisolated enum LineFramerError: LocalizedError, Equatable {
    case lineTooLong(Int)

    var errorDescription: String? {
        switch self {
        case let .lineTooLong(limit):
            return "A message longer than \(limit) bytes arrived without a newline"
        }
    }
}

nonisolated struct LineFramer: Sendable {
    static let defaultLimit = 32 * 1024 * 1024

    private let limit: Int
    private var buffer = Data()
    /// Bytes already searched for a newline, so a long message arriving in pieces is not
    /// rescanned from the start each time.
    private var scanned = 0

    init(limit: Int = defaultLimit) {
        self.limit = limit
    }

    var pendingByteCount: Int { buffer.count }

    mutating func append(_ chunk: Data) throws -> [Data] {
        buffer.append(chunk)

        var lines: [Data] = []
        var lineStart = buffer.startIndex
        var searchFrom = buffer.startIndex + scanned

        while let newline = buffer[searchFrom...].firstIndex(of: 0x0A) {
            var line = buffer[lineStart..<newline]
            if line.last == 0x0D { line = line.dropLast() }
            if !line.isEmpty { lines.append(Data(line)) }
            lineStart = newline + 1
            searchFrom = lineStart
        }

        if lineStart > buffer.startIndex {
            buffer = Data(buffer[lineStart...])
        }
        scanned = buffer.count

        guard buffer.count <= limit else {
            buffer = Data()
            scanned = 0
            throw LineFramerError.lineTooLong(limit)
        }
        return lines
    }
}
