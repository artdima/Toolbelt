import Testing
@testable import ToolbeltCore

@Suite("Login shell environment")
struct LoginShellEnvironmentTests {
    @Test("Startup noise before the marker is ignored")
    func noiseBeforeMarkerIsIgnored() {
        let output = "Welcome back!\n\(LoginShellEnvironment.marker)PATH=/usr/bin:/opt/homebrew/bin\0CLAUDE_CONFIG_DIR=/Users/me/.claude-work\0"

        #expect(LoginShellEnvironment.parse(output) == [
            "PATH": "/usr/bin:/opt/homebrew/bin",
            "CLAUDE_CONFIG_DIR": "/Users/me/.claude-work"
        ])
    }

    @Test("A value may contain an equals sign")
    func valueWithEqualsSign() {
        let output = "\(LoginShellEnvironment.marker)NODE_OPTIONS=--max-old-space-size=4096\0"

        #expect(LoginShellEnvironment.parse(output)?["NODE_OPTIONS"] == "--max-old-space-size=4096")
    }

    @Test("No marker means no environment")
    func missingMarker() {
        #expect(LoginShellEnvironment.parse("PATH=/usr/bin\0") == nil)
    }
}
