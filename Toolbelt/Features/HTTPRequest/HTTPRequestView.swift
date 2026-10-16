//
//  HTTPRequestView.swift
//  Toolbelt
//
//  A curl command turned into a request, sent, and its response.
//

import SwiftUI

struct HTTPRequestView: View {
    @State private var model = HTTPRequestViewModel()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } detail: {
            VSplitView {
                requestPane
                    .frame(minHeight: 230, idealHeight: 290)
                HTTPResponsePane(model: model)
                    .frame(minHeight: 200)
            }
            .navigationTitle("HTTP Request")
            .toolbar { copyToolbar }
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: model.curlText) { _, _ in
            model.parseCurl()
        }
        .onDisappear {
            model.cancelSend()
        }
    }

    @ToolbarContentBuilder
    private var copyToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                copyToPasteboard(model.curlCommand)
            } label: {
                Label("Copy as cURL", systemImage: "doc.on.doc")
            }
            .labelStyle(.titleAndIcon)
            .disabled(model.draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Copy the request as a curl command")
        }
    }

    // MARK: History

    private var sidebar: some View {
        List(selection: historySelection) {
            Section {
                ForEach(model.history.sorted) { entry in
                    historyRow(entry)
                        .tag(entry.id)
                }
            } header: {
                HStack {
                    Text("History")
                    Spacer()
                    if model.history.hasUnpinned {
                        Button("Clear") {
                            model.clearHistory()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Remove every request that is not pinned")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.history.entries.isEmpty {
                Text("Requests you send will be kept here")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(20)
            }
        }
    }

    private var historySelection: Binding<HTTPRequestEntry.ID?> {
        Binding(
            get: { model.selectedHistoryID },
            set: { id in
                guard let id, let entry = model.history.entries.first(where: { $0.id == id }) else { return }
                model.load(entry)
            }
        )
    }

    private func historyRow(_ entry: HTTPRequestEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.draft.method)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(methodColor(entry.draft.method))
                .frame(width: 52, alignment: .leading)

            Text("\(Text(entry.draft.displayHost).foregroundStyle(.secondary))\(Text(entry.draft.displayPath))")
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .help(entry.draft.url)
        .contextMenu {
            Button(entry.isPinned ? "Unpin" : "Pin") { model.history.togglePin(entry) }
            Button("Copy as cURL") { copyToPasteboard(CurlBuilder.command(for: entry.draft)) }
            Divider()
            Button("Remove", role: .destructive) { model.history.remove(entry) }
        }
    }

    // MARK: Request

    private var requestPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            requestLine

            Picker("Request", selection: $model.requestTab) {
                Text(model.headersTabTitle).tag(HTTPRequestViewModel.RequestTab.headers)
                Text(model.bodyTabTitle).tag(HTTPRequestViewModel.RequestTab.body)
                Text("cURL").tag(HTTPRequestViewModel.RequestTab.curl)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .fixedSize()

            Group {
                switch model.requestTab {
                case .headers: headersEditor
                case .body: bodyEditor
                case .curl: curlEditor
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 19)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private var requestLine: some View {
        HStack(spacing: 0) {
            methodMenu
                .padding(.horizontal, 14)

            Divider()
                .frame(height: 20)

            TextField("https://api.example.com/v1/users", text: $model.draft.url)
                .textFieldStyle(.plain)
                .font(.system(size: 14, design: .monospaced))
                .padding(.horizontal, 12)
                .onSubmit { Task { await model.send() } }

            sendControls
                .padding(.trailing, 5)
        }
        .frame(height: 38)
        .card()
    }

    private var methodMenu: some View {
        Menu {
            Picker("Method", selection: $model.draft.method) {
                ForEach(methodOptions, id: \.self) { method in
                    Text(method).tag(method)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(model.draft.method)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(methodColor(model.draft.method))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// A parsed command may carry a method that is not in the list; it is shown too.
    private var methodOptions: [String] {
        let method = model.draft.method
        if method.isEmpty || HTTPMethod.common.contains(method) {
            return HTTPMethod.common
        }
        return HTTPMethod.common + [method]
    }

    @ViewBuilder
    private var sendControls: some View {
        if model.isSending {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Button("Cancel") {
                    model.cancelSend()
                }
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop the request (⌘.)")
            }
        } else {
            Button {
                Task { await model.send() }
            } label: {
                Text("Send")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canSend)
            .help("Send the request (⌘↩)")
        }
    }

    private var headersEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.draft.headers.isEmpty {
                Text("No headers")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($model.draft.headers) { $header in
                            if header.id != model.draft.headers.first?.id {
                                Divider()
                            }
                            headerRow($header)
                        }
                    }
                }
            }

            Button {
                model.addHeader()
            } label: {
                Label {
                    Text("Add Header")
                } icon: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func headerRow(_ header: Binding<HTTPHeader>) -> some View {
        HStack(spacing: 10) {
            Toggle("Send this header", isOn: header.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(header.wrappedValue.isEnabled ? "Sent" : "Not sent")

            TextField("Name", text: header.name)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 200)

            TextField("Value", text: header.value)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)

            Button {
                model.removeHeader(id: header.wrappedValue.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove header")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(header.wrappedValue.isEnabled ? 1 : 0.55)
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            codeEditor(text: $model.draft.body, placeholder: "Request body")

            if !model.draft.body.isEmpty, !model.draft.hasHeader(named: "Content-Type") {
                Text("No \(Text.code("Content-Type")) header — the server will have to guess")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 3)
            }
        }
    }

    private var curlEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            codeEditor(
                text: $model.curlText,
                placeholder: "Paste a curl command — the request follows it as you type"
            )
            .overlay(alignment: .topTrailing) {
                if !model.curlText.isEmpty {
                    Button("Clear") { model.clearCurl() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }

            if let error = model.parseError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 3)
            }
            ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 3)
            }
        }
    }

    private func codeEditor(text: Binding<String>, placeholder: String) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 7)
            .padding(.vertical, 10)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
    }
}

// MARK: - Helpers

private func methodColor(_ method: String) -> Color {
    switch method {
    case "GET": .green
    case "POST": .orange
    case "PUT": .blue
    case "PATCH": .purple
    case "DELETE": .red
    default: .secondary
    }
}

private func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

#Preview {
    HTTPRequestView()
}
