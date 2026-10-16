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
        VStack(alignment: .leading, spacing: 12) {
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
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Sending…")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        PanePlaceholder(systemImage: "arrow.down", text: "Send a request to see the response here")
                    }
                }
                .card()
            }
        }
        .padding(.horizontal, 19)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }

    private func statusLine(_ response: HTTPResponseSummary) -> some View {
        let tint = statusColor(response.statusClass)

        return HStack(spacing: 14) {
            Text(String(response.statusCode))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(response.statusText)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            HStack(spacing: 12) {
                Label(DurationFormatter.milliseconds(response.duration), systemImage: "clock")
                Label(ByteFormatter.short(response.body.count), systemImage: "doc")
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            Spacer(minLength: 8)

            if model.responseTab == .body {
                Toggle("Pretty", isOn: $model.isPrettyPrinted)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 14))
                    .disabled(!model.canPrettyPrint)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.displayedBody ?? "", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
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
                PanePlaceholder(systemImage: "doc", text: "Empty body")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    TextEditor(text: .constant(body))
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if model.isBodyTruncated {
                        Divider()
                        Text("Showing the first \(ByteFormatter.short(HTTPRequestViewModel.bodyDisplayLimit)) of \(ByteFormatter.short(model.response?.body.count ?? 0))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
            }
        } else {
            PanePlaceholder(
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
                    HStack(alignment: .top, spacing: 10) {
                        Text(header.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(width: 200, alignment: .leading)
                        Text(header.value)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
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

/// An icon in a circle over a line of text, centered in an empty card.
private struct PanePlaceholder: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.08), in: Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
