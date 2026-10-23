//
//  MCPView.swift
//  Toolbelt
//
//  The MCP window: the server and its clients, the resources Claude reaches, the call log.
//

import SwiftUI

struct MCPView: View {
    @State private var model = MCPViewModel()
    @State private var editor: MCPResourceEditorTarget?
    @State private var pendingWriteAccess: MCPResource?
    @AppStorage("mcp.collapsedSections") private var collapsedSectionsStorage = ""

    private static let logTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppFormatters.locale
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("Server", id: "server") {
                    serverCard
                    if let notice = model.desktopNotice {
                        NoticeBanner(
                            systemImage: notice.isError ? "exclamationmark.triangle" : "arrow.clockwise.circle",
                            tint: notice.isError ? .orange : .accentColor,
                            onClose: model.dismissDesktopNotice
                        ) {
                            Text(notice.text)
                        }
                    }
                }

                section("Resources", id: "resources", count: model.store.resources.count) {
                    resourcesCard
                    HStack(spacing: 8) {
                        Button {
                            editor = .add
                        } label: {
                            Label("Add Resource", systemImage: "plus")
                        }
                        Button {
                            AppWindows.mcpGuide()
                        } label: {
                            Label("Setup Guide", systemImage: "questionmark.circle")
                        }
                        .help("How to add each kind of resource, step by step")
                    }
                    .buttonBorderShape(.capsule)
                }

                section("Call Log", id: "log", count: model.hub.log.count) {
                    logCard
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 500, minHeight: 420)
        .navigationTitle("MCP")
        .toolbar { toolbar }
        .sheet(item: $editor) { target in
            MCPResourceEditor(target: target)
        }
        .confirmationDialog(
            "Allow Claude to write?",
            isPresented: isConfirmingWriteAccess,
            presenting: pendingWriteAccess
        ) { resource in
            Button("Allow Write") {
                model.store.setAllowWrite(true, for: resource.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { resource in
            Text(MCPProviders.provider(for: resource.kind).writeAccessWarning(for: resource))
        }
        .task {
            model.refreshDesktopStatus()
            await model.recheckAccounts()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if model.isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    model.refreshDesktopStatus()
                    Task { await model.recheckAccounts() }
                } label: {
                    Label("Check Tokens", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Check every enabled token with its service again")
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }

    // MARK: Server

    private var serverCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.hub.statusTitle)
                        .font(.system(size: 13, weight: .medium))
                    Text(serverDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Toggle("MCP enabled", isOn: Binding(
                    get: { model.hub.isEnabled },
                    set: { model.hub.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help(model.hub.isEnabled ? "Turn MCP off: the socket closes and clients disconnect" : "Turn MCP on")
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)

            ForEach(model.hub.clients) { client in
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(client.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("since \(AppFormatters.time.string(from: client.connectedAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
            }

            Divider()
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Desktop")
                        .font(.system(size: 13))
                    Text(model.desktopStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(model.desktopStatus == .connected ? Color.secondary : Color.orange)
                }
                Spacer(minLength: 8)
                Button(model.desktopButtonTitle, action: model.connectClaudeDesktop)
                    .disabled(model.desktopStatus == .connected || model.desktopStatus == .notInstalled || model.helperPath == nil)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)

            Divider()
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code")
                        .font(.system(size: 13))
                    Text(model.claudeCodeCommand ?? "toolbelt-mcp is missing from the app bundle")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(model.claudeCodeCommand ?? "")
                }
                Spacer(minLength: 8)
                Button(model.isCommandCopied ? "Copied" : "Copy Command", action: model.copyClaudeCodeCommand)
                    .disabled(model.claudeCodeCommand == nil)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 42)
        }
        .card()
    }

    private var serverDetail: String {
        switch model.hub.state {
        case .off:
            return "The socket is closed; Claude cannot reach Toolbelt."
        case let .failed(reason):
            return reason
        case .running:
            return model.hub.socketPath
        }
    }

    private var statusColor: Color {
        switch model.hub.state {
        case .off: Color.primary.opacity(0.25)
        case .failed: Color.red
        case .running: model.hub.clients.isEmpty ? Color.orange : Color.green
        }
    }

    // MARK: Resources

    @ViewBuilder
    private var resourcesCard: some View {
        if model.store.resources.isEmpty {
            Text("Nothing yet. Add a GitLab instance and Claude can read its pipelines, job logs and merge requests.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .card()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.store.resources.enumerated()), id: \.element.id) { index, resource in
                    if index > 0 { Divider() }
                    resourceRow(resource)
                }
            }
            .card()
        }
    }

    private func resourceRow(_ resource: MCPResource) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: resource.kind.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(resource.isEnabled ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.07), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(resource.name)
                        .font(.system(size: 13, weight: .medium))
                    Text(resource.kind.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Text(accountLine(resource))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                tokenLine(resource)
            }
            .opacity(resource.isEnabled ? 1 : 0.6)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Toggle("Enabled", isOn: Binding(
                    get: { resource.isEnabled },
                    set: { model.store.setEnabled($0, for: resource.id) }
                ))
                allowWriteToggle(resource)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 11))

            Button {
                editor = .edit(resource)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Edit \(resource.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contextMenu {
            Button("Edit…") { editor = .edit(resource) }
            Button(resource.isEnabled ? "Turn Off" : "Turn On") {
                model.store.setEnabled(!resource.isEnabled, for: resource.id)
            }
            Divider()
            Button("Setup Guide…") {
                AppWindows.mcpGuide(kind: resource.kind, baseURL: resource.baseURL)
            }
        }
    }

    private func accountLine(_ resource: MCPResource) -> String {
        MCPProviders.provider(for: resource.kind).accountLine(resource)
    }

    @ViewBuilder
    private func allowWriteToggle(_ resource: MCPResource) -> some View {
        if MCPProviders.provider(for: resource.kind).supportsWrite {
            Toggle("Allow write", isOn: Binding(
                get: { resource.allowWrite },
                set: { allow in
                    if allow {
                        pendingWriteAccess = resource
                    } else {
                        model.store.setAllowWrite(false, for: resource.id)
                    }
                }
            ))
            .help("Lets Claude publish and change data through this resource")
        } else {
            Toggle("Allow write", isOn: .constant(resource.allowWrite))
                .disabled(true)
                .help("Toolbelt has no write tools for \(resource.kind.title) yet")
        }
    }

    /// Cancelling leaves the switch off: it only turns on after Allow Write.
    private var isConfirmingWriteAccess: Binding<Bool> {
        Binding(
            get: { pendingWriteAccess != nil },
            set: { if !$0 { pendingWriteAccess = nil } }
        )
    }

    @ViewBuilder
    private func tokenLine(_ resource: MCPResource) -> some View {
        if let error = model.accountErrors[resource.id] {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(2)
                .help(error)
        } else if let account = resource.account {
            let expiry = MCPViewModel.expiryText(account)
            HStack(spacing: 4) {
                if expiry.tint != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                Text(expiry.text)
            }
            .font(.system(size: 11))
            .foregroundStyle(expiry.tint ?? Color.secondary)
        } else {
            Text("not checked yet")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Call log

    @ViewBuilder
    private var logCard: some View {
        if model.hub.log.isEmpty {
            Text("Tool calls from Claude show up here, the last \(MCPHub.logLimit) of them.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .card()
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.hub.log.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        logRow(entry)
                    }
                }
                .card()

                Button("Clear Log", action: model.hub.clearLog)
                    .controlSize(.small)
            }
        }
    }

    private func logRow(_ entry: MCPCallLogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: entry.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(entry.isError ? Color.red : Color.green)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(entry.tool)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text(entry.client)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !entry.arguments.isEmpty {
                    Text(entry.arguments)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(entry.arguments)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(Self.logTime.string(from: entry.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(DurationFormatter.milliseconds(entry.duration)) · \(Self.size(entry.responseSize))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private static func size(_ characters: Int) -> String {
        if characters < 1_000 { return "\(characters) chars" }
        return String(format: "%.1fK chars", Double(characters) / 1_000)
    }

    // MARK: Sections

    private func section<Content: View>(
        _ title: String,
        id: String,
        count: Int? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isCollapsed = collapsedSections.contains(id)

        return VStack(alignment: .leading, spacing: 6) {
            FoldableSectionHeader(title: title, count: count, isCollapsed: isCollapsed) {
                toggleSection(id)
            }

            if !isCollapsed {
                content()
            }
        }
    }

    private var collapsedSections: Set<String> {
        Set(collapsedSectionsStorage.split(separator: "\n").map(String.init))
    }

    private func toggleSection(_ id: String) {
        var sections = collapsedSections
        if sections.contains(id) {
            sections.remove(id)
        } else {
            sections.insert(id)
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            collapsedSectionsStorage = sections.sorted().joined(separator: "\n")
        }
    }
}

#Preview {
    MCPView()
}
