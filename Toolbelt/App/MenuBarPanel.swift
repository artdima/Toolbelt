//
//  MenuBarPanel.swift
//  Toolbelt
//
//  The MenuBarExtra panel sits at status bar level and does not close itself when
//  a regular window opens on top of it. SwiftUI exposes no API to dismiss it, so we
//  remember the NSWindow that hosts the menu content and close it by hand.
//

import SwiftUI

enum MenuBarPanel {
    /// The panel window. Weak, because SwiftUI recreates the panel on every open.
    private static weak var panelWindow: NSWindow?

    /// Remembers the window that hosts the menu content. Called from
    /// `MenuBarPanelReader`, which only ever lives inside the panel, so no extra
    /// checks on the window are needed.
    static func register(_ window: NSWindow?) {
        guard let window else { return }
        panelWindow = window
    }

    /// Closes the menu bar panel. Call before opening a regular window.
    static func dismiss() {
        if let panelWindow, panelWindow.isVisible {
            panelWindow.close()
            return
        }

        // Fallback: a key window without a title bar is the menu panel.
        // Every regular window of the app is `.titled`, so those are left alone.
        if let key = NSApp.keyWindow, !key.styleMask.contains(.titled) {
            key.close()
        }
    }
}

/// An invisible backing view that tells `MenuBarPanel` which window hosts the content.
struct MenuBarPanelReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The view is not in a window yet at creation time — read it next cycle.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                MenuBarPanel.register(view.window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        MenuBarPanel.register(nsView.window)
    }
}
