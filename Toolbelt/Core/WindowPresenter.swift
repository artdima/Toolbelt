//
//  WindowPresenter.swift
//  Toolbelt
//
//  The single place that opens regular windows on top of a menu bar app.
//

import SwiftUI

struct WindowConfiguration {
    let id: String
    let title: String
    let size: NSSize
    var isResizable = true

    var autosaveName: NSWindow.FrameAutosaveName { "window.\(id)" }
}

@MainActor
enum WindowPresenter {
    private static var windows: [String: NSWindow] = [:]
    private static var closeObservers: [String: NSObjectProtocol] = [:]

    /// Opens a window, or raises the one already open.
    /// The menu bar panel is dismissed first: otherwise it hangs over the new window.
    static func show<Content: View>(
        _ configuration: WindowConfiguration,
        @ViewBuilder content: () -> Content
    ) {
        MenuBarPanel.dismiss()

        if let existing = windows[configuration.id] {
            existing.makeKeyAndOrderFront(nil)
            DockPresence.activate()
            return
        }

        DockPresence.retain()

        let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
        window.title = configuration.title
        window.styleMask = configuration.isResizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(configuration.size)

        window.setFrameAutosaveName(configuration.autosaveName)
        if !window.setFrameUsingName(configuration.autosaveName) {
            window.center()
        }

        windows[configuration.id] = window
        // Keeping the observer token matters: without removing it every open/close
        // cycle would leave a live registration pointing at a dead window.
        closeObservers[configuration.id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                forget(configuration.id)
            }
        }

        window.makeKeyAndOrderFront(nil)
        DockPresence.activate()
    }

    static func close(_ id: String) {
        windows[id]?.close()
    }

    private static func forget(_ id: String) {
        guard windows.removeValue(forKey: id) != nil else { return }
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        DockPresence.release()
    }
}
