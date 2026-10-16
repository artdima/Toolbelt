//
//  HTTPRequestHistoryStore.swift
//  Toolbelt
//

import Observation
import OSLog
import SwiftUI

@Observable
@MainActor
final class HTTPRequestHistoryStore {
    static let shared = HTTPRequestHistoryStore()

    private static let storageKey = "httpRequest.history"
    static let unpinnedLimit = 20

    private let defaults: UserDefaults
    private(set) var entries: [HTTPRequestEntry]

    /// `defaults` is the seam for tests.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = Self.decode(defaults.data(forKey: Self.storageKey))
    }

    /// Pinned entries first, the rest in most-recently-used order.
    var sorted: [HTTPRequestEntry] {
        entries.filter(\.isPinned) + entries.filter { !$0.isPinned }
    }

    /// Returns the id of the entry, new or moved to the top, so the sidebar can select it.
    @discardableResult
    func record(_ draft: HTTPRequestDraft) -> HTTPRequestEntry.ID {
        var updated = entries
        var entry = HTTPRequestEntry(draft: draft)
        if let index = updated.firstIndex(where: { $0.draft == draft }) {
            entry = updated.remove(at: index)
        }
        updated.insert(entry, at: 0)

        // The limit counts unpinned entries only: a star protects from eviction.
        var unpinned = 0
        updated = updated.filter { entry in
            guard !entry.isPinned else { return true }
            unpinned += 1
            return unpinned <= Self.unpinnedLimit
        }

        apply(updated)
        return entry.id
    }

    func togglePin(_ entry: HTTPRequestEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entries
        updated[index].isPinned.toggle()
        apply(updated)
    }

    func remove(_ entry: HTTPRequestEntry) {
        apply(entries.filter { $0.id != entry.id })
    }

    /// Pinned requests stay: pinning is how a request is kept on purpose.
    func clearUnpinned() {
        apply(entries.filter(\.isPinned))
    }

    var hasUnpinned: Bool {
        entries.contains { !$0.isPinned }
    }

    private func apply(_ newEntries: [HTTPRequestEntry]) {
        entries = newEntries
        do {
            defaults.set(try JSONEncoder().encode(newEntries), forKey: Self.storageKey)
        } catch {
            Log.storage.error("Could not save request history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func decode(_ data: Data?) -> [HTTPRequestEntry] {
        guard let data else { return [] }
        do {
            return try JSONDecoder().decode([HTTPRequestEntry].self, from: data)
        } catch {
            Log.storage.error("Request history is corrupted: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
