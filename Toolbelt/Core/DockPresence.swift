//
//  DockPresence.swift
//  Toolbelt
//
//  The app is marked LSUIElement and normally lives only in the menu bar.
//  While at least one regular window is open it temporarily switches to .regular
//  so the icon shows up in the Dock and the window can be reached with Cmd-Tab.
//

import SwiftUI

enum DockPresence {
    private static var openWindows = 0

    /// Call when opening a window, before `makeKeyAndOrderFront`.
    static func retain() {
        openWindows += 1
        guard openWindows == 1 else { return }
        NSApp.setActivationPolicy(.regular)
    }

    /// Call when a window closes.
    static func release() {
        assert(openWindows > 0, "release() without a matching retain()")
        openWindows = max(0, openWindows - 1)
        guard openWindows == 0 else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// The policy change does not apply immediately, so activate on the next cycle.
    static func activate() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
