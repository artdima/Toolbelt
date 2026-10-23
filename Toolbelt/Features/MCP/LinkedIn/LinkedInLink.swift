//
//  LinkedInLink.swift
//  Toolbelt
//
//  Reading a post's URN out of what the model passes: the URN itself or a LinkedIn link.
//

import Foundation

nonisolated enum LinkedInPostReference: Equatable, Sendable {
    /// `urn:li:share:…` or `urn:li:ugcPost:…`: what the Posts API takes.
    case post(String)
    /// The id of `activity-<id>` or `urn:li:activity:<id>`, which the Posts API does not take.
    case activity(String)
}

nonisolated enum LinkedInLink {
    static func postURL(_ urn: String) -> String {
        "https://www.linkedin.com/feed/update/\(urn)/"
    }

    static func parse(_ value: String) -> LinkedInPostReference? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reference = urn(trimmed) { return reference }

        let link = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: link),
              let host = url.host(percentEncoded: false)?.lowercased(),
              host == "linkedin.com" || host.hasSuffix(".linkedin.com")
        else { return nil }

        let path = url.path(percentEncoded: false)
        let segments = path.split(separator: "/").map(String.init)
        if let index = segments.firstIndex(of: "update"), index > 0, segments[index - 1] == "feed",
           index + 1 < segments.count {
            return urn(segments[index + 1])
        }
        return activityID(in: path).map(LinkedInPostReference.activity)
    }

    private static func urn(_ value: String) -> LinkedInPostReference? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4,
              parts[0].lowercased() == "urn",
              parts[1].lowercased() == "li",
              !parts[3].isEmpty,
              parts[3].allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }

        switch parts[2].lowercased() {
        case "share": return .post("urn:li:share:\(parts[3])")
        case "ugcpost": return .post("urn:li:ugcPost:\(parts[3])")
        case "activity": return .activity(parts[3])
        default: return nil
        }
    }

    /// Links copied from a post look like /posts/name_slug-activity-7123456789-AbCd.
    private static func activityID(in path: String) -> String? {
        guard let range = path.range(of: "activity-") else { return nil }
        let digits = path[range.upperBound...].prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }
}
