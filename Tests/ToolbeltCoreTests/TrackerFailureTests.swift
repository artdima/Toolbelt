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

    @Test("An unlisted status falls back to the bare code")
    func unlistedStatusFallsBackToCode() {
        let failure = TrackerFailure(TrackerError.from(status: 520, body: ""))

        #expect(failure.reason == "The server returned HTTP 520.")
        #expect(failure.suggestion == "Please try again in a few moments.")
    }

    @Test("Credential problems point to Settings", arguments: [
        TrackerError.unauthorized, .forbidden, .missingToken, .missingOrgId, .unknownUser
    ])
    func credentialProblemsNeedSettings(error: TrackerError) {
        #expect(TrackerFailure(error).needsSettings)
    }

    @Test("A malformed URL does not send the user to Settings")
    func invalidURLDoesNotNeedSettings() {
        #expect(!TrackerFailure(TrackerError.invalidURL).needsSettings)
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

@Suite("Failures changing an entry")
struct WorklogChangeFailureTests {
    /// The credentials did load the report, so a 403 here is about the entry.
    @Test("Access denied to an entry does not send the user to Settings")
    func forbiddenIsAboutEntry() {
        let failure = TrackerFailure.worklogChange(TrackerError.forbidden)

        #expect(failure.reason == "Tracker did not allow changing this entry.")
        #expect(!failure.needsSettings)
    }

    @Test("A missing entry is told apart from a missing page")
    func notFoundIsAboutEntry() {
        let failure = TrackerFailure.worklogChange(TrackerError.notFound)

        #expect(failure.reason == "This entry is no longer in Tracker.")
        #expect(failure.suggestion != nil)
    }

    @Test("A rejected change keeps Tracker's explanation in the details", arguments: [400, 422])
    func rejectedChange(status: Int) {
        let failure = TrackerFailure.worklogChange(TrackerError.from(status: status, body: "duration is required"))

        #expect(failure.reason == "Tracker rejected the change.")
        #expect(failure.details.contains("duration is required"))
    }

    @Test("An expired token still points to Settings")
    func unauthorizedNeedsSettings() {
        #expect(TrackerFailure.worklogChange(TrackerError.unauthorized).needsSettings)
    }

    @Test("Network errors read the same as when loading")
    func networkErrorFallsBack() {
        let error = URLError(.notConnectedToInternet)

        #expect(TrackerFailure.worklogChange(error) == TrackerFailure(error))
    }
}

@Suite("Worklog")
struct WorklogTests {
    @Test("Changing the comment keeps everything else")
    func withCommentKeepsTheRest() {
        let entry = Worklog(
            id: 7,
            issueKey: "MOB-1",
            issueTitle: "Cart",
            comment: "Old",
            start: Date(timeIntervalSince1970: 1_000),
            seconds: 9000
        )
        let updated = entry.with(comment: "New")

        #expect(updated.comment == "New")
        #expect(updated == Worklog(
            id: 7, issueKey: "MOB-1", issueTitle: "Cart", comment: "New",
            start: Date(timeIntervalSince1970: 1_000), seconds: 9000
        ))
    }
}
