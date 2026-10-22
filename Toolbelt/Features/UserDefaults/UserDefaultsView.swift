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
    @AppStorage("userDefaults.flutterHintDismissed") private var isFlutterHintDismissed = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                pickers
                content

                if let result = model.result, !result.isSuccess {
                    CommandFailureCard(title: "Command failed", command: result.command, output: result.output)
                }

                if let warning = model.warning {
                    NoticeBanner(systemImage: "exclamationmark.triangle", tint: .orange, message: {
                        Text(warning)
                    })
                }

                if model.showsFlutterHint && !isFlutterHintDismissed {
                    NoticeBanner(
                        systemImage: "info.circle",
                        tint: .orange,
                        onClose: { isFlutterHintDismissed = true }
                    ) {
                        Text("\(Text.code("shared_preferences")) keeps its own copy: a Flutter app sees edits after \(Text.code("prefs.reload()")) or a restart")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)

            if model.selectedApp != nil {
                Divider()
                footer
            }
        }
        .frame(minWidth: 540, minHeight: 420)
        .navigationTitle("User Defaults")
        .toolbar { refreshToolbar }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search keys and values")
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

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var refreshToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if model.isLoadingDevices || model.isLoadingApps || model.isLoadingEntries {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await model.reloadDevices() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Refresh simulators and apps")
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }

    // MARK: Pickers

    private var pickers: some View {
        HStack(alignment: .top, spacing: 8) {
            labeled("Device") {
                Menu {
                    Picker("Device", selection: deviceSelection) {
                        ForEach(model.devices) { device in
                            Text(verbatim: "\(device.name) — \(device.platform.title) \(device.osVersion)")
                                .tag(device.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    PickerCard { deviceLabel }
                }
                .disabled(model.devices.isEmpty)
            }
            .frame(width: 240)

            labeled("App") {
                Menu {
                    Picker("App", selection: appSelection) {
                        ForEach(model.apps) { app in
                            Text(verbatim: app.title)
                                .tag(app.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    PickerCard { appLabel }
                }
                .disabled(model.apps.isEmpty)
            }
            .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var deviceLabel: some View {
        if let device = model.selectedDevice {
            DeviceLabel(
                name: device.name,
                detail: "\(device.platform.title) \(device.osVersion)",
                isRunning: device.state == .booted
            )
        } else {
            Text(model.isLoadingDevices ? "Looking for simulators…" : "No booted simulators")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var appLabel: some View {
        if let app = model.selectedApp {
            HStack(spacing: 8) {
                Image(systemName: "app")
                    .foregroundStyle(.secondary)
                Text(app.name)
                    .layoutPriority(1)
                if app.name != app.bundleID {
                    Text(app.bundleID)
                        .foregroundStyle(.secondary)
                        .truncationMode(.middle)
                }
            }
        } else {
            Text(appPlaceholder)
                .foregroundStyle(.secondary)
        }
    }

    private var appPlaceholder: String {
        if model.selectedDevice == nil { return "—" }
        return model.isLoadingApps ? "Listing apps…" : "No apps installed from Xcode"
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
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: title)
            content()
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let error = model.readError {
            ErrorBanner(text: error)
        }

        if model.isLoadingDevices && model.devices.isEmpty {
            stateCard { LoadingState(text: "Looking for booted simulators…") }
        } else if model.devices.isEmpty {
            stateCard {
                EmptyState(
                    systemImage: "iphone.slash",
                    text: "Boot a simulator first — defaults are read from a running one"
                )
            }
        } else if model.apps.isEmpty {
            stateCard {
                if model.isLoadingApps {
                    LoadingState(text: "Listing apps…")
                } else {
                    EmptyState(systemImage: "app.dashed", text: "No apps installed from Xcode on this simulator")
                }
            }
        } else if model.entries.isEmpty {
            stateCard {
                if model.isLoadingEntries {
                    LoadingState(text: "Reading defaults…")
                } else {
                    EmptyState(systemImage: "tray", text: "The app has not stored any defaults yet")
                }
            }
        } else if model.visibleEntries.isEmpty {
            stateCard {
                EmptyState(systemImage: "magnifyingglass", text: "Nothing matches the search")
            }
        } else {
            entriesList
        }
    }

    private func stateCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
    }

    private var entriesList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    UserDefaultsRow(model: model, entry: entry, focusedKey: $focusedKey)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .card()
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text(keysSummary)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                model.reveal()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text("Reveal plist in Finder")
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.canReveal)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var keysSummary: String {
        let total = model.entries.count
        let shown = model.visibleEntries.count
        let keys = Plural.counted(total, "key", "keys")
        return shown == total ? keys : "\(shown) of \(keys)"
    }
}

#Preview {
    UserDefaultsView()
}
