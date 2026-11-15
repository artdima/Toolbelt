//
//  TrackerSignInView.swift
//  Toolbelt
//
//  Getting a Tracker token by the ClientID of an app on oauth.yandex.ru: the user
//  signs in to Yandex right here, and the token goes straight to Keychain.
//

import Observation
import SwiftUI

@Observable
@MainActor
final class TrackerSignInModel {
    enum Phase: Equatable {
        case form
        case signingIn(URL)
        case signedIn(expiresAt: Date?)
    }

    private static let clientIDKey = "tracker.oauthClientID"

    private let store: TrackerCredentialsStore
    private let defaults: UserDefaults
    /// Ties the redirect to the request that this window sent.
    private var state = ""

    var clientID: String
    private(set) var phase = Phase.form
    private(set) var failure: String?

    convenience init() {
        self.init(store: .shared, defaults: .standard)
    }

    init(store: TrackerCredentialsStore, defaults: UserDefaults) {
        self.store = store
        self.defaults = defaults
        clientID = defaults.string(forKey: Self.clientIDKey) ?? ""
    }

    var trimmedClientID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canContinue: Bool { !trimmedClientID.isEmpty }
    var needsOrganization: Bool { store.credentials.orgId.isEmpty }

    func start() {
        guard canContinue, phase == .form else { return }
        defaults.set(trimmedClientID, forKey: Self.clientIDKey)
        state = UUID().uuidString

        guard let url = YandexOAuth.authorizeURL(clientID: trimmedClientID, state: state) else {
            failure = "Could not build the Yandex OAuth address from this ClientID."
            return
        }
        failure = nil
        phase = .signingIn(url)
    }

    func cancel() {
        phase = .form
    }

    func handle(_ url: URL) -> Bool {
        guard case .signingIn = phase,
              let outcome = YandexOAuth.outcome(of: url, state: state)
        else { return false }

        switch outcome {
        case let .token(token, expiresIn):
            save(token, expiresIn: expiresIn)
        case let .failure(code, description):
            failure = YandexOAuth.message(forError: code, description: description)
            phase = .form
        }
        return true
    }

    func loadFailed(_ error: Error) {
        guard case .signingIn = phase else { return }
        failure = "Could not open Yandex OAuth: \(error.localizedDescription)"
        phase = .form
    }

    private func save(_ token: String, expiresIn: TimeInterval?) {
        var credentials = store.credentials
        credentials.token = token

        do {
            try store.save(credentials)
            phase = .signedIn(expiresAt: expiresIn.map { Date(timeIntervalSinceNow: $0) })
        } catch {
            failure = "Yandex issued a token, but Keychain did not store it: \(error.localizedDescription)"
            phase = .form
        }
    }
}

struct TrackerSignInView: View {
    @State private var model = TrackerSignInModel()
    @State private var isLoading = false

    var body: some View {
        content
            .frame(minWidth: 440, minHeight: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .form:
            form
        case let .signingIn(url):
            signIn(url)
        case let .signedIn(expiresAt):
            done(expiresAt: expiresAt)
        }
    }

    // MARK: Form

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    intro
                    appChecklist
                    clientIDField

                    if let failure = model.failure {
                        ErrorBanner(text: failure)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { AppWindows.closeTrackerSignIn() }
                    .keyboardShortcut(.cancelAction)
                Button("Continue") { model.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
            }
            .padding(12)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Get a Tracker Token")
                .font(.system(size: 16, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text("Sign in to Yandex in this window, and Toolbelt keeps the token it issues in Keychain. All it needs is the ClientID of your app on oauth.yandex.ru.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var appChecklist: some View {
        SettingsGroup("Your app on oauth.yandex.ru") {
            ChecklistRow(number: 1) {
                Text("Create one [for API access or debugging](https://oauth.yandex.ru/client/new/), or open the one you have.")
            }
            Divider()
            ChecklistRow(number: 2) {
                Text("Under Data access, add **Read from tracker** and **Write to tracker**.")
            }
            Divider()
            ChecklistRow(number: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Redirect URI:")
                    Text.code(YandexOAuth.redirectURI)
                        .textSelection(.enabled)
                    CopyButton(value: YandexOAuth.redirectURI, help: "Copy the Redirect URI")
                }
            }
        }
    }

    private var clientIDField: some View {
        SettingsGroup {
            SettingsRow(labelWidth: 80) {
                Text("ClientID")
            } content: {
                TextField("From the app's page", text: $model.clientID)
                    .textFieldStyle(.plain)
                    .onSubmit { model.start() }
            }
        } footer: {
            Text("Not the Client secret: Toolbelt does not need it.")
        }
    }

    // MARK: Signing in

    private func signIn(_ url: URL) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    model.cancel()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("oauth.yandex.ru")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            OAuthWebView(
                url: url,
                onAddress: { model.handle($0) },
                onFailure: { model.loadFailed($0) },
                isLoading: $isLoading
            )
            .id(url)
        }
    }

    // MARK: Done

    private func done(expiresAt: Date?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            Text("Token Saved")
                .font(.system(size: 16, weight: .bold))

            Text(doneMessage(expiresAt: expiresAt))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Done") { AppWindows.closeTrackerSignIn() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneMessage(expiresAt: Date?) -> String {
        var lines = ["It is in Keychain, and the Tracker windows already use it."]
        if let expiresAt {
            lines.append("Valid until \(AppFormatters.fullDate.string(from: expiresAt)).")
        }
        if model.needsOrganization {
            lines.append("Set the organization ID in Settings to finish.")
        }
        return lines.joined(separator: "\n")
    }
}

private struct ChecklistRow<Content: View>: View {
    let number: Int
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 12)

            content
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

#Preview {
    TrackerSignInView()
        .frame(width: 480, height: 640)
}
