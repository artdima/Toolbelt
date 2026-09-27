//
//  UserDefaultsModels.swift
//  Toolbelt
//

import Foundation

/// An app the developer installed on a simulator, the way `simctl listapps` reports it.
struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    /// The data container on disk; nil when simctl did not report one.
    let dataContainer: String?

    var id: String { bundleID }

    var title: String { name == bundleID ? bundleID : "\(name) · \(bundleID)" }

    /// Where cfprefsd keeps the app's standard defaults.
    var preferencesPlistPath: String? {
        dataContainer.map { "\($0)/Library/Preferences/\(bundleID).plist" }
    }
}

enum UserDefaultsValue: Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(bytes: Int)
    /// Collections are shown, not edited: the text is what the table displays.
    case array(String, count: Int)
    case dictionary(String, count: Int)

    private static let dates = ISO8601DateFormatter()

    var typeName: String {
        switch self {
        case .string: return "String"
        case .integer: return "Int"
        case .double: return "Double"
        case .bool: return "Bool"
        case .date: return "Date"
        case .data: return "Data"
        case let .array(_, count): return "Array · \(count)"
        case let .dictionary(_, count): return "Dictionary · \(count)"
        }
    }

    /// The text in the table, and the starting point of an edit.
    var display: String {
        switch self {
        case let .string(value): return value
        case let .integer(value): return String(value)
        case let .double(value): return String(value)
        case let .bool(value): return value ? "true" : "false"
        case let .date(value): return Self.dates.string(from: value)
        case let .data(bytes): return "\(bytes) bytes"
        case let .array(text, _), let .dictionary(text, _): return text
        }
    }

    /// Strings, numbers and booleans go back through `defaults write`; the rest is read-only.
    var isEditable: Bool {
        writeArguments != nil
    }

    /// The typed form `defaults write` takes.
    var writeArguments: [String]? {
        switch self {
        case let .string(value): return ["-string", value]
        case let .integer(value): return ["-int", String(value)]
        case let .double(value): return ["-float", String(value)]
        case let .bool(value): return ["-bool", value ? "true" : "false"]
        case .date, .data, .array, .dictionary: return nil
        }
    }

    /// The same type with the text the user typed; nil when the text is not that type.
    func replacing(with text: String) -> UserDefaultsValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .string:
            return .string(text)
        case .integer:
            return Int(trimmed).map(UserDefaultsValue.integer)
        case .double:
            return Double(trimmed).map(UserDefaultsValue.double)
        case .bool:
            switch trimmed.lowercased() {
            case "true", "yes", "1": return .bool(true)
            case "false", "no", "0": return .bool(false)
            default: return nil
            }
        case .date, .data, .array, .dictionary:
            return nil
        }
    }
}

struct UserDefaultsEntry: Identifiable, Equatable {
    let key: String
    let value: UserDefaultsValue

    var id: String { key }
}

struct UserDefaultsActionResult: Equatable {
    let command: String
    let output: String
    let isSuccess: Bool
}
