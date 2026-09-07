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
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let text: String

    var body: some View {
        Text("⚠ \(text)")
            .font(.system(size: 11))
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.1))
    }
}

struct SetupPrompt: View {
    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "key")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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
