//
//  HTTPRequestViewModel.swift
//  Toolbelt
//

import Observation
import SwiftUI

@Observable
@MainActor
final class HTTPRequestViewModel {
    enum RequestTab: String, CaseIterable, Identifiable {
        case headers, body
        var id: String { rawValue }
    }

    enum ResponseTab: String, CaseIterable, Identifiable {
        case body = "Body"
        case headers = "Headers"
        var id: String { rawValue }
    }

    /// Past this many characters the body is cut: SwiftUI text views choke on more.
    static let bodyDisplayLimit = 512 * 1024

    private let client: HTTPRequestSending
    let history: HTTPRequestHistoryStore

    var curlText = ""
    var draft = HTTPRequestDraft()
    var requestTab: RequestTab = .headers
    var responseTab: ResponseTab = .body
    var isPrettyPrinted = true

    private(set) var parseError: String?
    private(set) var warnings: [String] = []
    private(set) var response: HTTPResponseSummary?
    private(set) var bodyText: String?
    private(set) var prettyBodyText: String?
    private(set) var isBodyTruncated = false
    private(set) var sendError: String?
    private(set) var isSending = false

    convenience init() {
        self.init(client: URLSessionHTTPClient(), history: .shared)
    }

    init(client: HTTPRequestSending, history: HTTPRequestHistoryStore) {
        self.client = client
        self.history = history
    }

    var canSend: Bool {
        !draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var curlCommand: String {
        CurlBuilder.command(for: draft)
    }

    var canPrettyPrint: Bool {
        prettyBodyText != nil
    }

    /// nil means a binary body.
    var displayedBody: String? {
        isPrettyPrinted ? (prettyBodyText ?? bodyText) : bodyText
    }

    var headersTabTitle: String {
        let count = draft.enabledHeaders.count
        return count > 0 ? "Headers (\(count))" : "Headers"
    }

    var bodyTabTitle: String {
        draft.body.isEmpty ? "Body" : "Body •"
    }

    /// A command that does not parse yet leaves the form alone: it is still being typed.
    func parseCurl() {
        let text = curlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            parseError = nil
            warnings = []
            return
        }
        do {
            let parsed = try CurlParser.parse(text)
            draft = parsed.draft
            warnings = parsed.warnings
            parseError = nil
        } catch {
            parseError = error.localizedDescription
        }
    }

    func clearCurl() {
        curlText = ""
        parseError = nil
        warnings = []
    }

    func send() async {
        guard canSend else { return }
        let request = draft

        isSending = true
        sendError = nil
        defer { isSending = false }

        do {
            let received = try await client.send(request)
            present(received)
            history.record(request)
        } catch {
            response = nil
            bodyText = nil
            prettyBodyText = nil
            sendError = error.localizedDescription
        }
    }

    func load(_ entry: HTTPRequestEntry) {
        clearCurl()
        draft = entry.draft
    }

    func addHeader() {
        draft.headers.append(HTTPHeader(name: "", value: ""))
        requestTab = .headers
    }

    func removeHeader(id: HTTPHeader.ID) {
        draft.headers.removeAll { $0.id == id }
    }

    private func present(_ received: HTTPResponseSummary) {
        response = received
        guard let text = received.bodyText else {
            bodyText = nil
            prettyBodyText = nil
            isBodyTruncated = false
            return
        }
        isBodyTruncated = text.count > Self.bodyDisplayLimit
        if isBodyTruncated {
            bodyText = String(text.prefix(Self.bodyDisplayLimit))
            prettyBodyText = nil
        } else {
            bodyText = text
            prettyBodyText = JSONPretty.format(text)
        }
    }
}
