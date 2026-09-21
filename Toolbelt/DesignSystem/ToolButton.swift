//
//  ToolButton.swift
//  Toolbelt
//
//  A tool button in the menu bar panel.
//

import SwiftUI

struct ToolButton: View {
    let title: String
    let systemImage: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolRowLabel(title: title, systemImage: systemImage)
                .toolRowChrome(isDestructive: isDestructive)
        }
        .buttonStyle(.plain)
    }
}

struct ToolRowLabel<Accessory: View>: View {
    private let title: String
    private let systemImage: String
    private let accessory: Accessory

    init(
        title: String,
        systemImage: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            accessory
        }
    }
}

extension ToolRowLabel where Accessory == EmptyView {
    init(title: String, systemImage: String) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

extension View {
    func toolRowChrome(isDestructive: Bool = false) -> some View {
        self
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isDestructive ? Color.red.opacity(0.16) : Color.white.opacity(0.07))
            .foregroundStyle(isDestructive ? Color.red : Color.secondary)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
