//
//  DeepLinkHistoryStore.swift
//  Toolbelt
//

import Observation
import SwiftUI

@Observable
@MainActor
final class DeepLinkHistoryStore {
    static let shared = DeepLinkHistoryStore()

    private static let storageKey = "deeplink.history"
    static let unpinnedLimit = 20

    private let defaults: UserDefaults
    private(set) var entries: [DeepLinkEntry]

    /// `defaults` — шов для тестов.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    /// Закреплённые вверху, остальные — в порядке последнего использования.
    var sorted: [DeepLinkEntry] {
        entries.filter(\.isPinned) + entries.filter { !$0.isPinned }
    }

    func record(_ url: String) {
        var updated = entries
        if let index = updated.firstIndex(where: { $0.url == url }) {
            let existing = updated.remove(at: index)
            updated.insert(existing, at: 0)
        } else {
            updated.insert(DeepLinkEntry(url: url), at: 0)
        }

        // Лимит считается только по незакреплённым: звёздочка защищает от вытеснения.
        var unpinned = 0
        updated = updated.filter { entry in
            guard !entry.isPinned else { return true }
            unpinned += 1
            return unpinned <= Self.unpinnedLimit
        }

        apply(updated)
    }

    func togglePin(_ entry: DeepLinkEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entries
        updated[index].isPinned.toggle()
        apply(updated)
    }

    func remove(_ entry: DeepLinkEntry) {
        apply(entries.filter { $0.id != entry.id })
    }

    private func apply(_ newEntries: [DeepLinkEntry]) {
        entries = newEntries
        do {
            defaults.set(try JSONEncoder().encode(newEntries), forKey: Self.storageKey)
        } catch {
            Log.storage.error("Не удалось сохранить историю ссылок: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ data: Data?) -> [DeepLinkEntry] {
        guard let data else { return [] }
        do {
            return try JSONDecoder().decode([DeepLinkEntry].self, from: data)
        } catch {
            Log.storage.error("История ссылок повреждена: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
