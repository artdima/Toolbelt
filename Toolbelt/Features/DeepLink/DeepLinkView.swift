//
//  DeepLinkView.swift
//  Toolbelt
//
//  Testing a deep link on a booted iOS simulator or a connected Android device.
//

import SwiftUI

struct DeepLinkView: View {
    @State private var model = DeepLinkViewModel()
    @FocusState private var isLinkFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            deviceSection
            linkSection

            if let warning = model.warning {
                NoticeBanner(systemImage: "exclamationmark.triangle", tint: .orange, message: {
                    Text(warning)
                })
            }

            historySection
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(minWidth: 420, minHeight: 400)
        .navigationTitle("Deep Link")
        .toolbar { refreshToolbar }
        .task {
            await model.reloadTargets()
            isLinkFocused = true
        }
        .onChange(of: model.url) { _, _ in
            model.clearResult()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var refreshToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if model.isLoadingTargets {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await model.reloadTargets() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Look for simulators and devices again")
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }

    // MARK: Device

    private var deviceSection: some View {
        labeled("Device") {
            Menu {
                Picker("Device", selection: $model.selectedTargetID) {
                    ForEach(model.targets) { target in
                        Text(verbatim: target.title).tag(target.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                PickerCard { deviceLabel }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(model.targets.isEmpty)
        }
    }

    @ViewBuilder
    private var deviceLabel: some View {
        if let target = model.selectedTarget {
            DeviceLabel(
                name: target.name,
                detail: target.detail,
                systemImage: target.platform == .ios ? "iphone" : "candybarphone"
            )
        } else {
            Text(model.isLoadingTargets ? "Looking for devices…" : "No booted simulators and no connected devices")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Link

    private var linkSection: some View {
        labeled("Link") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("myapp://profile/123", text: $model.url)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .focused($isLinkFocused)
                        .onSubmit { Task { await model.open() } }

                    Button {
                        Task { await model.open() }
                    } label: {
                        Text("Open")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!model.canOpen)
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .frame(height: 32)
                .card()

                linkStatus
                    .font(.system(size: 11))
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var linkStatus: some View {
        if let result = model.result, !result.isSuccess {
            CommandFailureCard(title: "Could not open", command: result.command, output: result.output)
        } else if let result = model.result {
            HStack(spacing: 8) {
                Label(sentTitle, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                CopyButton(value: result.command, help: "Copy command")
            }
        } else if model.showsSchemeHint {
            Text("The link has no scheme — it usually looks like \(Text.code("myapp://path"))")
                .foregroundStyle(.orange)
        } else if let target = model.selectedTarget {
            Text("Press Return to open on \(target.name)")
                .foregroundStyle(.secondary)
        }
    }

    private var sentTitle: String {
        model.selectedTarget.map { "Sent to \($0.name)" } ?? "Sent"
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(title: "History")
                Spacer()
                if model.history.hasUnpinned {
                    Button("Clear") {
                        model.history.clearUnpinned()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 6)
                    .help("Remove every link that is not pinned")
                }
            }

            Group {
                if model.history.entries.isEmpty {
                    EmptyState(systemImage: "clock.arrow.circlepath", text: "Links you open will be kept here")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.history.sorted.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider() }
                                historyRow(entry)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
        }
    }

    private func historyRow(_ entry: DeepLinkEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.url)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.url)
                HStack(spacing: 5) {
                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                    Text(subtitle(for: entry))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await model.reopen(entry) }
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.selectedTarget == nil || model.isOpening)
            .help(model.selectedTarget.map { "Open on \($0.name)" } ?? "Open")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .onTapGesture {
            model.url = entry.url
            isLinkFocused = true
        }
        .contextMenu {
            Button("Open") { Task { await model.reopen(entry) } }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
            Button(entry.isPinned ? "Unpin" : "Pin") { model.history.togglePin(entry) }
            Divider()
            Button("Remove from History", role: .destructive) { model.history.remove(entry) }
        }
    }

    /// "iPhone 17 · Just now"; entries saved before devices were recorded show just the time, or nothing.
    private func subtitle(for entry: DeepLinkEntry) -> String {
        let time = entry.openedAt.map { RelativeTimeFormatter.short($0) }
        let parts = [entry.deviceName, time].compactMap { $0 }
        return parts.isEmpty ? (entry.isPinned ? "Pinned" : " ") : parts.joined(separator: " · ")
    }

    // MARK: Helpers

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: title)
            content()
        }
    }
}

#Preview {
    DeepLinkView()
}
