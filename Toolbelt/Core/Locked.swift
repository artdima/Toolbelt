//
//  Locked.swift
//  Toolbelt
//

import Foundation

/// A mutex-guarded value, used to hand data between GCD threads inside `Shell`.
nonisolated final class Locked<Value>: @unchecked Sendable {
    private let mutex = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        mutex.lock()
        defer { mutex.unlock() }
        return body(&value)
    }
}
