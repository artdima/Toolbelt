//
//  SettingsWindow.swift
//  Toolbelt
//
//  The settings window: sections switched from the toolbar, the way macOS
//  settings windows do it.
//

import SwiftUI

enum SettingsTab: String, Hashable {
    case profiles
    case tracker
    case tools
}

final class SettingsTabViewController: NSTabViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar

        addPane(.profiles, title: "Git Profiles", systemImage: "person.2") {
            GitProfilesSettingsView()
        }
        addPane(.tracker, title: "Yandex Tracker", systemImage: "checklist") {
            TrackerSettingsView()
        }
        addPane(.tools, title: "Tools", systemImage: "screwdriver") {
            ToolsSettingsView()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(_ tab: SettingsTab) {
        if let index = tabViewItems.firstIndex(where: { $0.identifier as? String == tab.rawValue }) {
            selectedTabViewItemIndex = index
        }
        updateWindowTitle()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return }
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }

    private func addPane<Content: View>(
        _ tab: SettingsTab,
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        let controller = NSHostingController(rootView: content())
        controller.title = title

        let item = NSTabViewItem(viewController: controller)
        item.identifier = tab.rawValue
        item.label = title
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        addTabViewItem(item)
    }
}
