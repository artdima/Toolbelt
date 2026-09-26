import Foundation
import Testing
@testable import ToolbeltCore

@Suite("curl command export")
struct CurlBuilderTests {
    @Test("A plain GET is one line without -X")
    func plainGet() {
        let draft = HTTPRequestDraft(url: "https://x.dev/a?b=1&c=2")
        #expect(CurlBuilder.command(for: draft) == "curl 'https://x.dev/a?b=1&c=2'")
    }

    @Test("Headers and body go on their own lines")
    func postWithBody() {
        let draft = HTTPRequestDraft(
            method: "POST",
            url: "https://x.dev",
            headers: [HTTPHeader(name: "Content-Type", value: "application/json")],
            body: #"{"a":1}"#
        )
        let expected = """
        curl -X POST 'https://x.dev' \\
          -H 'Content-Type: application/json' \\
          --data-raw '{"a":1}'
        """
        #expect(CurlBuilder.command(for: draft) == expected)
    }

    @Test("Single quotes inside values are escaped the bash way")
    func singleQuotes() {
        let draft = HTTPRequestDraft(method: "POST", url: "https://x.dev", body: "it's")
        #expect(CurlBuilder.command(for: draft).hasSuffix("--data-raw 'it'\\''s'"))
    }

    @Test("HEAD uses -I, a GET with a body keeps -X GET")
    func specialMethods() {
        #expect(CurlBuilder.command(for: HTTPRequestDraft(method: "HEAD", url: "https://x.dev")) == "curl -I 'https://x.dev'")
        let getWithBody = HTTPRequestDraft(method: "get", url: "https://x.dev", body: "q")
        #expect(CurlBuilder.command(for: getWithBody).hasPrefix("curl -X GET 'https://x.dev'"))
    }

    @Test("An empty header value uses curl's `Name;` form")
    func emptyHeader() throws {
        let draft = HTTPRequestDraft(url: "https://x.dev", headers: [HTTPHeader(name: "X-Empty", value: "")])
        #expect(CurlBuilder.command(for: draft).hasSuffix("-H 'X-Empty;'"))
        #expect(try CurlParser.parse(CurlBuilder.command(for: draft)).draft == draft)
    }

    @Test("Disabled and nameless headers are left out")
    func skippedHeaders() {
        let draft = HTTPRequestDraft(
            url: "https://x.dev",
            headers: [
                HTTPHeader(name: "X-Off", value: "1", isEnabled: false),
                HTTPHeader(name: "  ", value: "orphan")
            ]
        )
        #expect(CurlBuilder.command(for: draft) == "curl 'https://x.dev'")
    }

    @Test("Parsing the exported command gives the draft back")
    func roundTrip() throws {
        let draft = HTTPRequestDraft(
            method: "PUT",
            url: "https://x.dev/items/1?full=true",
            headers: [
                HTTPHeader(name: "Content-Type", value: "application/json"),
                HTTPHeader(name: "X-Trace", value: "it's \"quoted\"")
            ],
            body: "{\n  \"a\": 1\n}"
        )
        let parsed = try CurlParser.parse(CurlBuilder.command(for: draft))
        #expect(parsed.draft == draft)
        #expect(parsed.warnings.isEmpty)
    }
}
