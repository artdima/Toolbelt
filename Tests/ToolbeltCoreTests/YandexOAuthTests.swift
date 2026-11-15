import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Yandex OAuth sign-in link")
struct YandexOAuthLinkTests {
    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test("Asks for a token straight away, not for a code")
    func asksForToken() {
        let url = YandexOAuth.authorizeURL(clientID: "abc123", state: "s1")

        #expect(url?.host == "oauth.yandex.ru")
        #expect(url?.path == "/authorize")
        #expect(query(url)["response_type"] == "token")
        #expect(query(url)["client_id"] == "abc123")
        #expect(query(url)["state"] == "s1")
    }

    /// Editing and deleting entries needs write access; without it the token would only half work.
    @Test("Requests both Tracker permissions")
    func requestsReadAndWrite() {
        let url = YandexOAuth.authorizeURL(clientID: "abc123", state: "s1")

        #expect(query(url)["scope"] == "tracker:read tracker:write")
    }

    @Test("Leaves the redirect to the app's settings")
    func noRedirectURI() {
        let url = YandexOAuth.authorizeURL(clientID: "abc123", state: "s1")

        #expect(query(url)["redirect_uri"] == nil)
    }
}

@Suite("Yandex OAuth redirect")
struct YandexOAuthRedirectTests {
    private func outcome(_ string: String, state: String = "s1") -> YandexOAuth.Outcome? {
        URL(string: string).flatMap { YandexOAuth.outcome(of: $0, state: state) }
    }

    @Test("The token and its lifetime come from the fragment")
    func tokenFromFragment() {
        let result = outcome("https://oauth.yandex.ru/verification_code#access_token=y0_AgAAAA-x_1&token_type=bearer&expires_in=31536000&state=s1")

        #expect(result == .token("y0_AgAAAA-x_1", expiresIn: 31_536_000))
    }

    @Test("A redirect without state is still accepted")
    func noStateIsAccepted() {
        let result = outcome("https://oauth.yandex.ru/verification_code#access_token=y0_abc")

        #expect(result == .token("y0_abc", expiresIn: nil))
    }

    @Test("Another request's answer is ignored")
    func foreignStateIsIgnored() {
        #expect(outcome("https://oauth.yandex.ru/verification_code#access_token=y0_abc&state=other") == nil)
    }

    @Test("Pages on the way are not an answer", arguments: [
        "https://oauth.yandex.ru/authorize?response_type=token&client_id=abc",
        "https://passport.yandex.ru/auth?retpath=x",
        "https://passport.yandex.ru/auth#section",
        "https://oauth.yandex.ru/verification_code#"
    ])
    func intermediatePages(url: String) {
        #expect(outcome(url) == nil)
    }

    @Test("A refusal comes back as an error with its description")
    func errorWithDescription() {
        let result = outcome("https://oauth.yandex.ru/verification_code#error=access_denied&error_description=User+denied%20access&state=s1")

        #expect(result == .failure(code: "access_denied", description: "User denied access"))
    }

    @Test("Known errors say what to do", arguments: ["access_denied", "invalid_scope", "unauthorized_client"])
    func knownErrorsHaveOwnText(code: String) {
        let message = YandexOAuth.message(forError: code, description: "raw")

        #expect(!message.contains("raw"))
    }

    @Test("A missing permission names both of them")
    func invalidScopeNamesPermissions() {
        let message = YandexOAuth.message(forError: "invalid_scope", description: nil)

        #expect(message.contains("Read from tracker"))
        #expect(message.contains("Write to tracker"))
    }

    @Test("An unknown error falls back to Yandex's words, then to its code")
    func unknownErrorFallsBack() {
        #expect(YandexOAuth.message(forError: "server_error", description: "Try later") == "Yandex OAuth: Try later")
        #expect(YandexOAuth.message(forError: "server_error", description: nil).contains("server_error"))
    }
}
