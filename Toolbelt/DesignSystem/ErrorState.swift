//
//  ErrorState.swift
//  Toolbelt
//
//  A full-window error: an illustration, what went wrong, what to do next,
//  and the raw details folded away below.
//

import SwiftUI

struct ErrorState<Actions: View>: View {
    private let title: String
    private let message: String
    private let details: String
    private let retry: () -> Void
    private let actions: Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    init(
        title: String,
        message: String,
        details: String,
        retry: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.details = details
        self.retry = retry
        self.actions = actions()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    illustration

                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 18)

                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 8)

                    HStack(spacing: 10) {
                        Button(action: retry) {
                            Label("Try again", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)

                        actions
                    }
                    .buttonStyle(.bordered)
                    .menuStyle(.button)
                    .controlSize(.large)
                    .fixedSize()
                    .padding(.top, 22)

                    if !details.isEmpty {
                        TechnicalDetails(text: details)
                            .padding(.top, 32)
                    }
                }
                .frame(maxWidth: 440)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var illustration: some View {
        let isVisible = hasAppeared || reduceMotion

        return Image(.errorIllustration)
            .resizable()
            .scaledToFit()
            .frame(width: 220)
            .scaleEffect(isVisible ? 1 : 0.88)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) { hasAppeared = true }
            }
            .accessibilityHidden(true)
    }
}

extension ErrorState where Actions == EmptyView {
    init(title: String, message: String, details: String, retry: @escaping () -> Void) {
        self.init(title: title, message: message, details: details, retry: retry) { EmptyView() }
    }
}

private struct TechnicalDetails: View {
    let text: String

    @State private var isExpanded = false

    private var lines: [String] {
        text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text("Technical details")
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide details" : "Show details")

                CopyButton(value: text, help: "Copy technical details")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if isExpanded {
                code
                    .padding([.horizontal, .bottom], 6)
                    .transition(.opacity)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var code: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                GridRow {
                    Text(verbatim: "\(index + 1)")
                        .foregroundStyle(.tertiary)
                        .gridColumnAlignment(.trailing)
                    Text(verbatim: line)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    }
}

#Preview("Bad gateway") {
    ErrorState(
        title: "Unable to load report",
        message: "The server returned 502 Bad Gateway.\nPlease try again in a few moments.",
        details: """
        HTTP 502: <html>
        <head><title>502 Bad Gateway</title></head>
        <body>
        <center><h1>502 Bad Gateway</h1></center>
        <hr><center>nginx/1.18.0</center>
        </body>
        </html>
        """,
        retry: {}
    ) {
        Button("Change week") {}
    }
    .frame(width: 540, height: 720)
}
