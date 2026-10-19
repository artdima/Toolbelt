//
//  MCPText.swift
//  Toolbelt
//
//  Shaping tool responses: the size limit and secrets kept out of the text.
//

import Foundation

nonisolated enum MCPText {
    static let responseLimit = 20_000

    enum Keep {
        case head
        case tail
    }

    /// The result, marker included, never exceeds `limit` characters. The cut lands on a line
    /// boundary when one is close, so the model never sees half a line.
    static func limited(_ text: String, limit: Int = responseLimit, keep: Keep = .head) -> String {
        guard text.count > limit else { return text }

        let total = text.count
        let budget = max(0, limit - 160)
        switch keep {
        case .head:
            var kept = String(text.prefix(budget))
            if let newline = kept.lastIndex(of: "\n"), kept.distance(from: newline, to: kept.endIndex) < 600 {
                kept = String(kept[..<newline])
            }
            let cut = total - kept.count
            return kept + "\n\n[Truncated: \(cut) of \(total) characters cut to stay within \(limit). Narrow the request to see the rest.]"
        case .tail:
            var kept = String(text.suffix(budget))
            if let newline = kept.firstIndex(of: "\n"), kept.distance(from: kept.startIndex, to: newline) < 600 {
                kept = String(kept[kept.index(after: newline)...])
            }
            let cut = total - kept.count
            return "[Truncated: the first \(cut) of \(total) characters were cut to stay within \(limit).]\n\n" + kept
        }
    }

    /// Short strings are skipped: replacing them would mangle ordinary words.
    static func redacting(_ secrets: [String], in text: String) -> String {
        secrets
            .filter { $0.count >= 8 }
            .reduce(text) { $0.replacingOccurrences(of: $1, with: "[redacted]") }
    }

    static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit - 1))) + "…"
    }
}
