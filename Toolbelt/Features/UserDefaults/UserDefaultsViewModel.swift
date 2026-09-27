//
//  UserDefaultsViewModel.swift
//  Toolbelt
//

import Observation
import SwiftUI

@Observable
@MainActor
final class UserDefaultsViewModel {
    private static let trackingInterval: Duration = .seconds(2)

    private let controller: UserDefaultsControlling

    var search = ""
    var draft = ""

    private(set) var selectedDeviceID: SimulatorDevice.ID = ""
    private(set) var selectedBundleID: InstalledApp.ID = ""
    private(set) var devices: [SimulatorDevice] = []
    private(set) var apps: [InstalledApp] = []
    private(set) var entries: [UserDefaultsEntry] = []
    private(set) var warning: String?
    private(set) var readError: String?
    private(set) var result: UserDefaultsActionResult?
    private(set) var isLoadingDevices = false
    private(set) var isLoadingApps = false
    private(set) var isLoadingEntries = false
    private(set) var editingKey: String?

    private var isReadingEntries = false
    private var tracking: Task<Void, Never>?

    convenience init() {
        self.init(controller: UserDefaultsRunner())
    }

    init(controller: UserDefaultsControlling) {
        self.controller = controller
    }

    var selectedDevice: SimulatorDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    var selectedApp: InstalledApp? {
        apps.first { $0.id == selectedBundleID }
    }

    var editingEntry: UserDefaultsEntry? {
        entries.first { $0.key == editingKey }
    }

    var visibleEntries: [UserDefaultsEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.key.lowercased().contains(query) || $0.value.display.lowercased().contains(query)
        }
    }

    var isDraftValid: Bool {
        editingEntry?.value.replacing(with: draft) != nil
    }

    /// shared_preferences reads the domain once at start and keeps its own copy.
    var showsFlutterHint: Bool {
        entries.contains { $0.key.hasPrefix("flutter.") }
    }

    var canReveal: Bool {
        selectedApp?.dataContainer != nil
    }

    func reloadDevices() async {
        guard !isLoadingDevices else { return }

        isLoadingDevices = true
        defer { isLoadingDevices = false }

        let loaded = await controller.devices()
        devices = loaded.devices
        warning = loaded.warning

        if devices.contains(where: { $0.id == selectedDeviceID }) {
            await reloadApps()
        } else {
            selectDevice(devices.first?.id ?? "")
        }
    }

    func selectDevice(_ id: SimulatorDevice.ID) {
        guard id != selectedDeviceID else { return }

        selectedDeviceID = id
        apps = []
        selectApp("")
        Task { await reloadApps() }
    }

    func selectApp(_ id: InstalledApp.ID) {
        guard id != selectedBundleID else { return }

        selectedBundleID = id
        entries = []
        editingKey = nil
        readError = nil
        result = nil
        stopTracking()

        guard !id.isEmpty else { return }
        Task { await reloadEntries() }
        startTracking()
    }

    /// Two loads may overlap when devices are switched quickly; the stale one is dropped.
    func reloadApps() async {
        guard let device = selectedDevice else {
            apps = []
            return
        }

        isLoadingApps = true
        defer { isLoadingApps = false }

        let loaded = await controller.apps(on: device)
        guard selectedDeviceID == device.id else { return }
        apps = loaded.apps
        warning = loaded.warning

        if apps.contains(where: { $0.id == selectedBundleID }) {
            await reloadEntries()
        } else {
            selectApp(apps.first?.id ?? "")
        }
    }

    func reloadEntries() async {
        await loadEntries(showingSpinner: true)
    }

    func beginEditing(_ entry: UserDefaultsEntry) {
        guard entry.value.isEditable else { return }
        editingKey = entry.key
        draft = entry.value.display
    }

    func cancelEditing() {
        editingKey = nil
    }

    /// Enter: an invalid number keeps the field open so the mistake can be fixed.
    func commitEditing() async {
        guard let entry = editingEntry, let value = entry.value.replacing(with: draft) else { return }

        editingKey = nil
        guard value != entry.value else { return }
        await set(entry, to: value)
    }

    /// Focus lost: what is valid is saved, the rest is dropped.
    func endEditing() async {
        if isDraftValid {
            await commitEditing()
        } else {
            cancelEditing()
        }
    }

    func set(_ entry: UserDefaultsEntry, to value: UserDefaultsValue) async {
        guard let device = selectedDevice, let app = selectedApp else { return }

        let outcome = await controller.write(value, forKey: entry.key, of: app, on: device)
        result = outcome
        if outcome.isSuccess {
            await reloadEntries()
        }
    }

    func delete(_ entry: UserDefaultsEntry) async {
        guard let device = selectedDevice, let app = selectedApp else { return }

        if editingKey == entry.key {
            editingKey = nil
        }
        let outcome = await controller.delete(key: entry.key, of: app, on: device)
        result = outcome
        if outcome.isSuccess {
            await reloadEntries()
        }
    }

    func reveal() {
        guard let app = selectedApp else { return }
        Task { await controller.reveal(app) }
    }

    /// The window can be closed while a poll is scheduled.
    func stopTracking() {
        tracking?.cancel()
        tracking = nil
    }

    /// One `defaults export` every two seconds: the table follows what the app writes.
    private func startTracking() {
        tracking?.cancel()
        tracking = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.trackingInterval)
                guard !Task.isCancelled, let self else { return }
                await self.loadEntries(showingSpinner: false)
            }
        }
    }

    /// A poll skips while another read is in flight; an explicit reload goes through,
    /// so an edit shows up at once.
    private func loadEntries(showingSpinner: Bool) async {
        guard let device = selectedDevice, let app = selectedApp else {
            entries = []
            return
        }
        guard showingSpinner || !isReadingEntries else { return }

        isReadingEntries = true
        if showingSpinner {
            isLoadingEntries = true
        }
        defer {
            isReadingEntries = false
            isLoadingEntries = false
        }

        let loaded = await controller.entries(of: app, on: device)
        guard selectedDeviceID == device.id, selectedBundleID == app.id else { return }
        entries = loaded.entries
        readError = loaded.error
    }
}
