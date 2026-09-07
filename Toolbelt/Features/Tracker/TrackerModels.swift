//
//  TrackerModels.swift
//  Toolbelt
//

import Foundation

/// The organization kind decides which header the request carries:
/// `X-Org-ID` or `X-Cloud-Org-ID`.
enum TrackerOrgKind: String, CaseIterable, Identifiable, Codable {
    case yandex360
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yandex360: return "Yandex 360"
        case .cloud: return "Yandex Cloud"
        }
    }

    var headerName: String {
        switch self {
        case .yandex360: return "X-Org-ID"
        case .cloud: return "X-Cloud-Org-ID"
        }
    }
}

/// A logged time entry.
struct Worklog: Identifiable, Hashable {
    let id: Int
    let issueKey: String
    let issueTitle: String
    let comment: String?
    let start: Date
    let seconds: TimeInterval
}

/// An issue on the board.
struct Issue: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let summary: String
    let statusKey: String
    let statusName: String
    let priorityKey: String
    let priorityName: String
    let queueName: String
    let updatedAt: Date?
    let deadline: Date?

    var url: URL? { URL(string: "https://tracker.yandex.ru/\(key)") }

    func isOverdue(now: Date = Date(), calendar: Calendar = AppFormatters.calendar) -> Bool {
        guard let deadline else { return false }
        return deadline < calendar.startOfDay(for: now)
    }
}
