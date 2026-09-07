//
//  DeepLinkView.swift
//  Toolbelt
//
//  Testing a deep link on a booted iOS simulator or a connected Android device.
//

import SwiftUI

struct DeepLinkView: View {
    @State private var model = DeepLinkViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            devicePicker

            if let warning = model.warning {
                Text("⚠ \(warning)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            linkField

            if let result = model.result {
                resultCard(result)
            }

            historySection
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 460)
        .task {
            await model.reloadTargets()
        }
    }

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Device")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if model.targets.isEmpty {
                    Text("No booted simulators and no connected devices")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker("", selection: $model.selectedTargetID) {
                        ForEach(model.targets) { target in
                            Text(target.title).tag(target.id)
                        }
                    }
                    .labelsHidden()
                }

                if model.isLoadingTargets {
                    ProgressView().controlSize(.small)
                }

                RefreshButton(isDisabled: model.isLoadingTargets) {
                    Task { await model.reloadTargets() }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var linkField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Link")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("myapp://profile/123", text: $model.url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit { Task { await model.open() } }

                Button("Open") {
                    Task { await model.open() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canOpen)
            }

            if model.showsSchemeHint {
                Text("The link has no scheme — it usually looks like myapp://path")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func resultCard(_ result: DeepLinkResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.isSuccess ? Color.green : Color.red)
                Text(result.isSuccess ? "Link sent" : "Could not open")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                CopyButton(value: result.command, help: "Copy command")
            }

            Text(result.command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !result.output.isEmpty {
                Text(result.output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if model.history.entries.isEmpty {
                Text("Links you open will be kept here")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.history.sorted) { entry in
                            historyRow(entry)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func historyRow(_ entry: DeepLinkEntry) -> some View {
        HStack(spacing: 8) {
            Button {
                model.history.togglePin(entry)
            } label: {
                Image(systemName: entry.isPinned ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.isPinned ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(entry.isPinned ? "Unpin" : "Pin")

            Button {
                model.url = entry.url
            } label: {
                Text(entry.url)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Paste into the field")

            Button {
                model.history.remove(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Remove from history")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    DeepLinkView()
}
