//
//  SimulatorsView.swift
//  Toolbelt
//
//  Launching an iOS simulator or an Android emulator without Xcode and Android Studio.
//

import SwiftUI

struct SimulatorsView: View {
    @State private var model = SimulatorsViewModel()
    /// Group ids separated by newlines: AppStorage keeps plain values only.
    @AppStorage("simulators.collapsedGroups") private var collapsedGroupsStorage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Show", selection: $model.filter) {
                ForEach(SimulatorFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .fixedSize()

            if let warning = model.warning {
                NoticeBanner(systemImage: "exclamationmark.triangle", tint: .orange, message: {
                    Text(warning)
                })
            }

            content

            if let result = model.result, !result.isSuccess {
                failureCard(result)
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 2)
        .padding(.bottom, 17)
        .frame(minWidth: 480, minHeight: 480)
        .navigationTitle("Simulators")
        .toolbar { refreshToolbar }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
        .task {
            await model.reload()
        }
        .onDisappear {
            model.stopTracking()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var refreshToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await model.reload() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Look for simulators and emulators again")
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.devices.isEmpty {
            LoadingState(text: "Looking for simulators…")
        } else if model.groups.isEmpty {
            EmptyState(systemImage: "iphone.slash", text: emptyText)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.groups) { group in
                        groupSection(group)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyText: String {
        if model.devices.isEmpty { return "No iOS simulators and no Android AVDs were found" }
        if !isSearching { return "No \(model.filter.title) devices" }
        return "Nothing matches the search"
    }

    private var isSearching: Bool {
        !model.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func groupSection(_ group: SimulatorGroup) -> some View {
        // A search shows its matches even inside a group folded earlier.
        let isCollapsed = !isSearching && collapsedGroups.contains(group.id)

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                toggleGroup(group.id)
            } label: {
                HStack(spacing: 6) {
                    Text(group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(group.devices.count)")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .padding(.leading, 4)
                .padding(.trailing, 13)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Show \(group.title)" : "Hide \(group.title)")

            if !isCollapsed {
                VStack(spacing: 0) {
                    ForEach(Array(group.devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 { Divider() }
                        row(device)
                    }
                }
                .card()
            }
        }
    }

    private func row(_ device: SimulatorDevice) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor(device.state))
                .frame(width: 8, height: 8)
                .help(device.state.title)

            Image(systemName: icon(for: device))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(device.name)
                .font(.system(size: 14))
                .lineLimit(1)

            Spacer(minLength: 8)

            actionButton(device)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 40)
        .contextMenu {
            if device.state == .shutdown {
                Button("Launch") { Task { await model.boot(device) } }
            } else {
                Button("Stop") { Task { await model.shutdown(device) } }
                    .disabled(!model.canStop(device))
            }
            Divider()
            Button(device.platform == .ios ? "Copy UDID" : "Copy AVD Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.identifier, forType: .string)
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ device: SimulatorDevice) -> some View {
        if model.isBusy(device) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 26, height: 26)
        } else if device.state == .shutdown {
            circleButton("play.fill", tint: .accentColor, help: "Launch") {
                Task { await model.boot(device) }
            }
        } else {
            circleButton("stop.fill", tint: .red, help: "Stop") {
                Task { await model.shutdown(device) }
            }
            .disabled(!model.canStop(device))
            .opacity(model.canStop(device) ? 1 : 0.4)
        }
    }

    private func circleButton(
        _ systemImage: String,
        tint: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func failureCard(_ result: SimulatorActionResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.red)
                Text("Could not start")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if !result.command.isEmpty {
                    CopyButton(value: result.command, help: "Copy command")
                }
            }

            if !result.command.isEmpty {
                Text(result.command)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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

    // MARK: Helpers

    private var collapsedGroups: Set<String> {
        Set(collapsedGroupsStorage.split(separator: "\n").map(String.init))
    }

    private func toggleGroup(_ id: String) {
        var groups = collapsedGroups
        if groups.contains(id) {
            groups.remove(id)
        } else {
            groups.insert(id)
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            collapsedGroupsStorage = groups.sorted().joined(separator: "\n")
        }
    }

    private func icon(for device: SimulatorDevice) -> String {
        switch device.platform {
        case .ios: device.isTablet ? "ipad" : "iphone"
        case .android: "candybarphone"
        }
    }

    private func stateColor(_ state: SimulatorState) -> Color {
        switch state {
        case .shutdown: Color.primary.opacity(0.25)
        case .booting: Color.orange
        case .booted: Color.green
        }
    }
}

#Preview {
    SimulatorsView()
}
