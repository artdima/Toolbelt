//
//  GitLabClient.swift
//  Toolbelt
//
//  Read-only calls to GitLab REST v4 with a personal access token.
//

import Foundation

nonisolated enum GitLabError: LocalizedError, Equatable {
    case unauthorized(host: String)
    case forbidden(host: String)
    case notFound(host: String)
    case rateLimited(host: String, retryAfter: Int?)
    case server(host: String, status: Int, message: String?)
    case network(host: String, reason: String)
    case redirected(host: String, location: String)
    case invalidResponse(host: String)

    var errorDescription: String? {
        switch self {
        case let .unauthorized(host):
            return "GitLab at \(host) rejected the token (401): it is invalid, revoked or expired. Replace it in Toolbelt → MCP."
        case let .forbidden(host):
            return "The token for \(host) lacks the permission for this request (403). It needs the read_api scope and access to the project."
        case let .notFound(host):
            return "Not found on \(host) (404), or the token has no access to it: GitLab answers the same in both cases."
        case let .rateLimited(host, retryAfter):
            let wait = retryAfter.map { "Wait \($0) s" } ?? "Wait a minute"
            return "GitLab at \(host) is rate limiting requests (429). \(wait) and try again."
        case let .server(host, status, message):
            let detail = message.map { ": \($0)" } ?? ""
            return "GitLab at \(host) answered HTTP \(status)\(detail)"
        case let .network(host, reason):
            return "Could not reach \(host): \(reason)"
        case let .redirected(host, location):
            return "\(host) redirected the request to \(location); Toolbelt does not send the token to another address."
        case let .invalidResponse(host):
            return "\(host) sent a response that is not what GitLab sends"
        }
    }
}

nonisolated struct GitLabPage<Element: Decodable & Sendable>: Sendable {
    let items: [Element]
    let nextPage: Int?
}

nonisolated struct GitLabClient: Sendable {
    let baseURL: URL
    let token: String
    private let session: URLSession

    static let requestTimeout: TimeInterval = 30
    static let traceTimeout: TimeInterval = 120

    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: configuration)
    }()

    init(baseURL: URL, token: String, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.token = token
        self.session = session ?? Self.sharedSession
    }

    var host: String {
        GitLabLinkParser.host(of: baseURL) ?? baseURL.absoluteString
    }

    /// A path or a numeric id; the path goes in as one segment, slashes encoded.
    static func projectSegment(_ project: String) -> String {
        var trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("/") { trimmed.removeFirst() }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return encodeSegment(trimmed)
    }

    static func encodeSegment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func get<Value: Decodable & Sendable>(
        _ path: String,
        query: [String: String?] = [:],
        as type: Value.Type = Value.self
    ) async throws -> Value {
        let (data, _) = try await send(path, query: query, timeout: Self.requestTimeout)
        return try decode(data)
    }

    func page<Element: Decodable & Sendable>(
        _ path: String,
        query: [String: String?] = [:],
        page: Int,
        perPage: Int,
        of type: Element.Type = Element.self
    ) async throws -> GitLabPage<Element> {
        var query = query
        query["page"] = String(page)
        query["per_page"] = String(perPage)
        let (data, response) = try await send(path, query: query, timeout: Self.requestTimeout)
        let next = response.value(forHTTPHeaderField: "x-next-page").flatMap { Int($0) }
        return GitLabPage(items: try decode(data), nextPage: next)
    }

    func all<Element: Decodable & Sendable>(
        _ path: String,
        query: [String: String?] = [:],
        maxPages: Int = 20,
        of type: Element.Type = Element.self
    ) async throws -> (items: [Element], isComplete: Bool) {
        var items: [Element] = []
        var pageNumber = 1
        for _ in 0..<maxPages {
            let result: GitLabPage<Element> = try await page(path, query: query, page: pageNumber, perPage: 100)
            items += result.items
            guard let next = result.nextPage, next > pageNumber else { return (items, true) }
            pageNumber = next
        }
        return (items, false)
    }

    func text(_ path: String) async throws -> String {
        let (data, _) = try await send(path, query: [:], timeout: Self.traceTimeout)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Transport

    private func send(
        _ path: String,
        query: [String: String?],
        timeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        let request = try makeRequest(path, query: query, timeout: timeout)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: SameHostRedirects(host: host))
        } catch let error as URLError {
            throw GitLabError.network(host: host, reason: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw GitLabError.invalidResponse(host: host) }
        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 300..<400:
            let location = http.value(forHTTPHeaderField: "Location") ?? "another address"
            throw GitLabError.redirected(host: host, location: location)
        case 401:
            throw GitLabError.unauthorized(host: host)
        case 403:
            throw GitLabError.forbidden(host: host)
        case 404:
            throw GitLabError.notFound(host: host)
        case 429:
            throw GitLabError.rateLimited(host: host, retryAfter: Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After")))
        default:
            let body = try? JSONDecoder().decode(GitLabErrorBody.self, from: data)
            let message = (body?.message ?? body?.error).map { MCPText.truncated($0, to: 300) }
            throw GitLabError.server(host: host, status: http.statusCode, message: message)
        }
    }

    private func makeRequest(_ path: String, query: [String: String?], timeout: TimeInterval) throws -> URLRequest {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + "/api/v4/" + path) else {
            throw GitLabError.invalidResponse(host: host)
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=;")
        let items = query
            .compactMap { key, value in value.map { (key, $0) } }
            .sorted { $0.0 < $1.0 }
            .map { URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: allowed)) }
        components.percentEncodedQueryItems = items.isEmpty ? nil : items

        guard let url = components.url else { throw GitLabError.invalidResponse(host: host) }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Toolbelt-MCP", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func decode<Value: Decodable>(_ data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw GitLabError.invalidResponse(host: host)
        }
    }

    static func retryAfter(_ value: String?, now: Date = Date()) -> Int? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if let seconds = Int(value) { return max(0, seconds) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, Int(date.timeIntervalSince(now).rounded(.up)))
    }
}

/// URLSession would carry PRIVATE-TOKEN along to wherever a redirect points.
nonisolated private final class SameHostRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let target = request.url.flatMap(GitLabLinkParser.host(of:))
        let isSafe = target == host && request.url?.scheme?.lowercased() == task.originalRequest?.url?.scheme?.lowercased()
        completionHandler(isSafe ? request : nil)
    }
}
