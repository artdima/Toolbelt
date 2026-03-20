//
//  DockPresence.swift
//  Toolbelt
//
//  Приложение помечено LSUIElement и обычно живёт только в строке меню.
//  Пока открыто хотя бы одно обычное окно, временно переводим его в .regular,
//  чтобы иконка появилась в доке и на окно можно было переключиться.
//

import SwiftUI

enum DockPresence {
    private static var openWindows = 0

    /// Вызывать при открытии окна — до `makeKeyAndOrderFront`.
    static func retain() {
        openWindows += 1
        guard openWindows == 1 else { return }
        NSApp.setActivationPolicy(.regular)
    }

    /// Вызывать при закрытии окна.
    static func release() {
        openWindows = max(0, openWindows - 1)
        guard openWindows == 0 else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Смена политики применяется не мгновенно, поэтому активируем следующим циклом.
    static func activate() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
