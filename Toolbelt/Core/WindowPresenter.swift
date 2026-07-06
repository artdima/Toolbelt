//
//  WindowPresenter.swift
//  Toolbelt
//
//  Единая точка открытия обычных окон поверх приложения из строки меню.
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

    /// Открывает окно или поднимает уже открытое.
    /// Панель в строке меню закрывается: иначе она висит поверх нового окна.
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
        // Токен наблюдателя обязателен: без снятия каждый цикл «открыл — закрыл»
        // оставлял бы в NotificationCenter живую регистрацию на мёртвое окно.
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
