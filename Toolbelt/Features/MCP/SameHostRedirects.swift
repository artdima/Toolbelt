//
//  SameHostRedirects.swift
//  Toolbelt
//
//  Redirects that would carry a token to another address are not followed.
//

import Foundation

/// URLSession would carry the token header along to wherever a redirect points. A refused
/// redirect comes back as the 3xx response itself, and the client reports it as an error.
nonisolated final class SameHostRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let host: String

    /// `host` as `host(of:)` gives it: lowercased, with the port when there is one.
    init(host: String) {
        self.host = host
    }

    static func host(of url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let target = request.url.flatMap(Self.host(of:))
        let isSafe = target == host && request.url?.scheme?.lowercased() == task.originalRequest?.url?.scheme?.lowercased()
        completionHandler(isSafe ? request : nil)
    }
}
