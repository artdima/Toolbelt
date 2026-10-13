import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Tracker failures")
struct TrackerFailureTests {
    private let gatewayPage = """
    <html>
    <head><title>502 Bad Gateway</title></head>
    <body>
    <center><h1>502 Bad Gateway</h1></center>
    <hr><center>nginx/1.18.0</center>
    </body>
    </html>
    """

    @Test("A gateway error names the status instead of dumping the page")
    func gatewayErrorNamesStatus() {
        let failure = TrackerFailure(TrackerError.from(status: 502, body: gatewayPage))

        #expect(failure.reason == "The server returned 502 Bad Gateway.")
        #expect(failure.suggestion == "Please try again in a few moments.")
        #expect(!failure.needsSettings)
    }

    @Test("The raw response is kept for the technical details")
    func detailsKeepResponseBody() {
        let failure = TrackerFailure(TrackerError.from(status: 502, body: gatewayPage))

        #expect(failure.details == "HTTP 502: \(gatewayPage)")
    }

    @Test("A client error has no retry suggestion")
    func clientErrorHasNoSuggestion() {
        let failure = TrackerFailure(TrackerError.from(status: 400, body: ""))

        #expect(failure.suggestion == nil)
        #expect(failure.message == failure.reason)
    }

    @Test("Credential problems point to Settings", arguments: [
        TrackerError.unauthorized, .forbidden, .missingToken, .missingOrgId, .unknownUser
    ])
    func credentialProblemsNeedSettings(error: TrackerError) {
        #expect(TrackerFailure(error).needsSettings)
    }

    @Test("Being offline is told apart from a server failure")
    func offlineHasOwnMessage() {
        let failure = TrackerFailure(URLError(.notConnectedToInternet))

        #expect(failure.reason == "You appear to be offline.")
        #expect(failure.details.hasPrefix("URLError -1009"))
    }

    @Test("The suggestion goes on its own line")
    func messageJoinsReasonAndSuggestion() {
        let failure = TrackerFailure(reason: "Reason.", suggestion: "Suggestion.", details: "")

        #expect(failure.message == "Reason.\nSuggestion.")
    }

    @Test("An unknown error keeps its own description")
    func unknownErrorKeepsDescription() {
        let error = NSError(domain: "Test", code: 7, userInfo: [NSLocalizedDescriptionKey: "Something broke"])
        let failure = TrackerFailure(error)

        #expect(failure.reason == "Something broke")
        #expect(!failure.details.isEmpty)
    }
}
