//
//  UserDefaultsParsing.swift
//  Toolbelt
//

import Foundation

/// Reads what `simctl listapps` and `defaults export` print. Pure functions, tested
/// against captured output.
enum UserDefaultsParsing {
    /// `listapps` prints an old-style plist keyed by bundle id; only apps installed by
    /// the developer are of interest, not Safari and Settings.
    static func installedApps(fromListappsOutput data: Data) -> [InstalledApp] {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let apps = object as? [String: [String: Any]]
        else { return [] }

        return apps
            .filter { ($0.value["ApplicationType"] as? String) == "User" }
            .map { bundleID, info in
                InstalledApp(
                    bundleID: bundleID,
                    name: (info["CFBundleDisplayName"] as? String)
                        ?? (info["CFBundleName"] as? String)
                        ?? bundleID,
                    dataContainer: (info["DataContainer"] as? String).flatMap { URL(string: $0)?.path }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The XML plist of one defaults domain; nil when the data is not a plist dictionary.
    static func entries(fromPlist data: Data) -> [UserDefaultsEntry]? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = object as? [String: Any]
        else { return nil }

        return dictionary
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { UserDefaultsEntry(key: $0.key, value: value($0.value)) }
    }

    /// A plist number is one NSNumber whatever it holds: booleans and floats are told
    /// apart through CoreFoundation, since `1 as? Bool` succeeds as well.
    static func value(_ object: Any) -> UserDefaultsValue {
        switch object {
        case let text as String:
            return .string(text)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            if CFNumberIsFloatType(number as CFNumber) { return .double(number.doubleValue) }
            return .integer(number.intValue)
        case let date as Date:
            return .date(date)
        case let data as Data:
            return .data(bytes: data.count)
        case let array as [Any]:
            return .array(describe(array), count: array.count)
        case let dictionary as [String: Any]:
            return .dictionary(describe(dictionary), count: dictionary.count)
        default:
            return .string(String(describing: object))
        }
    }

    /// One line, JSON-like, for a collection cell.
    static func describe(_ object: Any) -> String {
        switch object {
        case let text as String:
            return "\"\(text)\""
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case let date as Date:
            return UserDefaultsValue.date(date).display
        case let data as Data:
            return "<\(data.count) bytes>"
        case let array as [Any]:
            return "[" + array.map(describe).joined(separator: ", ") + "]"
        case let dictionary as [String: Any]:
            let pairs = dictionary
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \(describe($0.value))" }
            return "{" + pairs.joined(separator: ", ") + "}"
        default:
            return String(describing: object)
        }
    }
}
