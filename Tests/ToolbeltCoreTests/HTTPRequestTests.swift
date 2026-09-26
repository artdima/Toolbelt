import Foundation
import Testing
@testable import ToolbeltCore

@Suite("URLRequest building")
struct HTTPRequestBuilderTests {
    @Test("Method, enabled headers and body reach the request")
    func fullRequest() throws {
        let draft = HTTPRequestDraft(
            method: "post",
            url: " https://x.dev/items?x=1 ",
            headers: [
                HTTPHeader(name: "X-On", value: "1"),
                HTTPHeader(name: "X-Off", value: "2", isEnabled: false),
                HTTPHeader(name: "", value: "nameless")
            ],
            body: "a=1"
        )

        let request = try HTTPRequestBuilder.request(for: draft)

        #expect(request.url?.absoluteString == "https://x.dev/items?x=1")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-On") == "1")
        #expect(request.value(forHTTPHeaderField: "X-Off") == nil)
        #expect(request.httpBody == Data("a=1".utf8))
        #expect(request.timeoutInterval == HTTPRequestBuilder.timeout)
    }

    @Test("An empty method is a GET without a body")
    func emptyMethod() throws {
        let request = try HTTPRequestBuilder.request(for: HTTPRequestDraft(method: "", url: "https://x.dev"))
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
    }

    @Test("Malformed URLs and other schemes are rejected")
    func rejectedURLs() {
        #expect(throws: HTTPRequestError.invalidURL) {
            try HTTPRequestBuilder.request(for: HTTPRequestDraft(url: "not a url"))
        }
        #expect(throws: HTTPRequestError.invalidURL) {
            try HTTPRequestBuilder.request(for: HTTPRequestDraft(url: "x.dev/path"))
        }
        #expect(throws: HTTPRequestError.unsupportedScheme("ftp")) {
            try HTTPRequestBuilder.request(for: HTTPRequestDraft(url: "ftp://x.dev/file"))
        }
    }
}

@Suite("Response summary")
struct HTTPResponseSummaryTests {
    private func response(_ status: Int, type: String? = nil, body: Data = Data()) -> HTTPResponseSummary {
        HTTPResponseSummary(
            statusCode: status,
            headers: type.map { [HTTPHeader(name: "content-type", value: $0)] } ?? [],
            body: body,
            duration: 0.1837
        )
    }

    @Test("Status classes and texts")
    func status() {
        #expect(response(204).statusClass == .success)
        #expect(response(302).statusClass == .redirect)
        #expect(response(404).statusClass == .clientError)
        #expect(response(503).statusClass == .serverError)
        #expect(response(404).statusText == "Not Found")
        #expect(response(418).statusText.isEmpty == false)
    }

    @Test("Text bodies decode, binary ones do not")
    func bodies() {
        #expect(response(200, type: "application/json; charset=utf-8", body: Data("{}".utf8)).bodyText == "{}")
        #expect(response(200, type: "image/png", body: Data([0x89, 0x50])).bodyText == nil)
        #expect(response(200, type: "text/plain", body: Data([0xFF, 0xFE])).bodyText == nil)
        #expect(response(204).bodyText == "")
    }

    @Test("Sizes and durations are short")
    func formatting() {
        #expect(ByteFormatter.short(512) == "512 B")
        #expect(ByteFormatter.short(4301) == "4.2 KB")
        #expect(ByteFormatter.short(3_000_000) == "2.9 MB")
        #expect(DurationFormatter.milliseconds(0.1837) == "184 ms")
        #expect(DurationFormatter.milliseconds(1.34) == "1.3 s")
    }
}
