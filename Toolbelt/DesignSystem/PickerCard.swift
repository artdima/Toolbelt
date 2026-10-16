//
//  PickerCard.swift
//  Toolbelt
//
//  A menu that looks like a field: the current choice and the up-down chevrons.
//

import SwiftUI

struct PickerCard<Content: View>: View {
    private let height: CGFloat
    private let content: Content

    init(height: CGFloat = 36, @ViewBuilder content: () -> Content) {
        self.height = height
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 14))
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: height)
        .card(cornerRadius: 10)
        .contentShape(Rectangle())
    }
}

/// A running simulator or device: a green dot, its icon, the name and a gray detail.
struct DeviceLabel: View {
    let name: String
    let detail: String
    var systemImage = "iphone"
    var isRunning = true

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(isRunning ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Text(name)
                if !detail.isEmpty {
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
