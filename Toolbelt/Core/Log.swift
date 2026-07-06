//
//  Log.swift
//  Toolbelt
//

import OSLog

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.dima.Toolbelt"

    static let tracker = Logger(subsystem: subsystem, category: "tracker")
    static let shell = Logger(subsystem: subsystem, category: "shell")
    static let storage = Logger(subsystem: subsystem, category: "storage")
}
