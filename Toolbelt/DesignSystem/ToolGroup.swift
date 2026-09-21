//
//  ToolGroup.swift
//  Toolbelt
//
//  A tool button that unfolds nested tools underneath itself.
//

import SwiftUI

struct ToolGroup<Content: View>: View {
    private let title: String
    private let systemImage: String
    private let content: Content

    @State private var isExpanded = false

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                ToolRowLabel(title: title, systemImage: systemImage) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .toolRowChrome()
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide \(title) tools" : "Show \(title) tools")

            if isExpanded {
                VStack(spacing: 8) {
                    content
                }
                .padding(.leading, 16)
            }
        }
    }
}
