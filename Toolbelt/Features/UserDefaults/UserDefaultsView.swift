//
//  UserDefaultsView.swift
//  Toolbelt
//
//  The standard UserDefaults of an app on a booted simulator: live, searchable, editable.
//

import SwiftUI

struct UserDefaultsView: View {
    @State private var model = UserDefaultsViewModel()
    @FocusState private var focusedKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pickers

            if let warning = model.warning {
                Text("⚠ \(warning)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            content

            if let result = model.result, !result.isSuccess {
                failureCard(result)
            }
        }
        .padding(18)
        .frame(minWidth: 600, minHeight: 460)
        .task {
            await model.reloadDevices()
        }
        .onDisappear {
            model.stopTracking()
        }
        .onChange(of: model.editingKey) { _, key in
            focusedKey = key
        }
        .onChange(of: focusedKey) { previous, current in
            if current == nil, previous != nil, model.editingKey == previous {
                Task { await model.endEditing() }
            }
        }
    }

    // MARK: Pickers

    private var pickers: some View {
        HStack(alignment: .bottom, spacing: 10) {
            labeled("Device") {
                if model.devices.isEmpty {
                    placeholder("No booted simulators")
                } else {
                    Picker("", selection: deviceSelection) {
                        ForEach(model.devices) { device in
                            Text("\(device.name) · \(device.platform.title) \(device.osVersion)").tag(device.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            labeled("App") {
                if model.apps.isEmpty {
                    placeholder(model.selectedDevice == nil ? "—" : "No apps installed from Xcode")
                } else {
                    Picker("", selection: appSelection) {
                        ForEach(model.apps) { app in
                            Text(app.title).tag(app.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack(spacing: 8) {
                if model.isLoadingDevices || model.isLoadingApps {
                    ProgressView().controlSize(.small)
                }

                RefreshButton(isDisabled: model.isLoadingDevices) {
                    Task { await model.reloadDevices() }
                }
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)
        }
    }

    private var deviceSelection: Binding<SimulatorDevice.ID> {
        Binding(
            get: { model.selectedDeviceID },
            set: { model.selectDevice($0) }
        )
    }

    private var appSelection: Binding<InstalledApp.ID> {
        Binding(
            get: { model.selectedBundleID },
            set: { model.selectApp($0) }
        )
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(height: 22)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.isLoadingDevices && model.devices.isEmpty {
            LoadingState(text: "Looking for booted simulators…")
        } else if model.devices.isEmpty {
            EmptyState(
                systemImage: "iphone.slash",
                text: "Boot a simulator first — defaults are read from a running one"
            )
        } else if model.apps.isEmpty {
            if model.isLoadingApps {
                LoadingState(text: "Listing apps…")
            } else {
                EmptyState(systemImage: "app.dashed", text: "No apps installed from Xcode on this simulator")
            }
        } else {
            searchField
            table
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField("Search keys and values", text: $model.search)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            if model.isLoadingEntries {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var table: some View {
        if let error = model.readError {
            ErrorBanner(text: error)
        }

        if model.entries.isEmpty {
            if model.isLoadingEntries {
                LoadingState(text: "Reading defaults…")
            } else {
                EmptyState(systemImage: "tray", text: "The app has not stored any defaults yet")
            }
        } else if model.visibleEntries.isEmpty {
            EmptyState(systemImage: "magnifyingglass", text: "Nothing matches the search")
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.visibleEntries) { entry in
                        row(entry)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ entry: UserDefaultsEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.key)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.key)
                Text(entry.value.typeName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 230, alignment: .leading)

            valueCell(entry)
                .frame(maxWidth: .infinity, alignment: .leading)

            CopyButton(value: entry.value.display, help: "Copy value")

            Button {
                Task { await model.delete(entry) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Delete key")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func valueCell(_ entry: UserDefaultsEntry) -> some View {
        switch entry.value {
        case let .bool(isOn):
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in Task { await model.set(entry, to: .bool(newValue)) } }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

        case .string, .integer, .double:
            if model.editingKey == entry.key {
                TextField("", text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(model.isDraftValid ? Color.primary : Color.red)
                    .focused($focusedKey, equals: entry.key)
                    .onSubmit { Task { await model.commitEditing() } }
                    .onExitCommand { model.cancelEditing() }
            } else {
                Button {
                    model.beginEditing(entry)
                } label: {
                    Text(entry.value.display.isEmpty ? "empty" : entry.value.display)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(entry.value.display.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to edit")
            }

        case .date, .data, .array, .dictionary:
            Text(entry.value.display)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(entry.value.display)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(keysSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Reveal plist in Finder") {
                    model.reveal()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .disabled(!model.canReveal)
            }

            if model.showsFlutterHint {
                Text("shared_preferences keeps its own copy: a Flutter app sees edits after prefs.reload() or a restart")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var keysSummary: String {
        let total = model.entries.count
        let shown = model.visibleEntries.count
        let keys = total == 1 ? "1 key" : "\(total) keys"
        return shown == total ? keys : "\(shown) of \(keys)"
    }

    private func failureCard(_ result: UserDefaultsActionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.red)
                Text("Command failed")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !result.command.isEmpty {
                    CopyButton(value: result.command, help: "Copy command")
                }
            }

            if !result.command.isEmpty {
                Text(result.command)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
}

#Preview {
    UserDefaultsView()
}
