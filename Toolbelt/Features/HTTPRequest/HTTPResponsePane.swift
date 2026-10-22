//
//  HTTPResponsePane.swift
//  Toolbelt
//
//  The lower half of the HTTP Request window: the status line and the response.
//

import SwiftUI

struct HTTPResponsePane: View {
    @Bindable var model: HTTPRequestViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = model.sendError {
                NoticeBanner(systemImage: "xmark.octagon", tint: .red, message: {
                    Text(error)
                })
            } else if model.wasCancelled {
                NoticeBanner(systemImage: "xmark.circle", tint: .gray, message: {
                    Text(model.response == nil ? "Request cancelled" : "Request cancelled — showing the previous response")
                })
            }

            if let response = model.response {
                statusLine(response)

                Group {
                    switch model.responseTab {
                    case .body: responseBody
                    case .headers: responseHeaders(response)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .card()
            } else {
                Group {
                    if model.isSending {
                        LoadingState(text: "Sending…")
                    } else {
                        EmptyState(systemImage: "arrow.down", text: "Send a request to see the response here")
                    }
                }
                .card()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private func statusLine(_ response: HTTPResponseSummary) -> some View {
        let tint = statusColor(response.statusClass)

        return HStack(spacing: 10) {
            Text(String(response.statusCode))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(response.statusText)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 10) {
                Label(DurationFormatter.milliseconds(response.duration), systemImage: "clock")
                Label(ByteFormatter.short(response.body.count), systemImage: "doc")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            Spacer(minLength: 8)

            if model.responseTab == .body {
                Toggle("Pretty", isOn: $model.isPrettyPrinted)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .disabled(!model.canPrettyPrint)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.displayedBody ?? "", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled((model.displayedBody ?? "").isEmpty)
                .help("Copy body")
            }

            PillPicker(
                selection: $model.responseTab,
                options: HTTPRequestViewModel.ResponseTab.allCases
            ) { $0.rawValue }
        }
    }

    @ViewBuilder
    private var responseBody: some View {
        if let body = model.displayedBody {
            if body.isEmpty {
                EmptyState(systemImage: "doc", text: "Empty body")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: .constant(body))
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if model.isBodyTruncated {
                        Divider()
                        Text("Showing the first \(ByteFormatter.short(HTTPRequestViewModel.bodyDisplayLimit)) of \(ByteFormatter.short(model.response?.body.count ?? 0))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
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
                            .frame(width: 180, alignment: .leading)
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
    }

    private func statusColor(_ statusClass: HTTPResponseSummary.StatusClass) -> Color {
        switch statusClass {
        case .success: .green
        case .redirect: .blue
        case .clientError: .orange
        case .serverError: .red
        case .other: .gray
        }
    }
}
