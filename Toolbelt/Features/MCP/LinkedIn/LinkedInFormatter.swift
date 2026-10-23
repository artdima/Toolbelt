//
//  LinkedInFormatter.swift
//  Toolbelt
//
//  LinkedIn answers as compact text for the model, one line per thing, fields joined by “·”.
//

import Foundation

nonisolated struct LinkedInFormatter: Sendable {
    static let journalNote = "Only posts published through Toolbelt are listed: LinkedIn's API does not let Toolbelt read the member's own posts."

    let timeZone: TimeZone

    init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
    }

    // MARK: Accounts

    /// Secrets never get here: a resource carries none.
    func accounts(
        _ enabled: [MCPResource],
        withoutToken: Set<UUID> = [],
        disabledCount: Int,
        now: Date = Date()
    ) -> String {
        guard !enabled.isEmpty else { return "No LinkedIn account is turned on in Toolbelt." }

        var lines = ["LinkedIn accounts enabled in Toolbelt — \(enabled.count):"]
        for resource in enabled {
            var parts = [resource.name]
            if let account = resource.account {
                if let name = account.displayName { parts.append(name) }
                if !account.username.isEmpty { parts.append(account.username) }
                if let subject = account.subjectID { parts.append("urn:li:person:\(subject)") }
                if let scopes = account.scopes { parts.append("scopes: \(scopes.isEmpty ? "none" : scopes.joined(separator: ", "))") }
                if let expiry = expiry(account, now: now) { parts.append(expiry) }
            } else {
                parts.append("not checked yet")
            }
            parts.append(resource.allowWrite ? "writing allowed" : "read only")
            if withoutToken.contains(resource.id) { parts.append("no token in Keychain, unusable until it is added again") }
            lines.append(parts.joined(separator: " · "))
        }
        if disabledCount > 0 { lines.append("\(disabledCount) more turned off by the user.") }
        return lines.joined(separator: "\n")
    }

    // MARK: Profile

    func profile(_ info: LinkedInUserInfo) -> String {
        var lines = [info.displayName ?? "Name not shared"]
        if let email = info.email {
            let state = info.emailVerified.map { $0 ? " (verified)" : " (not verified)" } ?? ""
            lines.append("Email: \(email)\(state)")
        } else {
            lines.append("Email: not shared with the app")
        }
        if let locale = info.locale?.value, !locale.isEmpty { lines.append("Locale: \(locale)") }
        if let picture = info.picture { lines.append("Photo: \(picture)") }
        lines.append("Author URN: \(info.authorURN)")
        return lines.joined(separator: "\n")
    }

    // MARK: Posts

    func recentPosts(_ records: [LinkedInPostRecord], account: String, total: Int) -> String {
        guard !records.isEmpty else {
            return "Nothing has been published through Toolbelt as \(account) yet. \(Self.journalNote)"
        }
        var lines = ["Posts published through Toolbelt as \(account), newest first — \(records.count) of \(total):"]
        for record in records {
            lines.append([time(record.createdAt), record.visibility.audience, record.urn].joined(separator: " · "))
            lines.append("  \(record.url)")
            lines.append("  “\(Self.oneLine(record.excerpt))”")
        }
        lines.append(Self.journalNote)
        return lines.joined(separator: "\n")
    }

    func published(urn: String, author: String, visibility: LinkedInVisibility, at date: Date) -> String {
        [
            "Posted to LinkedIn as \(author) · \(visibility.audience) · \(time(date))",
            urn,
            LinkedInLink.postURL(urn)
        ].joined(separator: "\n")
    }

    func publishedWithoutURN(author: String, visibility: LinkedInVisibility, at date: Date) -> String {
        [
            "Posted to LinkedIn as \(author) · \(visibility.audience) · \(time(date))",
            "LinkedIn did not return the post's URN, so it is not in linkedin_recent_posts.",
            "Do not post it again: it is published. The member finds it on their profile under Activity."
        ].joined(separator: "\n")
    }

    func dryRun(text: String, escaped: String, author: String, authorURN: String, visibility: LinkedInVisibility) -> String {
        [
            "Dry run: nothing was published.",
            "Would post as \(author) (\(authorURN)) · \(visibility.audience) · \(text.count) of \(LittleText.maxLength) characters",
            "Text as LinkedIn will receive it, reserved characters escaped:",
            escaped,
            "",
            "Show the user this text and the visibility, and publish only after they agree."
        ].joined(separator: "\n")
    }

    func deleted(_ urn: String, account: String, wasInJournal: Bool, wasAlreadyGone: Bool = false) -> String {
        let head = wasAlreadyGone
            ? "\(urn) is already gone from LinkedIn (\(account))."
            : "Deleted \(urn) from LinkedIn (\(account))."
        let note = wasInJournal ? "" : " It was not in the list of posts published through Toolbelt."
        return head + note
    }

    // MARK: Values

    func time(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let offset = timeZone.secondsFromGMT(for: date) / 60
        let local = String(
            format: "%04ld-%02ld-%02ld %02ld:%02ld",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
        let zone = String(format: "%02ld:%02ld", abs(offset) / 60, abs(offset) % 60)
        return local + (offset < 0 ? "-" : "+") + zone
    }

    private func expiry(_ account: MCPAccount, now: Date) -> String? {
        guard case let .on(date) = account.expiry else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04ld-%02ld-%02ld", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return account.isExpired(now: now) ? "token expired \(day)" : "token expires \(day)"
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
