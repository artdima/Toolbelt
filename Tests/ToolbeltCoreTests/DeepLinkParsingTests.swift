import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Device list parsing")
struct DeepLinkParsingTests {
    @Test("Simulators from simctl JSON")
    func simulatorsFromSimctl() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              { "udid": "AAA-111", "name": "iPhone 16 Pro", "state": "Booted" }
            ]
          }
        }
        """

        let targets = DeepLinkParsing.simulators(fromSimctlJSON: Data(json.utf8))
        let target = try #require(targets.first)

        #expect(targets.count == 1)
        #expect(target.platform == .ios)
        #expect(target.identifier == "AAA-111")
        #expect(target.name == "iPhone 16 Pro · iOS 18 0")
    }

    @Test("Multiple runtimes come back in a predictable order")
    func simulatorsAreOrdered() {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
              { "udid": "B", "name": "iPhone 17", "state": "Booted" }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              { "udid": "A", "name": "iPhone 16", "state": "Booted" }
            ]
          }
        }
        """

        #expect(DeepLinkParsing.simulators(fromSimctlJSON: Data(json.utf8)).map(\.identifier) == ["A", "B"])
    }

    @Test("Broken JSON yields an empty list")
    func brokenJSONIsEmpty() {
        #expect(DeepLinkParsing.simulators(fromSimctlJSON: Data("not json".utf8)).isEmpty)
    }

    @Test("Devices from adb devices -l output")
    func androidDevices() throws {
        let output = """
        List of devices attached
        emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1
        """

        let targets = DeepLinkParsing.androidDevices(fromAdbOutput: output)
        let target = try #require(targets.first)

        #expect(targets.count == 1)
        #expect(target.platform == .android)
        #expect(target.identifier == "emulator-5554")
        #expect(target.name == "sdk gphone64 arm64 · emulator-5554")
    }

    /// Only devices in the "device" state make the list.
    @Test("Unauthorized and offline devices are skipped")
    func onlyReadyDevicesAreListed() {
        let output = """
        List of devices attached
        emulator-5554          device
        1234567890             unauthorized
        abcdef                 offline
        """

        #expect(DeepLinkParsing.androidDevices(fromAdbOutput: output).map(\.identifier) == ["emulator-5554"])
    }

    @Test("A device without a model shows its serial")
    func deviceWithoutModel() {
        let output = """
        List of devices attached
        R58M1234ABC            device
        """

        #expect(DeepLinkParsing.androidDevices(fromAdbOutput: output).first?.name == "R58M1234ABC")
    }

    @Test("Empty adb output yields an empty list")
    func emptyAdbOutput() {
        #expect(DeepLinkParsing.androidDevices(fromAdbOutput: "List of devices attached\n").isEmpty)
    }

    @Test("A target id distinguishes platforms")
    func targetIdIncludesPlatform() {
        let ios = DeepLinkTarget(platform: .ios, identifier: "X", name: "n")
        let android = DeepLinkTarget(platform: .android, identifier: "X", name: "n")

        #expect(ios.id != android.id)
    }
}

@Suite("Command quoting")
struct ShellQuotingTests {
    /// adb reassembles the command on the device, so an `&` from the query string
    /// has to stay inside quotes.
    @Test("A link with an ampersand is quoted")
    func urlWithAmpersandIsQuoted() {
        #expect(Shell.singleQuoted("myapp://x?a=1&b=2") == "'myapp://x?a=1&b=2'")
    }

    @Test("A single quote inside the value is escaped")
    func singleQuoteInsideValue() {
        #expect(Shell.singleQuoted("a'b") == "'a'\\''b'")
    }

    @Test("The displayed command quotes shell metacharacters")
    func displayCommandQuotesSpecialCharacters() {
        let command = Shell.displayCommand("/usr/bin/xcrun", ["simctl", "openurl", "BOOTED", "myapp://x?a=1&b=2"])

        #expect(command == "/usr/bin/xcrun simctl openurl BOOTED \"myapp://x?a=1&b=2\"")
    }

    @Test("An already quoted argument gets double quotes around it")
    func alreadyQuotedArgument() {
        let command = Shell.displayCommand("/opt/adb", ["-d", "'myapp://x'"])

        #expect(command == "/opt/adb -d \"'myapp://x'\"")
    }

    @Test("Plain arguments stay bare")
    func plainArgumentsStayBare() {
        #expect(Shell.displayCommand("/usr/bin/git", ["status"]) == "/usr/bin/git status")
    }
}

@Suite("Tracker errors")
struct TrackerErrorTests {
    @Test("Status codes map to readable errors", arguments: [
        (401, TrackerError.unauthorized),
        (403, TrackerError.forbidden),
        (404, TrackerError.notFound)
    ])
    func knownStatuses(status: Int, expected: TrackerError) {
        #expect(TrackerError.from(status: status, body: "") == expected)
    }

    @Test("An unknown status keeps the response body")
    func unknownStatusKeepsBody() {
        let error = TrackerError.from(status: 500, body: "internal error")

        #expect(error == .http(status: 500, message: "internal error"))
    }

    /// The body reaches the UI, so it is truncated.
    @Test("A long response body is truncated")
    func longBodyIsTruncated() {
        let error = TrackerError.from(status: 500, body: String(repeating: "x", count: 1000))

        #expect(error == .http(status: 500, message: String(repeating: "x", count: 300)))
    }

    @Test("Every error carries a message for the user")
    func allErrorsHaveDescription() {
        let errors: [TrackerError] = [
            .missingToken, .missingOrgId, .invalidURL, .unexpectedResponse,
            .unauthorized, .forbidden, .notFound,
            .http(status: 500, message: "x"), .decoding("x"), .unknownUser
        ]

        #expect(errors.allSatisfy { $0.errorDescription?.isEmpty == false })
    }
}
