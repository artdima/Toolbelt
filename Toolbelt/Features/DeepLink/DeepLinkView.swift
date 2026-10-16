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
        VStack(alignment: .leading, spacing: 20) {
            deviceSection
            linkSection

            if let warning = model.warning {
                NoticeBanner(systemImage: "exclamationmark.triangle", tint: .orange, message: {
                    Text(warning)
                })
            }

            historySection
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .frame(minWidth: 480, minHeight: 460)
        .task {
            await model.reloadTargets()
            isLinkFocused = true
        }
        .onChange(of: model.url) { _, _ in
            model.clearResult()
        }
    }

    // MARK: Device

    private var deviceSection: some View {
        labeled("Device") {
            HStack(spacing: 12) {
                Menu {
                    Picker("Device", selection: $model.selectedTargetID) {
                        ForEach(model.targets) { target in
                            Text(verbatim: target.title).tag(target.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    PickerCard(height: 39) { deviceLabel }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .disabled(model.targets.isEmpty)

                Group {
                    if model.isLoadingTargets {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await model.reloadTargets() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut("r")
                        .help("Look for simulators and devices again")
                    }
                }
                .frame(width: 28)
            }
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("myapp://profile/123", text: $model.url)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .focused($isLinkFocused)
                        .onSubmit { Task { await model.open() } }

                    Button {
                        Task { await model.open() }
                    } label: {
                        Text("Open")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(!model.canOpen)
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .frame(height: 43)
                .card()

                linkStatus
                    .padding(.horizontal, 3)
            }
        }
    }

    @ViewBuilder
    private var linkStatus: some View {
        if let result = model.result, !result.isSuccess {
            failureCard(result)
        } else if let result = model.result {
            HStack(spacing: 8) {
                Label(sentTitle, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                CopyButton(value: result.command, help: "Copy command")
            }
            .font(.system(size: 13))
        } else if model.showsSchemeHint {
            Text("The link has no scheme — it usually looks like \(Text.code("myapp://path"))")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
        } else if let target = model.selectedTarget {
            Text("Press Return to open on \(target.name)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var sentTitle: String {
        model.selectedTarget.map { "Sent to \($0.name)" } ?? "Sent"
    }

    private func failureCard(_ result: DeepLinkResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.red)
                Text("Could not open")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                CopyButton(value: result.command, help: "Copy command")
            }

            Text(result.command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !result.output.isEmpty {
                Text(result.output)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .card()
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle("History")
                Spacer()
                if model.history.hasUnpinned {
                    Button("Clear") {
                        model.history.clearUnpinned()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
                    .help("Remove every link that is not pinned")
                }
            }

            Group {
                if model.history.entries.isEmpty {
                    Text("Links you open will be kept here")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.url)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.url)
                HStack(spacing: 5) {
                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                    Text(subtitle(for: entry))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await model.reopen(entry) }
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(model.selectedTarget == nil || model.isOpening)
            .help(model.selectedTarget.map { "Open on \($0.name)" } ?? "Open")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(minHeight: 52)
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
            sectionTitle(title)
            content()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 3)
    }
}

#Preview {
    DeepLinkView()
}
