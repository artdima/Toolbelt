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
    var toolbarStyle: NSWindow.ToolbarStyle?

    var autosaveName: NSWindow.FrameAutosaveName { "window.\(id)" }
}

@MainActor
enum WindowPresenter {
    private static var windows: [String: NSWindow] = [:]
    private static var closeObservers: [String: NSObjectProtocol] = [:]

    /// Opens a window, or raises the one already open.
    static func show<Content: View>(
        _ configuration: WindowConfiguration,
        @ViewBuilder content: () -> Content
    ) {
        show(configuration, controller: {
            let controller = NSHostingController(rootView: content())
            if configuration.toolbarStyle != nil {
                // A SwiftUI `.toolbar` and `.navigationSubtitle` reach an AppKit-made
                // window only through scene bridging.
                controller.sceneBridgingOptions = [.toolbars, .title]
            }
            return controller
        })
    }

    /// The menu bar panel is dismissed first: otherwise it hangs over the new window.
    /// `controller` is called only when the window is not open yet.
    static func show(
        _ configuration: WindowConfiguration,
        controller makeController: () -> NSViewController
    ) {
        MenuBarPanel.dismiss()

        if let existing = windows[configuration.id] {
            existing.makeKeyAndOrderFront(nil)
            DockPresence.activate()
            return
        }

        DockPresence.retain()

        let window = NSWindow(contentViewController: makeController())
        window.title = configuration.title
        window.styleMask = configuration.isResizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        if let toolbarStyle = configuration.toolbarStyle {
            window.toolbarStyle = toolbarStyle
        }
        window.setContentSize(configuration.size)

        window.setFrameAutosaveName(configuration.autosaveName)
        if !window.setFrameUsingName(configuration.autosaveName) {
            window.center()
        }
        if !configuration.isResizable {
            // A saved frame may come from an older layout; a fixed window keeps its design size.
            window.setContentSize(configuration.size)
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
