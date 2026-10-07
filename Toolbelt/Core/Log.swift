//
//  Log.swift
//  Toolbelt
//

import Foundation
import OSLog

nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.artdima.Toolbelt"

    static let tracker = Logger(subsystem: subsystem, category: "tracker")
    static let shell = Logger(subsystem: subsystem, category: "shell")
    static let storage = Logger(subsystem: subsystem, category: "storage")
    static let http = Logger(subsystem: subsystem, category: "http")
}
