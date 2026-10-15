//
//  PanelRow.swift
//  Toolbelt
//
//  Rows and commands of the menu bar panel.
//

import SwiftUI

enum PanelRowRole {
    case standard
    case prominent
    case destructive
}

struct PanelRow: View {
    let title: String
    let systemImage: String
    var role: PanelRowRole = .standard
    var detail: String?
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PanelRowIcon(systemImage: systemImage, role: role, isBusy: isBusy)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(5)
        }
        .buttonStyle(PanelButtonStyle())
    }
}

struct PanelConfirmation: View {
    let title: String
    let message: String
    let systemImage: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                PanelRowIcon(systemImage: systemImage, role: .destructive, isBusy: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .controlSize(.small)
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }
}

private struct PanelRowIcon: View {
    let systemImage: String
    let role: PanelRowRole
    let isBusy: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: role == .prominent ? .bold : .medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 26, height: 26)
    }

    private var fill: Color {
        switch role {
        case .standard: Color.primary.opacity(0.1)
        case .prominent: Color.accentColor
        case .destructive: Color.red.opacity(0.15)
        }
    }

    private var tint: Color {
        switch role {
        case .standard: Color.primary
        case .prominent: Color.white
        case .destructive: Color.red
        }
    }
}

struct PanelCommand: View {
    let title: String
    let key: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
                Text("⌘" + String(key.character).uppercased())
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .buttonStyle(PanelButtonStyle())
        .keyboardShortcut(key, modifiers: .command)
    }
}

struct PanelDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 6)
    }
}

struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PanelButtonBody(configuration: configuration)
    }
}

private struct PanelButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(highlightOpacity))
            )
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }

    private var highlightOpacity: Double {
        guard isEnabled else { return 0 }
        if configuration.isPressed { return 0.12 }
        return isHovered ? 0.07 : 0
    }
}
