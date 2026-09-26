import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Shell word splitting")
struct ShellWordsTests {
    @Test("Quotes, escapes and line continuations")
    func quoting() throws {
        let line = """
        curl 'https://x.dev/a b' "say \\"hi\\"" plain\\ word \\
          --last
        """
        #expect(try ShellWords.split(line) == ["curl", "https://x.dev/a b", "say \"hi\"", "plain word", "--last"])
    }

    @Test("ANSI-C quoting turns escapes into characters")
    func ansiQuoting() throws {
        #expect(try ShellWords.split("$'a\\nb\\x41\\'c'") == ["a\nbA'c"])
    }

    @Test("Spaces after a continuation backslash do not become an argument")
    func trailingSpaceContinuation() throws {
        #expect(try ShellWords.split("curl \\   \n  https://x.dev") == ["curl", "https://x.dev"])
    }

    @Test("An empty quoted string is still an argument")
    func emptyArgument() throws {
        #expect(try ShellWords.split("-H '' x") == ["-H", "", "x"])
    }

    @Test("An unclosed quote is an error")
    func unclosedQuote() {
        #expect(throws: CurlParseError.unterminatedQuote) {
            try ShellWords.split("curl 'https://x.dev")
        }
    }
}

@Suite("curl command parsing")
struct CurlParserTests {
    @Test("A command copied from Chrome")
    func chromeCopy() throws {
        let command = """
        curl 'https://api.example.com/v1/users?page=2' \\
          -H 'accept: application/json' \\
          -H 'authorization: Bearer abc123' \\
          --data-raw '{"name":"Ann"}' \\
          --compressed
        """

        let result = try CurlParser.parse(command)

        #expect(result.draft.method == "POST")
        #expect(result.draft.url == "https://api.example.com/v1/users?page=2")
        #expect(result.draft.headers == [
            HTTPHeader(name: "accept", value: "application/json"),
            HTTPHeader(name: "authorization", value: "Bearer abc123"),
            HTTPHeader(name: "Content-Type", value: "application/x-www-form-urlencoded")
        ])
        #expect(result.draft.body == #"{"name":"Ann"}"#)
        #expect(result.warnings.isEmpty)
    }

    @Test("A bare URL is a GET")
    func plainGet() throws {
        let result = try CurlParser.parse("curl https://x.dev/health")
        #expect(result.draft == HTTPRequestDraft(url: "https://x.dev/health"))
        #expect(result.warnings.isEmpty)
    }

    @Test("The method comes from -X, attached or not")
    func explicitMethod() throws {
        #expect(try CurlParser.parse("curl -X put https://x.dev").draft.method == "PUT")
        #expect(try CurlParser.parse("curl -XPATCH https://x.dev -d a=1").draft.method == "PATCH")
        #expect(try CurlParser.parse("curl --request=DELETE https://x.dev/1").draft.method == "DELETE")
        #expect(try CurlParser.parse("curl -I https://x.dev").draft.method == "HEAD")
        #expect(try CurlParser.parse("curl -X '' https://x.dev").draft.method == "GET")
    }

    @Test("Several -d values are joined, -G moves them into the query")
    func dataHandling() throws {
        let post = try CurlParser.parse("curl https://x.dev -d a=1 -d b=2")
        #expect(post.draft.method == "POST")
        #expect(post.draft.body == "a=1&b=2")

        let get = try CurlParser.parse("curl -G 'https://x.dev/s?q=1' -d page=2 --data-urlencode 'name=a b'")
        #expect(get.draft.method == "GET")
        #expect(get.draft.url == "https://x.dev/s?q=1&page=2&name=a%20b")
        #expect(get.draft.body.isEmpty)
        #expect(get.draft.headers.isEmpty)
    }

    @Test("--json sets both JSON headers")
    func jsonOption() throws {
        let result = try CurlParser.parse(#"curl https://x.dev --json '{"a":1}'"#)
        #expect(result.draft.method == "POST")
        #expect(result.draft.body == #"{"a":1}"#)
        #expect(result.draft.headers == [
            HTTPHeader(name: "Content-Type", value: "application/json"),
            HTTPHeader(name: "Accept", value: "application/json")
        ])
    }

    @Test("An explicit Content-Type is not duplicated")
    func contentTypeKept() throws {
        let result = try CurlParser.parse("curl https://x.dev -H 'content-type: text/plain' -d hello")
        #expect(result.draft.headers == [HTTPHeader(name: "content-type", value: "text/plain")])
    }

    @Test("Credentials, cookies, agent and referer become headers")
    func headerShortcuts() throws {
        let result = try CurlParser.parse(
            "curl https://x.dev -u ann:secret -b 'a=1; b=2' -A Toolbelt -e https://ref.dev"
        )
        #expect(result.draft.headers == [
            HTTPHeader(name: "Authorization", value: "Basic YW5uOnNlY3JldA=="),
            HTTPHeader(name: "Cookie", value: "a=1; b=2"),
            HTTPHeader(name: "User-Agent", value: "Toolbelt"),
            HTTPHeader(name: "Referer", value: "https://ref.dev")
        ])
    }

    @Test("Header lines without a colon are skipped, `Name;` sends an empty header")
    func headerLines() throws {
        let result = try CurlParser.parse("curl https://x.dev -H Nonsense -H 'X-Empty;'")
        #expect(result.draft.headers == [HTTPHeader(name: "X-Empty", value: "")])
        #expect(result.warnings.count == 1)
    }

    @Test("Bash quoting reaches the request intact")
    func quoting() throws {
        let result = try CurlParser.parse(#"curl "https://x.dev/p" -H "X-Quote: say \"hi\"" --data-raw $'a\nb'"#)
        #expect(result.draft.headers.first == HTTPHeader(name: "X-Quote", value: "say \"hi\""))
        #expect(result.draft.body == "a\nb")
    }

    @Test("Clustered boolean flags and prompt prefix do not swallow the URL")
    func flagClusters() throws {
        let result = try CurlParser.parse("$ curl -sSL -o out.json https://x.dev")
        #expect(result.draft.url == "https://x.dev")
        #expect(result.warnings.isEmpty)
    }

    @Test("A URL without a scheme gets http:// and a warning")
    func missingScheme() throws {
        let result = try CurlParser.parse("curl example.com/api")
        #expect(result.draft.url == "http://example.com/api")
        #expect(result.warnings.count == 1)
    }

    @Test("Unsupported options produce warnings, not errors")
    func warnings() throws {
        let result = try CurlParser.parse("curl -k https://x.dev -F 'file=@a.png' --foo=bar extra")
        #expect(result.draft.url == "https://x.dev")
        #expect(result.warnings.count == 4)
    }

    @Test("Errors: no URL, missing value, empty command")
    func errors() {
        #expect(throws: CurlParseError.missingURL) { try CurlParser.parse("curl -X POST") }
        #expect(throws: CurlParseError.missingValue(option: "-H")) { try CurlParser.parse("curl https://x.dev -H") }
        #expect(throws: CurlParseError.empty) { try CurlParser.parse("   ") }
    }
}
