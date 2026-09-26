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
        HSplitView {
            historySidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 340)

            VSplitView {
                requestPane
                    .frame(minHeight: 300, idealHeight: 380)
                responsePane
                    .frame(minHeight: 180, idealHeight: 300)
            }
            .frame(minWidth: 500, maxWidth: .infinity)
        }
        .frame(minWidth: 720, minHeight: 560)
        .onChange(of: model.curlText) { _, _ in
            model.parseCurl()
        }
    }

    // MARK: Request

    private var requestPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            curlSection
            requestLine
            requestTabs

            switch model.requestTab {
            case .headers: headersEditor
            case .body: bodyEditor
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var curlSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("cURL")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.curlText.isEmpty {
                    Button("Clear") { model.clearCurl() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.curlText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                if model.curlText.isEmpty {
                    Text("Paste a curl command — the form below follows it as you type")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                        .padding(.leading, 9)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 84)
            .editorChrome()

            if let error = model.parseError {
                Text("⚠ \(error)")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
            ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                Text("⚠ \(warning)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var requestLine: some View {
        HStack(spacing: 8) {
            Picker("", selection: $model.draft.method) {
                ForEach(methodOptions, id: \.self) { method in
                    Text(method).tag(method)
                }
            }
            .labelsHidden()
            .fixedSize()

            TextField("https://api.example.com/v1/users", text: $model.draft.url)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
                .onSubmit { Task { await model.send() } }

            if model.isSending {
                ProgressView().controlSize(.small)
            }

            Button("Send") {
                Task { await model.send() }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!model.canSend)
            .help("Send the request (⌘↩)")
        }
    }

    /// A parsed command may carry a method that is not in the list; it is shown too.
    private var methodOptions: [String] {
        let method = model.draft.method
        if method.isEmpty || HTTPMethod.common.contains(method) {
            return HTTPMethod.common
        }
        return HTTPMethod.common + [method]
    }

    private var requestTabs: some View {
        HStack(spacing: 8) {
            Picker("", selection: $model.requestTab) {
                Text(model.headersTabTitle).tag(HTTPRequestViewModel.RequestTab.headers)
                Text(model.bodyTabTitle).tag(HTTPRequestViewModel.RequestTab.body)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()

            Spacer()

            Button {
                copy(model.curlCommand)
            } label: {
                Label("Copy as cURL", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .disabled(model.draft.url.isEmpty)
            .help("Copy the request as a curl command")
        }
    }

    private var headersEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.draft.headers.isEmpty {
                Text("No headers")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach($model.draft.headers) { $header in
                            headerRow($header)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button {
                model.addHeader()
            } label: {
                Label("Add header", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private func headerRow(_ header: Binding<HTTPHeader>) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: header.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(header.wrappedValue.isEnabled ? "Sent" : "Not sent")

            TextField("Name", text: header.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 200)

            TextField("Value", text: header.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            Button {
                model.removeHeader(id: header.wrappedValue.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Remove header")
        }
        .opacity(header.wrappedValue.isEnabled ? 1 : 0.55)
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $model.draft.body)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .editorChrome()

            if !model.draft.body.isEmpty, !model.draft.hasHeader(named: "Content-Type") {
                Text("No Content-Type header — the server will have to guess")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Response

    private var responsePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.sendError {
                ErrorBanner(text: error)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let response = model.response {
                statusLine(response)

                switch model.responseTab {
                case .body: responseBody
                case .headers: responseHeaders(response)
                }
            } else if model.isSending {
                LoadingState(text: "Sending…")
            } else if model.sendError == nil {
                EmptyState(systemImage: "arrow.down.circle", text: "Send a request to see the response here")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func statusLine(_ response: HTTPResponseSummary) -> some View {
        HStack(spacing: 8) {
            Text(String(response.statusCode))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(statusColor(response.statusClass))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            Text(response.statusText)
                .font(.system(size: 12, weight: .medium))

            Text(DurationFormatter.milliseconds(response.duration))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(ByteFormatter.short(response.body.count))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if model.responseTab == .body {
                Toggle("Pretty", isOn: $model.isPrettyPrinted)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .disabled(!model.canPrettyPrint)

                CopyButton(value: model.displayedBody ?? "", help: "Copy body")
            }

            Picker("", selection: $model.responseTab) {
                ForEach(HTTPRequestViewModel.ResponseTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var responseBody: some View {
        if let body = model.displayedBody {
            if body.isEmpty {
                EmptyState(systemImage: "doc", text: "Empty body")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: .constant(body))
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .editorChrome()

                    if model.isBodyTruncated {
                        Text("Showing the first \(ByteFormatter.short(HTTPRequestViewModel.bodyDisplayLimit)) of \(ByteFormatter.short(model.response?.body.count ?? 0))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            EmptyState(
                systemImage: "doc.zipper",
                text: "Binary body, \(ByteFormatter.short(model.response?.body.count ?? 0))"
            )
        }
    }

    private func responseHeaders(_ response: HTTPResponseSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(response.headers.enumerated()), id: \.element.id) { index, header in
                    if index > 0 { Divider() }
                    HStack(alignment: .top, spacing: 8) {
                        Text(header.name)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 200, alignment: .leading)
                        Text(header.value)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .editorChrome()
    }

    // MARK: History

    private var historySidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            if model.history.entries.isEmpty {
                Text("Requests you send will be kept here")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.history.sorted) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.03))
    }

    private func historyRow(_ entry: HTTPRequestEntry) -> some View {
        Button {
            model.load(entry)
        } label: {
            HStack(spacing: 6) {
                Text(entry.draft.method)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(methodColor(entry.draft.method))
                    .frame(width: 44, alignment: .leading)
                Text(entry.draft.displayURL)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if entry.isPinned {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.yellow)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(entry.draft.url)
        .contextMenu {
            Button(entry.isPinned ? "Unpin" : "Pin") { model.history.togglePin(entry) }
            Button("Copy as cURL") { copy(CurlBuilder.command(for: entry.draft)) }
            Divider()
            Button("Remove", role: .destructive) { model.history.remove(entry) }
        }
    }

    // MARK: Helpers

    private func statusColor(_ statusClass: HTTPResponseSummary.StatusClass) -> Color {
        switch statusClass {
        case .success: return .green
        case .redirect: return .blue
        case .clientError: return .orange
        case .serverError: return .red
        case .other: return .gray
        }
    }

    private func methodColor(_ method: String) -> Color {
        switch method {
        case "GET": return .green
        case "POST": return .orange
        case "PUT": return .blue
        case "PATCH": return .purple
        case "DELETE": return .red
        default: return .secondary
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private extension View {
    func editorChrome() -> some View {
        background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

#Preview {
    HTTPRequestView()
}
