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
        VStack(alignment: .leading, spacing: 10) {
            PillPicker(selection: $model.filter, options: SimulatorFilter.allCases) { $0.title }

            if let warning = model.warning {
                NoticeBanner(systemImage: "exclamationmark.triangle", tint: .orange, message: {
                    Text(warning)
                })
            }

            content

            if let result = model.result, !result.isSuccess {
                CommandFailureCard(title: "Could not start", command: result.command, output: result.output)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(minWidth: 420, minHeight: 400)
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
                VStack(alignment: .leading, spacing: 10) {
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
            FoldableSectionHeader(title: group.title, count: group.devices.count, isCollapsed: isCollapsed) {
                toggleGroup(group.id)
            }

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
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor(device.state))
                .frame(width: 7, height: 7)
                .help(device.state.title)

            Image(systemName: icon(for: device))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(device.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer(minLength: 8)

            actionButton(device)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 32)
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
                .frame(width: 22, height: 22)
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
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
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
