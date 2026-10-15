//
//  PanelSection.swift
//  Toolbelt
//
//  A titled group of rows in the menu bar panel that folds under its header.
//

import SwiftUI

struct PanelSection<Content: View>: View {
    private let title: String
    private let content: Content

    @AppStorage private var isExpanded: Bool

    init(_ title: String, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        _isExpanded = AppStorage(wrappedValue: true, "panel.section.\(id).isExpanded")
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 5)
                .padding(.trailing, 9)
                .padding(.top, 11)
                .padding(.bottom, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")

            if isExpanded {
                content
            }
        }
    }
}
