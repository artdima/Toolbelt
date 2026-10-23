//
//  LinkedInClient.swift
//  Toolbelt
//
//  The member's profile, token introspection, and creating and deleting the member's posts.
//

import Foundation

nonisolated enum LinkedInEndpoint: Sendable {
    case userInfo
    case introspection
    case createPost
    case deletePost
}

nonisolated enum LinkedInError: LocalizedError, Equatable {
    case tokenRejected
    case missingProfileScope
    case missingShareScope
    case notYourPost
    case forbidden(message: String?)
    case notFound
    case rejected(status: Int, message: String?)
    case outdatedVersion(String)
    case rateLimited(retryAfter: Int?)
    case server(status: Int, message: String?)
    case network(reason: String)
    case redirected(location: String)
    case invalidResponse
    case wrongClientSecret
    case wrongClientIDOrToken

    static let tokenGenerator = "https://www.linkedin.com/developers/tools/oauth/token-generator"

    var errorDescription: String? {
        switch self {
        case .tokenRejected:
            return "LinkedIn rejected the token (401): access tokens last 60 days, or it was revoked. "
                + "Generate a new one in the OAuth Token Generator (\(Self.tokenGenerator)) and paste it in Toolbelt → MCP."
        case .missingProfileScope:
            return "The token lacks the openid and profile scopes (403), so Toolbelt cannot tell who the author is. "
                + "Generate it again with openid profile email w_member_social."
        case .missingShareScope:
            return "The token lacks the w_member_social scope (403). "
                + "Add the Share on LinkedIn product to the app and generate the token again."
        case .notYourPost:
            return "LinkedIn refused to delete the post (403): it belongs to another member, or the token lacks w_member_social."
        case let .forbidden(message):
            return "LinkedIn refused the request (403)" + Self.detail(message)
        case .notFound:
            return "LinkedIn has no such post (404): it was deleted already, or never existed."
        case let .rejected(status, message):
            return "LinkedIn rejected the request (HTTP \(status))" + Self.detail(message)
        case let .outdatedVersion(version):
            return "LinkedIn no longer supports API version \(version), the one this Toolbelt uses. Update Toolbelt."
        case let .rateLimited(retryAfter):
            let wait = retryAfter.map { " Retry in \($0) s." } ?? ""
            return "LinkedIn's daily limit is used up (429): 150 requests per member, reset at midnight UTC.\(wait)"
        case let .server(status, message):
            return "LinkedIn answered HTTP \(status)" + Self.detail(message)
        case let .network(reason):
            return "Could not reach LinkedIn: \(reason)"
        case let .redirected(location):
            return "LinkedIn redirected the request to \(location); Toolbelt does not send the token to another address."
        case .invalidResponse:
            return "LinkedIn sent a response Toolbelt does not understand."
        case .wrongClientSecret:
            return "The Client Secret does not fit the Client ID (401). Copy it again from the app's Auth tab."
        case .wrongClientIDOrToken:
            return "LinkedIn did not accept the Client ID or the token (400). Both have to come from the same app."
        }
    }

    /// A request that never got an answer may still have reached LinkedIn.
    var leavesOutcomeUnknown: Bool {
        switch self {
        case .network: return true
        default: return false
        }
    }

    private static func detail(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return "." }
        return ": \(message)"
    }
}

nonisolated struct LinkedInClient: Sendable {
    /// Raised by hand every few months: LinkedIn turns a version off about a year after its release.
    static let apiVersion = "202608"
    static let requestTimeout: TimeInterval = 30

    private static let apiBase = "https://api.linkedin.com"
    private static let introspectionURL = "https://www.linkedin.com/oauth/v2/introspectToken"

    let token: String
    private let session: URLSession

    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: configuration)
    }()

    init(token: String, session: URLSession? = nil) {
        self.token = token
        self.session = session ?? Self.sharedSession
    }

    func userInfo() async throws -> LinkedInUserInfo {
        let request = try apiRequest("GET", path: "/v2/userinfo", isVersioned: false)
        let (data, _) = try await send(request, endpoint: .userInfo)
        return try Self.decode(data)
    }

    /// Works only with the Client ID and Client Secret of the app the token was issued for.
    func introspect(clientID: String, clientSecret: String) async throws -> LinkedInIntrospection {
        guard let url = URL(string: Self.introspectionURL) else { throw LinkedInError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Toolbelt-MCP", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(Self.formBody([
            ("client_id", clientID),
            ("client_secret", clientSecret),
            ("token", token)
        ]).utf8)
        let (data, _) = try await send(request, endpoint: .introspection)
        return try Self.decode(data)
    }

    /// The URN of the new post comes in x-restli-id, the body is empty. nil means the post
    /// exists, but LinkedIn did not say which it is.
    func createPost(_ body: LinkedInPostBody) async throws -> String? {
        var request = try apiRequest("POST", path: "/rest/posts", isVersioned: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await send(request, endpoint: .createPost)
        guard let header = response.value(forHTTPHeaderField: "x-restli-id"),
              let urn = header.removingPercentEncoding?.trimmingCharacters(in: .whitespaces),
              !urn.isEmpty
        else { return nil }
        return urn
    }

    /// LinkedIn answers 204 to a post that is already gone, too.
    func deletePost(_ urn: String) async throws {
        let request = try apiRequest("DELETE", path: "/rest/posts/" + Self.encodeSegment(urn), isVersioned: true)
        _ = try await send(request, endpoint: .deletePost)
    }

    // MARK: Transport

    private func apiRequest(_ method: String, path: String, isVersioned: Bool) throws -> URLRequest {
        guard let url = URL(string: Self.apiBase + path) else { throw LinkedInError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Toolbelt-MCP", forHTTPHeaderField: "User-Agent")
        if isVersioned {
            request.setValue(Self.apiVersion, forHTTPHeaderField: "LinkedIn-Version")
            request.setValue("2.0.0", forHTTPHeaderField: "X-Restli-Protocol-Version")
        }
        return request
    }

    private func send(_ request: URLRequest, endpoint: LinkedInEndpoint) async throws -> (Data, HTTPURLResponse) {
        let host = request.url.flatMap(SameHostRedirects.host(of:)) ?? ""
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: SameHostRedirects(host: host))
        } catch let error as URLError {
            throw LinkedInError.network(reason: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw LinkedInError.invalidResponse }
        if (300..<400).contains(http.statusCode) {
            throw LinkedInError.redirected(location: http.value(forHTTPHeaderField: "Location") ?? "another address")
        }
        if let error = Self.error(
            status: http.statusCode,
            endpoint: endpoint,
            body: data,
            retryAfter: http.value(forHTTPHeaderField: "Retry-After")
        ) {
            throw error
        }
        return (data, http)
    }

    /// nil for a success. The endpoint tells apart what a bare 403 means.
    static func error(status: Int, endpoint: LinkedInEndpoint, body: Data, retryAfter: String?) -> LinkedInError? {
        guard !(200..<300).contains(status) else { return nil }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let parsed = try? decoder.decode(LinkedInErrorBody.self, from: body)
        let message = (parsed?.message ?? parsed?.errorDescription ?? parsed?.error).map { MCPText.truncated($0, to: 300) }

        if status == 426 || parsed?.code == "NONEXISTENT_VERSION" || parsed?.code == "VERSION_MISSING" {
            return .outdatedVersion(apiVersion)
        }
        switch (status, endpoint) {
        case (401, .introspection):
            return .wrongClientSecret
        case (400, .introspection):
            return .wrongClientIDOrToken
        case (401, _):
            return .tokenRejected
        case (403, .userInfo):
            return .missingProfileScope
        case (403, .createPost):
            return .missingShareScope
        case (403, .deletePost):
            return .notYourPost
        case (403, _):
            return .forbidden(message: message)
        case (404, .deletePost):
            return .notFound
        case (429, _):
            let seconds = retryAfter.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return .rateLimited(retryAfter: seconds)
        case (400, _), (422, _):
            return .rejected(status: status, message: message)
        default:
            return .server(status: status, message: message)
        }
    }

    static func encodeSegment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func formBody(_ fields: [(String, String)]) -> String {
        fields.map { "\(encodeSegment($0.0))=\(encodeSegment($0.1))" }.joined(separator: "&")
    }

    private static func decode<Value: Decodable>(_ data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            throw LinkedInError.invalidResponse
        }
    }
}
