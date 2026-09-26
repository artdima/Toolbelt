//
//  HTTPRequestModels.swift
//  Toolbelt
//

import Foundation

enum HTTPMethod {
    /// The methods offered in the picker; a parsed command may carry any other one.
    static let common = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
}

struct HTTPHeader: Identifiable, Codable {
    var id = UUID()
    var name: String
    var value: String
    var isEnabled = true
}

extension HTTPHeader: Equatable {
    /// Identity exists for SwiftUI rows only: two headers with the same text are the same header.
    static func == (lhs: HTTPHeader, rhs: HTTPHeader) -> Bool {
        lhs.name == rhs.name && lhs.value == rhs.value && lhs.isEnabled == rhs.isEnabled
    }
}

struct HTTPRequestDraft: Codable, Equatable {
    var method = "GET"
    var url = ""
    var headers: [HTTPHeader] = []
    var body = ""

    var enabledHeaders: [HTTPHeader] {
        headers.filter { $0.isEnabled && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func hasHeader(named name: String) -> Bool {
        enabledHeaders.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The URL without its scheme, for compact lists.
    var displayURL: String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "://") else { return trimmed }
        return String(trimmed[range.upperBound...])
    }
}

struct HTTPRequestEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var draft: HTTPRequestDraft
    var isPinned = false
}

struct HTTPResponseSummary: Equatable {
    enum StatusClass {
        case success, redirect, clientError, serverError, other
    }

    let statusCode: Int
    let headers: [HTTPHeader]
    let body: Data
    let duration: TimeInterval

    var statusClass: StatusClass {
        switch statusCode {
        case 200..<300: return .success
        case 300..<400: return .redirect
        case 400..<500: return .clientError
        case 500..<600: return .serverError
        default: return .other
        }
    }

    var statusText: String {
        Self.statusTexts[statusCode]
            ?? HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalizedFirst
    }

    var contentType: String? {
        headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
    }

    /// The body decoded as UTF-8; nil when it is binary.
    var bodyText: String? {
        guard !body.isEmpty else { return "" }
        if let type = contentType?.lowercased(),
           Self.binaryTypePrefixes.contains(where: { type.hasPrefix($0) }) {
            return nil
        }
        return String(data: body, encoding: .utf8)
    }

    private static let binaryTypePrefixes = [
        "image/", "audio/", "video/", "font/",
        "application/octet-stream", "application/pdf", "application/zip", "application/gzip"
    ]

    /// Foundation's texts read like error messages ("no error" for 200); these are the usual ones.
    private static let statusTexts: [Int: String] = [
        200: "OK", 201: "Created", 202: "Accepted", 204: "No Content",
        301: "Moved Permanently", 302: "Found", 304: "Not Modified", 307: "Temporary Redirect", 308: "Permanent Redirect",
        400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
        408: "Request Timeout", 409: "Conflict", 410: "Gone", 415: "Unsupported Media Type",
        422: "Unprocessable Entity", 429: "Too Many Requests",
        500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway",
        503: "Service Unavailable", 504: "Gateway Timeout"
    ]
}
