//
//  MenuBarPanel.swift
//  GitSwitcher
//
//  Панель MenuBarExtra (меню в строке состояния) висит на уровне статус-бара
//  и не закрывается сама, когда мы открываем обычное окно поверх неё.
//  Публичного API для её закрытия SwiftUI не даёт, поэтому запоминаем NSWindow,
//  в котором живёт содержимое меню, и закрываем его вручную.
//

import SwiftUI

enum MenuBarPanel {
    /// Окно панели. Слабая ссылка: SwiftUI пересоздаёт панель при каждом открытии.
    private static weak var panelWindow: NSWindow?

    /// Запоминает окно, в котором отрисовано содержимое меню.
    /// Вызывается из `MenuBarPanelReader`, а он живёт только внутри панели,
    /// поэтому проверять окно дополнительно не нужно.
    static func register(_ window: NSWindow?) {
        guard let window else { return }
        panelWindow = window
    }

    /// Закрывает меню в строке состояния. Вызывать перед открытием обычного окна.
    static func dismiss() {
        if let panelWindow, panelWindow.isVisible {
            panelWindow.close()
            return
        }

        // Запасной путь: активное окно без строки заголовка — это и есть панель меню.
        // Обычные окна приложения помечены `.titled`, поэтому их не трогаем.
        if let key = NSApp.keyWindow, !key.styleMask.contains(.titled) {
            key.close()
        }
    }
}

/// Невидимая подложка: сообщает `MenuBarPanel`, в каком окне живёт SwiftUI-вью.
struct MenuBarPanelReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // На момент создания вью ещё не добавлено в окно — читаем следующим циклом.
        DispatchQueue.main.async {
            MenuBarPanel.register(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        MenuBarPanel.register(nsView.window)
    }
}
