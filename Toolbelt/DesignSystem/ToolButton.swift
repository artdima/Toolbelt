//
//  ToolButton.swift
//  Toolbelt
//
//  Кнопка инструмента в панели строки меню.
//

import SwiftUI

struct ToolButton: View {
    let title: String
    let systemImage: String
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
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
        .buttonStyle(.plain)
    }
}
