//
//  SettingsComponents.swift
//  Toolbelt
//
//  Building blocks shared by the settings sections.
//

import SwiftUI

enum SettingsMetrics {
    /// Every section has the same size, so switching tabs never resizes the window.
    static let paneSize = CGSize(width: 520, height: 420)
    static let labelInset: CGFloat = 4
}

struct SettingsPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: SettingsMetrics.paneSize.width, height: SettingsMetrics.paneSize.height)
    }
}

/// A title above a card, a card, and a hint under it.
struct SettingsGroup<Content: View, Footer: View>: View {
    private let title: String?
    private let content: Content
    private let footer: Footer

    init(
        _ title: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                SectionLabel(title: title)
            }

            VStack(spacing: 0) {
                content
            }
            .card()

            if Footer.self != EmptyView.self {
                footer
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SettingsMetrics.labelInset)
            }
        }
    }
}

extension SettingsGroup where Footer == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, content: content) { EmptyView() }
    }
}

/// One line of a settings card: a fixed-width label column and the control.
struct SettingsRow<RowLabel: View, Content: View>: View {
    private let labelWidth: CGFloat
    private let label: RowLabel
    private let content: Content

    init(
        labelWidth: CGFloat,
        @ViewBuilder label: () -> RowLabel,
        @ViewBuilder content: () -> Content
    ) {
        self.labelWidth = labelWidth
        self.label = label()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            label
                .font(.system(size: 13))
                .frame(width: labelWidth, alignment: .leading)
            content
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
    }
}
