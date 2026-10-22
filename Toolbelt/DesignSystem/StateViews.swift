//
//  StateViews.swift
//  Toolbelt
//
//  Loading, empty and error states, identical across every window.
//

import SwiftUI

struct LoadingState: View {
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyState: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            StateIcon(systemImage: systemImage)
            Text(text)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let text: String
    var details: String?

    var body: some View {
        NoticeBanner(systemImage: "exclamationmark.triangle", tint: .red, message: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                message
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let details {
                    CopyButton(value: details, help: "Copy technical details")
                }
            }
        })
    }

    @ViewBuilder
    private var message: some View {
        let label = Text(verbatim: text)
            .textSelection(.enabled)

        if let details {
            label.help(details)
        } else {
            label
        }
    }
}

struct SetupPrompt: View {
    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            StateIcon(systemImage: "key")
            Text(text)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: action)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// A symbol in a soft circle above the text of an empty or setup state.
private struct StateIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 34)
            .background(Color.primary.opacity(0.08), in: Circle())
    }
}

struct CopyButton: View {
    let value: String
    var help = "Copy"

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(value.isEmpty)
        .help(help)
    }
}

struct RefreshButton: View {
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help("Refresh")
    }
}
