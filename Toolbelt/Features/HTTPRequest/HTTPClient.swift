//
//  HTTPClient.swift
//  Toolbelt
//
//  Sending a request and summarizing what came back.
//

import Foundation
import OSLog

protocol HTTPRequestSending {
    func send(_ draft: HTTPRequestDraft) async throws -> HTTPResponseSummary
}

nonisolated enum HTTPRequestError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedScheme(String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL is malformed"
        case let .unsupportedScheme(scheme):
            return "\(scheme):// is not supported, only http and https are"
        case .unexpectedResponse:
            return "The response is not HTTP"
        }
    }
}

/// Building the URLRequest is kept apart from sending it, so it is tested without a network.
enum HTTPRequestBuilder {
    static let timeout: TimeInterval = 60

    static func request(for draft: HTTPRequestDraft) throws -> URLRequest {
        let address = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), url.host() != nil else {
            throw HTTPRequestError.invalidURL
        }
        guard scheme == "http" || scheme == "https" else {
            throw HTTPRequestError.unsupportedScheme(scheme)
        }

        let method = draft.method.trimmingCharacters(in: .whitespaces).uppercased()

        var request = URLRequest(url: url)
        request.httpMethod = method.isEmpty ? "GET" : method
        request.timeoutInterval = timeout
        for header in draft.enabledHeaders {
            request.addValue(header.value, forHTTPHeaderField: header.name.trimmingCharacters(in: .whitespaces))
        }
        if !draft.body.isEmpty {
            request.httpBody = Data(draft.body.utf8)
        }
        return request
    }
}

@MainActor
final class URLSessionHTTPClient: HTTPRequestSending {
    private let session: URLSession

    convenience init() {
        self.init(session: Self.makeSession())
    }

    init(session: URLSession) {
        self.session = session
    }

    /// Ephemeral on purpose: no cookie jar and no cache, so every response is the server's.
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = HTTPRequestBuilder.timeout
        return URLSession(configuration: configuration)
    }

    func send(_ draft: HTTPRequestDraft) async throws -> HTTPResponseSummary {
        let request = try HTTPRequestBuilder.request(for: draft)
        let started = Date()
        let (data, response) = try await session.data(for: request)
        let duration = Date().timeIntervalSince(started)

        guard let http = response as? HTTPURLResponse else {
            throw HTTPRequestError.unexpectedResponse
        }
        let headers = http.allHeaderFields
            .map { HTTPHeader(name: String(describing: $0.key), value: String(describing: $0.value)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        Log.http.info(
            "\(request.httpMethod ?? "GET", privacy: .public) → \(http.statusCode, privacy: .public) in \(Int(duration * 1000), privacy: .public) ms"
        )
        return HTTPResponseSummary(statusCode: http.statusCode, headers: headers, body: data, duration: duration)
    }
}
