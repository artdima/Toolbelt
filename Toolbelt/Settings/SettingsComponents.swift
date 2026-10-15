//
//  SettingsComponents.swift
//  Toolbelt
//
//  Building blocks shared by the settings sections.
//

import SwiftUI

enum SettingsMetrics {
    /// Every section has the same size, so switching tabs never resizes the window.
    static let paneSize = CGSize(width: 560, height: 460)
    static let labelInset: CGFloat = 5
}

struct SettingsPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
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
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsMetrics.labelInset)
            }

            VStack(spacing: 0) {
                content
            }
            .card()

            if Footer.self != EmptyView.self {
                footer
                    .font(.system(size: 12))
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
        .padding(.horizontal, 13)
        .frame(minHeight: 41)
    }
}

extension Text {
    /// Code inside a sentence: monospaced, at the size of the surrounding text.
    static func code(_ value: String) -> Text {
        Text(verbatim: value).monospaced()
    }
}
