import Foundation
import Testing
@testable import ToolbeltCore

@Suite("MCP response text")
struct MCPTextTests {
    @Test("Truncation stays within the limit and says so")
    func limit() {
        let text = (1...3_000).map { "line \($0)" }.joined(separator: "\n")

        let head = MCPText.limited(text, limit: 2_000, keep: .head)
        #expect(head.count <= 2_000)
        #expect(head.hasPrefix("line 1\nline 2\n"))
        #expect(head.contains("[Truncated:"))

        let tail = MCPText.limited(text, limit: 2_000, keep: .tail)
        #expect(tail.count <= 2_000)
        #expect(tail.hasSuffix("line 3000"))
        #expect(tail.hasPrefix("[Truncated: the first"))

        #expect(MCPText.limited("short", limit: 2_000) == "short")
    }

    @Test("Secrets are replaced, short strings are left alone")
    func redaction() {
        let text = "Authorization failed for glpat-abcdef123456 at host"
        #expect(MCPText.redacting(["glpat-abcdef123456", "at"], in: text) == "Authorization failed for [redacted] at host")
    }
}

@Suite("MCP line framing")
struct LineFramerTests {
    @Test("Messages split across chunks, CRLF and blank lines")
    func framing() throws {
        var framer = LineFramer()
        #expect(try framer.append(Data(#"{"a":"#.utf8)).isEmpty)
        let first = try framer.append(Data("1}\r\n\n{\"b\":2}\n{\"c\"".utf8))
        #expect(first.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#, #"{"b":2}"#])
        #expect(framer.pendingByteCount == 4)
        let second = try framer.append(Data(":3}\n".utf8))
        #expect(second.map { String(decoding: $0, as: UTF8.self) } == [#"{"c":3}"#])
        #expect(framer.pendingByteCount == 0)
    }

    @Test("A message without a newline cannot grow forever")
    func limit() {
        var framer = LineFramer(limit: 8)
        #expect(throws: LineFramerError.lineTooLong(8)) {
            try framer.append(Data("0123456789".utf8))
        }
    }
}

@Suite("MCP resources")
struct MCPResourceTests {
    @Test("Only https leaves the Mac")
    func addresses() {
        #expect(MCPResource.validatedBaseURL("https://gitlab.gftech.ru/")?.absoluteString == "https://gitlab.gftech.ru")
        #expect(MCPResource.validatedBaseURL(" https://example.com/gitlab ")?.absoluteString == "https://example.com/gitlab")
        #expect(MCPResource.validatedBaseURL("http://localhost:8080")?.absoluteString == "http://localhost:8080")
        #expect(MCPResource.validatedBaseURL("http://gitlab.com") == nil)
        #expect(MCPResource.validatedBaseURL("gitlab.com") == nil)
        #expect(MCPResource.validatedBaseURL("https://user@gitlab.com") == nil)
    }

    @Test("Token expiry: days left, soon, expired")
    func expiry() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func account(daysFromNow days: Double) -> MCPAccount {
            MCPAccount(username: "u", expiry: .on(now.addingTimeInterval(days * 86_400)), checkedAt: now)
        }
        #expect(account(daysFromNow: 30).expiresSoon(now: now) == false)
        #expect(account(daysFromNow: 5.5).daysLeft(now: now) == 5)
        #expect(account(daysFromNow: 5.5).expiresSoon(now: now))
        #expect(account(daysFromNow: -1).isExpired(now: now))
        #expect(account(daysFromNow: -1).expiresSoon(now: now) == false)
        #expect(MCPAccount(username: "u", expiry: .never, checkedAt: now).daysLeft(now: now) == nil)
    }

    @Test("Resources saved before client credentials existed still load")
    func legacyResource() throws {
        let json = #"""
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"gitlab","name":"work",
          "baseURL":"https://gitlab.com","isEnabled":true,"allowWrite":false,
          "account":{"username":"dima","displayName":"Dima","scopes":["read_api"],"expiry":{"never":{}},"checkedAt":0}}]
        """#
        let resources = try JSONDecoder().decode([MCPResource].self, from: Data(json.utf8))
        let resource = try #require(resources.first)
        #expect(resource.clientID == nil)
        #expect(resource.account?.subjectID == nil)
        #expect(resource.account?.username == "dima")
        #expect(resource.account?.expiry == .never)
    }
}

@Suite("Claude Desktop config")
struct ClaudeDesktopConfigTests {
    private let helper = "/Applications/Toolbelt.app/Contents/MacOS/toolbelt-mcp"

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Other servers and settings are kept")
    func merge() throws {
        let existing = Data("""
        {"globalShortcut": "Cmd+Space", "mcpServers": {"other": {"command": "/bin/other", "args": ["-x"]}}}
        """.utf8)
        let merged = try object(ClaudeDesktopConfig.merged(existing, helperPath: helper))
        let servers = try #require(merged["mcpServers"] as? [String: Any])
        #expect(merged["globalShortcut"] as? String == "Cmd+Space")
        #expect((servers["other"] as? [String: Any])?["args"] as? [String] == ["-x"])
        #expect((servers["toolbelt"] as? [String: Any])?["command"] as? String == helper)
    }

    @Test("An existing entry only gets the new path")
    func update() throws {
        let existing = Data(#"{"mcpServers": {"toolbelt": {"command": "/old/toolbelt-mcp", "env": {"A": "1"}}}}"#.utf8)
        let merged = try object(ClaudeDesktopConfig.merged(existing, helperPath: helper))
        let entry = try #require((merged["mcpServers"] as? [String: Any])?["toolbelt"] as? [String: Any])
        #expect(entry["command"] as? String == helper)
        #expect((entry["env"] as? [String: String]) == ["A": "1"])
    }

    @Test("Files that are not a config are refused")
    func refusals() {
        #expect(throws: ClaudeConfigError.notAnObject) {
            try ClaudeDesktopConfig.merged(Data("[1]".utf8), helperPath: helper)
        }
        #expect(throws: ClaudeConfigError.serversNotAnObject) {
            try ClaudeDesktopConfig.merged(Data(#"{"mcpServers": []}"#.utf8), helperPath: helper)
        }
        #expect(throws: ClaudeConfigError.unreadable("it is not valid JSON")) {
            try ClaudeDesktopConfig.merged(Data("{".utf8), helperPath: helper)
        }
        #expect((try? ClaudeDesktopConfig.merged(Data("  \n".utf8), helperPath: helper)) != nil)
    }

    @Test("Install backs the old file up, and does nothing the second time")
    func install() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appending(path: "claude_desktop_config.json")
        let original = Data(#"{"mcpServers": {}}"#.utf8)
        try original.write(to: config)

        #expect(ClaudeDesktopConfig.status(helperPath: helper, configURL: config) == .notConnected)
        let first = try ClaudeDesktopConfig.install(helperPath: helper, configURL: config)
        let backup = try #require(first.backupURL)
        #expect(try Data(contentsOf: backup) == original)
        #expect(ClaudeDesktopConfig.status(helperPath: helper, configURL: config) == .connected)
        #expect(ClaudeDesktopConfig.status(helperPath: "/elsewhere", configURL: config) == .otherPath(helper))

        let second = try ClaudeDesktopConfig.install(helperPath: helper, configURL: config)
        #expect(second.wasAlreadyConnected)
        #expect(second.backupURL == nil)

        let missing = directory.appending(path: "nowhere/claude_desktop_config.json")
        #expect(ClaudeDesktopConfig.status(helperPath: helper, configURL: missing) == .notInstalled)
        #expect(throws: ClaudeConfigError.claudeNotInstalled) {
            try ClaudeDesktopConfig.install(helperPath: helper, configURL: missing)
        }
    }

    @Test("The Claude Code command quotes paths with spaces")
    func claudeCode() {
        #expect(ClaudeCodeCommand.add(helperPath: helper) == "claude mcp add --scope user toolbelt -- \(helper)")
        #expect(ClaudeCodeCommand.shellQuoted("/Users/me/My Apps/it's.app") == #"'/Users/me/My Apps/it'\''s.app'"#)
    }
}

@Suite("MCP socket")
struct MCPSocketTests {
    @Test("The socket is private to the user, accepts connections and is removed on stop")
    func listener() async throws {
        let directory = URL(fileURLWithPath: "/tmp").appending(path: "tb-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "mcp.sock").path(percentEncoded: false)

        let accepted = Locked(0)
        let listener = MCPSocketListener(path: path) { fd in
            accepted.withLock { $0 += 1 }
            close(fd)
        }
        try listener.start()

        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)

        #expect(throws: MCPSocketError.alreadyServed(path)) {
            try MCPSocketListener(path: path) { close($0) }.start()
        }

        let client = try #require(MCPSocket.dial(path))
        #expect(MCPSocket.peerUID(of: client) == getuid())
        for _ in 0..<100 where accepted.withLock({ $0 }) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(accepted.withLock { $0 } >= 1)
        close(client)

        listener.stop()
        for _ in 0..<100 where FileManager.default.fileExists(atPath: path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test("A socket left behind by a crash is replaced")
    func staleSocket() throws {
        let directory = URL(fileURLWithPath: "/tmp").appending(path: "tb-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appending(path: "mcp.sock").path(percentEncoded: false)
        _ = FileManager.default.createFile(atPath: path, contents: Data())

        let listener = MCPSocketListener(path: path) { close($0) }
        try listener.start()
        defer { listener.stop() }
        let client = try #require(MCPSocket.dial(path))
        close(client)
    }
}

@Suite("GitLab client")
struct GitLabClientTests {
    @Test("Project paths become one encoded segment")
    func projectSegment() {
        #expect(GitLabClient.projectSegment("growfood/gf_android_app") == "growfood%2Fgf_android_app")
        #expect(GitLabClient.projectSegment("/group/sub group/app/") == "group%2Fsub%20group%2Fapp")
        #expect(GitLabClient.projectSegment("123") == "123")
    }

    @Test("Retry-After in seconds or as a date")
    func retryAfter() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(GitLabClient.retryAfter("42") == 42)
        #expect(GitLabClient.retryAfter("Fri, 15 Jan 2027 08:00:30 GMT", now: now) == 30)
        #expect(GitLabClient.retryAfter(nil, now: now) == nil)
        #expect(GitLabClient.retryAfter("soon", now: now) == nil)
    }

    @Test("Error texts never carry the token")
    func errors() {
        let all: [GitLabError] = [
            .unauthorized(host: "g"), .forbidden(host: "g"), .notFound(host: "g"),
            .rateLimited(host: "g", retryAfter: 42), .server(host: "g", status: 500, message: "boom"),
            .network(host: "g", reason: "offline"), .redirected(host: "g", location: "https://evil"), .invalidResponse(host: "g")
        ]
        for error in all {
            #expect(error.errorDescription?.contains("g") == true)
        }
        #expect(GitLabError.rateLimited(host: "g", retryAfter: 42).errorDescription?.contains("Wait 42 s") == true)
    }
}
