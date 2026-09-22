//
//  SimulatorsViewModel.swift
//  Toolbelt
//

import Observation
import SwiftUI

@Observable
@MainActor
final class SimulatorsViewModel {
    private static let trackingAttempts = 45
    private static let trackingInterval: Duration = .seconds(2)

    private let controller: SimulatorControlling

    var search = ""

    private(set) var devices: [SimulatorDevice] = []
    private(set) var warning: String?
    private(set) var result: SimulatorActionResult?
    private(set) var isLoading = false
    private(set) var busyIDs: Set<SimulatorDevice.ID> = []

    /// A freshly launched emulator stays invisible to adb for a while, and the row would
    /// fall back to Shutdown on the next poll.
    private var pendingBoot: Set<SimulatorDevice.ID> = []
    private var tracking: Task<Void, Never>?

    convenience init() {
        self.init(controller: SimulatorRunner())
    }

    init(controller: SimulatorControlling) {
        self.controller = controller
    }

    var iosDevices: [SimulatorDevice] { visible(.ios) }
    var androidDevices: [SimulatorDevice] { visible(.android) }
    var hasVisibleDevices: Bool { !iosDevices.isEmpty || !androidDevices.isEmpty }

    func isBusy(_ device: SimulatorDevice) -> Bool {
        busyIDs.contains(device.id)
    }

    func canStop(_ device: SimulatorDevice) -> Bool {
        switch device.platform {
        case .ios: return device.state != .shutdown
        case .android: return device.serial != nil
        }
    }

    func reload() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        let loaded = await controller.devices()
        warning = loaded.warning
        devices = loaded.devices.map(applyingPendingBoot)
        forgetSettledBoots()
    }

    func boot(_ device: SimulatorDevice) async {
        guard !isBusy(device) else { return }

        busyIDs.insert(device.id)
        let outcome = await controller.boot(device)
        busyIDs.remove(device.id)
        result = outcome

        guard outcome.isSuccess else { return }
        pendingBoot.insert(device.id)
        markBooting(device.id)
        startTracking(device.id)
    }

    func shutdown(_ device: SimulatorDevice) async {
        guard !isBusy(device) else { return }

        busyIDs.insert(device.id)
        let outcome = await controller.shutdown(device)
        busyIDs.remove(device.id)
        result = outcome

        guard outcome.isSuccess else { return }
        stopTracking()
        pendingBoot.remove(device.id)
        await refreshStates()
    }

    /// The window can be closed long before a device finishes booting.
    func stopTracking() {
        tracking?.cancel()
        tracking = nil
    }

    private func startTracking(_ id: SimulatorDevice.ID) {
        tracking?.cancel()
        tracking = Task { [weak self] in
            for _ in 0 ..< Self.trackingAttempts {
                try? await Task.sleep(for: Self.trackingInterval)
                guard !Task.isCancelled, let self else { return }

                await self.refreshStates()
                if self.devices.first(where: { $0.id == id })?.state == .booted { return }
            }
            self?.pendingBoot.remove(id)
        }
    }

    /// Polling asks only for what changes while a device boots. Re-enumerating the SDK
    /// every two seconds would mean spawning simctl, the emulator and adb each time.
    private func refreshStates() async {
        guard !isLoading else { return }

        let statuses = await controller.statuses()
        devices = devices.map { device in
            var updated = device
            let status = statuses[device.id]
            updated.state = status?.state ?? .shutdown
            updated.serial = status?.serial
            return applyingPendingBoot(updated)
        }
        forgetSettledBoots()
    }

    private func forgetSettledBoots() {
        pendingBoot.subtract(devices.filter { $0.state == .booted }.map(\.id))
    }

    private func markBooting(_ id: SimulatorDevice.ID) {
        guard let index = devices.firstIndex(where: { $0.id == id }),
              devices[index].state == .shutdown
        else { return }
        devices[index].state = .booting
    }

    private func applyingPendingBoot(_ device: SimulatorDevice) -> SimulatorDevice {
        guard pendingBoot.contains(device.id), device.state == .shutdown else { return device }

        var booting = device
        booting.state = .booting
        return booting
    }

    private func visible(_ platform: MobilePlatform) -> [SimulatorDevice] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return devices.filter { device in
            guard device.platform == platform else { return false }
            guard !query.isEmpty else { return true }
            return device.name.lowercased().contains(query)
                || device.detail.lowercased().contains(query)
        }
    }
}
