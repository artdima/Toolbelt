//
//  MCPGuideView.swift
//  Toolbelt
//
//  The Setup Guide window: how to add each kind of resource, step by step.
//

import Observation
import SwiftUI

@Observable
@MainActor
final class MCPGuideNavigator {
    static let shared = MCPGuideNavigator()

    var kind = MCPResourceKind.gitlab
    /// Per kind: an address typed for GitLab must not end up in another kind's guide.
    private(set) var baseURLs: [MCPResourceKind: URL] = [:]

    var guide: MCPGuide {
        MCPProviders.provider(for: kind).guide(for: baseURLs[kind])
    }

    func open(_ kind: MCPResourceKind, baseURL: URL?) {
        self.kind = kind
        baseURLs[kind] = baseURL
    }
}

struct MCPGuideView: View {
    @Bindable var navigator: MCPGuideNavigator

    var body: some View {
        let guide = navigator.guide

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if MCPResourceKind.allCases.count > 1 {
                    PillPicker(selection: $navigator.kind, options: MCPResourceKind.allCases) { $0.title }
                }

                Text(guide.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                group("Steps") {
                    ForEach(Array(guide.steps.enumerated()), id: \.element.id) { index, step in
                        if index > 0 { Divider() }
                        stepRow(number: index + 1, step: step)
                    }
                }

                if !guide.examples.isEmpty {
                    group("Ask Claude") {
                        ForEach(Array(guide.examples.enumerated()), id: \.offset) { index, example in
                            if index > 0 { Divider() }
                            line(example, symbol: "text.bubble")
                        }
                    }
                }

                if !guide.notes.isEmpty {
                    group("Good to Know") {
                        ForEach(Array(guide.notes.enumerated()), id: \.offset) { index, note in
                            if index > 0 { Divider() }
                            line(note, symbol: "info.circle")
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minWidth: 420, minHeight: 400)
        .navigationTitle("Setup Guide")
        .navigationSubtitle(navigator.kind.title)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: title)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .card()
        }
    }

    private func stepRow(number: Int, step: MCPGuide.Step) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.07), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))

                Text(Self.markdown(step.text))
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !step.values.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(step.values, id: \.self) { value in
                            Text(verbatim: value)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .textSelection(.enabled)
                        }
                    }
                }

                if let link = step.link {
                    Link(destination: link.url) {
                        Label(link.title, systemImage: "arrow.up.right.square")
                    }
                    .font(.system(size: 12))
                    .help(link.url.absoluteString)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func line(_ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

#Preview {
    MCPGuideView(navigator: .shared)
}
