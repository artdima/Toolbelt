//
//  AppUpdater.swift
//  Toolbelt
//
//  Updates through Sparkle. Toolbelt never restarts by itself: a downloaded update
//  waits for Quit or for a click in the panel, since a restart drops Claude's MCP sessions.
//

import Foundation
import Observation
import Sparkle

@Observable
final class AppUpdater: NSObject {
    enum PendingUpdate {
        /// Found by a scheduled check while background downloads are off.
        case available(version: String)
        /// Downloaded; installs on Quit or from `installNow()`.
        case readyToInstall(version: String)
    }

    static let shared = AppUpdater()

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    private(set) var pendingUpdate: PendingUpdate?
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )
    @ObservationIgnored private var installUpdate: (() -> Void)?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private var holdsDockPresence = false

    private override init() {
        super.init()
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get {
            access(keyPath: \.automaticallyDownloadsUpdates)
            return controller.updater.automaticallyDownloadsUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyDownloadsUpdates) {
                controller.updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    func start() {
        controller.startUpdater()
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        MenuBarPanel.dismiss()
        if case .available = pendingUpdate {
            holdDockPresence()
        }
        controller.checkForUpdates(nil)
        DockPresence.activate()
    }

    func installNow() {
        installUpdate?()
    }

    /// Keeps the update window reachable with Cmd-Tab until Sparkle ends the session.
    private func holdDockPresence() {
        guard !holdsDockPresence else { return }
        holdsDockPresence = true
        DockPresence.retain()
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installUpdate = immediateInstallHandler
        pendingUpdate = .readyToInstall(version: item.displayVersionString)
        return true
    }
}

extension AppUpdater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// A scheduled update shows up as a row in the panel instead of a window over other apps.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            holdDockPresence()
        } else {
            pendingUpdate = .available(version: update.displayVersionString)
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        if case .available = pendingUpdate {
            pendingUpdate = nil
        }
        guard holdsDockPresence else { return }
        holdsDockPresence = false
        DockPresence.release()
    }
}
