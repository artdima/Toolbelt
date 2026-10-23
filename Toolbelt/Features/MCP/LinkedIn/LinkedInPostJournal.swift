//
//  LinkedInPostJournal.swift
//  Toolbelt
//
//  Posts published through Toolbelt. LinkedIn's API does not let a member's app read the
//  member's own posts, so this is the only way Claude can refer to them later.
//

import Foundation

nonisolated struct LinkedInPostRecord: Codable, Equatable, Sendable {
    static let excerptLength = 200

    let urn: String
    let createdAt: Date
    let visibility: LinkedInVisibility
    let excerpt: String

    init(urn: String, createdAt: Date, visibility: LinkedInVisibility, text: String) {
        self.urn = urn
        self.createdAt = createdAt
        self.visibility = visibility
        excerpt = MCPText.truncated(text, to: Self.excerptLength)
    }

    var url: String { LinkedInLink.postURL(urn) }
}

/// The provider runs off the main actor, and several clients can publish at once.
nonisolated final class LinkedInPostJournal: @unchecked Sendable {
    static let shared = LinkedInPostJournal(defaults: .standard)
    static let recordLimit = 100

    private let defaults: UserDefaults
    private let lock = Locked(())

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func recordsKey(for resource: UUID) -> String {
        "mcp.linkedin.posts.\(resource.uuidString)"
    }

    /// Publications are counted apart from the records: deleting a post must not free up the daily limit.
    static func publishedKey(for resource: UUID) -> String {
        "mcp.linkedin.published.\(resource.uuidString)"
    }

    static func erase(_ resource: UUID, in defaults: UserDefaults) {
        defaults.removeObject(forKey: recordsKey(for: resource))
        defaults.removeObject(forKey: publishedKey(for: resource))
    }

    /// Newest first.
    func records(for resource: UUID) -> [LinkedInPostRecord] {
        lock.withLock { _ in load(resource) }
    }

    func add(_ record: LinkedInPostRecord, for resource: UUID) {
        lock.withLock { _ in
            var records = load(resource)
            records.removeAll { $0.urn == record.urn }
            records.insert(record, at: 0)
            if records.count > Self.recordLimit {
                records.removeLast(records.count - Self.recordLimit)
            }
            save(records, resource)
        }
    }

    /// Counted before the request in one step with the check, so parallel calls cannot
    /// all slip under the limit.
    func reservePublication(for resource: UUID, limit: Int, at date: Date) throws {
        let isAllowed = lock.withLock { _ -> Bool in
            let dayAgo = date.addingTimeInterval(-86_400)
            let recent = loadPublished(resource).filter { $0 > dayAgo }
            guard recent.count < limit else { return false }
            savePublished(recent + [date], resource)
            return true
        }
        if !isAllowed {
            throw LinkedInAccessError.dailyLimit(limit)
        }
    }

    /// For a request LinkedIn turned down: that post does not exist.
    func cancelPublication(at date: Date, for resource: UUID) {
        lock.withLock { _ in
            var published = loadPublished(resource)
            if let index = published.firstIndex(where: { abs($0.timeIntervalSince(date)) < 0.001 }) {
                published.remove(at: index)
                savePublished(published, resource)
            }
        }
    }

    @discardableResult
    func remove(urn: String, for resource: UUID) -> Bool {
        lock.withLock { _ in
            var records = load(resource)
            let count = records.count
            records.removeAll { $0.urn == urn }
            guard records.count != count else { return false }
            save(records, resource)
            return true
        }
    }

    func publishedInLastDay(for resource: UUID, now: Date = Date()) -> Int {
        lock.withLock { _ in
            let dayAgo = now.addingTimeInterval(-86_400)
            return loadPublished(resource).filter { $0 > dayAgo }.count
        }
    }

    private func load(_ resource: UUID) -> [LinkedInPostRecord] {
        guard let data = defaults.data(forKey: Self.recordsKey(for: resource)) else { return [] }
        return (try? JSONDecoder().decode([LinkedInPostRecord].self, from: data)) ?? []
    }

    private func save(_ records: [LinkedInPostRecord], _ resource: UUID) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.recordsKey(for: resource))
    }

    private func loadPublished(_ resource: UUID) -> [Date] {
        let stamps = defaults.array(forKey: Self.publishedKey(for: resource)) as? [Double] ?? []
        return stamps.map(Date.init(timeIntervalSince1970:))
    }

    private func savePublished(_ dates: [Date], _ resource: UUID) {
        defaults.set(dates.map(\.timeIntervalSince1970), forKey: Self.publishedKey(for: resource))
    }
}
