//
//  DeepLinkHistoryStore.swift
//  Toolbelt
//

import Observation
import OSLog
import SwiftUI

@Observable
@MainActor
final class DeepLinkHistoryStore {
    static let shared = DeepLinkHistoryStore()

    private static let storageKey = "deeplink.history"
    static let unpinnedLimit = 20

    private let defaults: UserDefaults
    private(set) var entries: [DeepLinkEntry]

    /// `defaults` is the seam for tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    /// Pinned entries first, the rest in most-recently-used order.
    var sorted: [DeepLinkEntry] {
        entries.filter(\.isPinned) + entries.filter { !$0.isPinned }
    }

    func record(_ url: String, on deviceName: String, at date: Date = Date()) {
        var updated = entries
        var entry = DeepLinkEntry(url: url)
        if let index = updated.firstIndex(where: { $0.url == url }) {
            entry = updated.remove(at: index)
        }
        entry.deviceName = deviceName
        entry.openedAt = date
        updated.insert(entry, at: 0)

        // The limit counts unpinned entries only: a star protects from eviction.
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

    /// Pinned links stay: pinning is how a link is kept on purpose.
    func clearUnpinned() {
        apply(entries.filter(\.isPinned))
    }

    var hasUnpinned: Bool {
        entries.contains { !$0.isPinned }
    }

    private func apply(_ newEntries: [DeepLinkEntry]) {
        entries = newEntries
        do {
            defaults.set(try JSONEncoder().encode(newEntries), forKey: Self.storageKey)
        } catch {
            Log.storage.error("Could not save link history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ data: Data?) -> [DeepLinkEntry] {
        guard let data else { return [] }
        do {
            return try JSONDecoder().decode([DeepLinkEntry].self, from: data)
        } catch {
            Log.storage.error("Link history is corrupted: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
