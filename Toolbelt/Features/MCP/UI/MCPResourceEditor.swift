//
//  MCPResourceEditor.swift
//  Toolbelt
//
//  Adding a resource, checking its token, replacing the token, deleting the resource.
//

import Observation
import SwiftUI

enum MCPResourceEditorTarget: Identifiable {
    case add
    case edit(MCPResource)

    var id: String {
        switch self {
        case .add: "add"
        case let .edit(resource): resource.id.uuidString
        }
    }
}

@Observable
@MainActor
final class MCPResourceEditorModel {
    enum CheckState {
        case idle
        case checking
        case passed(MCPValidation, key: String)
        case failed(String)
    }

    let original: MCPResource?
    private let store: MCPResourceStore

    var kind: MCPResourceKind
    var name: String
    var address: String
    var token = ""
    private(set) var check = CheckState.idle
    private(set) var saveError: String?

    convenience init(target: MCPResourceEditorTarget) {
        self.init(target: target, store: .shared)
    }

    init(target: MCPResourceEditorTarget, store: MCPResourceStore) {
        self.store = store
        switch target {
        case .add:
            original = nil
            kind = .gitlab
            name = ""
            address = MCPProviders.provider(for: .gitlab).defaultBaseURL
        case let .edit(resource):
            original = resource
            kind = resource.kind
            name = resource.name
            address = resource.baseURL.absoluteString
        }
    }

    var isEditing: Bool { original != nil }
    var provider: any MCPProvider { MCPProviders.provider(for: kind) }
    var baseURL: URL? { MCPResource.validatedBaseURL(address) }
    var hint: MCPTokenHint { provider.tokenHint(for: baseURL) }

    var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return baseURL.flatMap(GitLabLinkParser.host(of:)) ?? ""
    }

    var addressProblem: String? {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty, baseURL == nil else { return nil }
        return "Use an https:// address; plain http only works for a server on this Mac."
    }

    var nameProblem: String? {
        guard !resolvedName.isEmpty, store.isNameTaken(resolvedName, except: original?.id) else { return nil }
        return "Another resource is already called “\(resolvedName)”."
    }

    /// What the last check vouches for: a new address or token needs a new check.
    private var checkKey: String {
        "\(baseURL?.absoluteString ?? "")\n\(trimmedToken)"
    }

    var passedValidation: MCPValidation? {
        guard case let .passed(validation, key) = check, key == checkKey else { return nil }
        return validation
    }

    private var keepsStoredSetup: Bool {
        guard let original else { return false }
        return trimmedToken.isEmpty && baseURL == original.baseURL
    }

    var canCheck: Bool {
        guard baseURL != nil else { return false }
        if case .checking = check { return false }
        return !trimmedToken.isEmpty || isEditing
    }

    var canSave: Bool {
        guard baseURL != nil, !resolvedName.isEmpty, nameProblem == nil else { return false }
        return passedValidation != nil || keepsStoredSetup
    }

    func runCheck() async {
        guard let baseURL else { return }
        let key = checkKey
        let tokenToCheck = trimmedToken.isEmpty ? original.flatMap { store.token(for: $0.id) } : trimmedToken
        guard let tokenToCheck, !tokenToCheck.isEmpty else {
            check = .failed("There is no token to check: paste one above.")
            return
        }

        check = .checking
        do {
            let validation = try await provider.validate(baseURL: baseURL, token: tokenToCheck)
            check = .passed(validation, key: key)
        } catch {
            check = .failed(MCPText.redacting([tokenToCheck], in: error.localizedDescription))
        }
    }

    func save() -> Bool {
        guard canSave, let baseURL else { return false }
        do {
            if var resource = original {
                resource.name = resolvedName
                resource.baseURL = baseURL
                if let validation = passedValidation { resource.account = validation.account }
                try store.update(resource, token: trimmedToken.isEmpty ? nil : trimmedToken)
            } else {
                let resource = MCPResource(
                    kind: kind,
                    name: resolvedName,
                    baseURL: baseURL,
                    account: passedValidation?.account
                )
                try store.add(resource, token: trimmedToken)
            }
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    func delete() -> Bool {
        guard let original else { return false }
        do {
            try store.delete(original.id)
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}

struct MCPResourceEditor: View {
    private enum Field {
        case name
        case address
        case token
    }

    @Environment(\.dismiss) private var dismiss
    @State private var model: MCPResourceEditorModel
    @State private var isTokenVisible = false
    @State private var isConfirmingDeletion = false
    @FocusState private var focusedField: Field?

    private let labelWidth: CGFloat = 96

    init(target: MCPResourceEditorTarget) {
        _model = State(initialValue: MCPResourceEditorModel(target: target))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.isEditing ? "Edit \(model.original?.name ?? "")" : "Add Resource")
                .font(.system(size: 14, weight: .semibold))

            SettingsGroup {
                if !model.isEditing {
                    SettingsRow(labelWidth: labelWidth) {
                        Text("Type")
                    } content: {
                        Picker("Type", selection: $model.kind) {
                            ForEach(MCPResourceKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Divider()
                }
                SettingsRow(labelWidth: labelWidth) {
                    Text("Name")
                } content: {
                    TextField(model.resolvedName.isEmpty ? "work" : model.resolvedName, text: $model.name)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .name)
                }
                Divider()
                SettingsRow(labelWidth: labelWidth) {
                    Text("Address")
                } content: {
                    TextField(model.provider.defaultBaseURL, text: $model.address)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .address)
                }
                Divider()
                SettingsRow(labelWidth: labelWidth) {
                    Text("Token")
                } content: {
                    tokenField
                }
            } footer: {
                hintText
            }

            if let problem = model.addressProblem ?? model.nameProblem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, SettingsMetrics.labelInset)
            }

            checkResult

            if let error = model.saveError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.horizontal, SettingsMetrics.labelInset)
            }

            HStack(spacing: 8) {
                if model.isEditing {
                    Button("Delete…", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Check") {
                    Task { await model.runCheck() }
                }
                .disabled(!model.canCheck)
                Button("Save") {
                    if model.save() { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSave)
            }
        }
        .padding(18)
        .frame(width: 460)
        .onAppear {
            focusedField = model.isEditing ? .token : .address
        }
        .confirmationDialog(
            "Delete “\(model.original?.name ?? "")”?",
            isPresented: $isConfirmingDeletion
        ) {
            Button("Delete", role: .destructive) {
                if model.delete() { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Claude loses access to it, and its token is erased from Keychain.")
        }
    }

    private var tokenField: some View {
        HStack(spacing: 8) {
            let placeholder = model.isEditing ? "Leave empty to keep the current token" : "glpat-…"
            Group {
                if isTokenVisible {
                    TextField(placeholder, text: $model.token)
                } else {
                    SecureField(placeholder, text: $model.token)
                }
            }
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .token)

            Button {
                isTokenVisible.toggle()
            } label: {
                Image(systemName: isTokenVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(isTokenVisible ? "Hide token" : "Show token")
        }
    }

    private var hintText: some View {
        let hint = model.hint
        var text = AttributedString(hint.text + " ")
        if let url = hint.url {
            var link = AttributedString("Open the token page")
            link.link = url
            text += link + AttributedString(". ")
        }
        text += AttributedString("Stored in Keychain only.")
        return Text(text)
    }

    @ViewBuilder
    private var checkResult: some View {
        switch model.check {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking the token…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SettingsMetrics.labelInset)
        case let .failed(message):
            NoticeBanner(systemImage: "xmark.octagon", tint: .red) {
                Text(message)
            }
        case let .passed(validation, _):
            NoticeBanner(
                systemImage: validation.warnings.isEmpty ? "checkmark.seal" : "exclamationmark.triangle",
                tint: validation.warnings.isEmpty ? .green : .orange
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(accountSummary(validation.account))
                        .fontWeight(.medium)
                    Text(tokenSummary(validation.account))
                        .foregroundStyle(.secondary)
                    ForEach(validation.warnings, id: \.self) { warning in
                        Text(warning)
                    }
                    if model.passedValidation == nil {
                        Text("The address or token changed after the check. Check again to save.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func accountSummary(_ account: MCPAccount) -> String {
        if let name = account.displayName, !name.isEmpty {
            return "@\(account.username) · \(name)"
        }
        return "@\(account.username)"
    }

    private func tokenSummary(_ account: MCPAccount) -> String {
        var parts: [String] = []
        if let tokenName = account.tokenName { parts.append("token “\(tokenName)”") }
        if let scopes = account.scopes { parts.append("scopes: \(scopes.isEmpty ? "none" : scopes.joined(separator: ", "))") }
        parts.append(MCPViewModel.expiryText(account).text)
        return parts.joined(separator: " · ")
    }
}
