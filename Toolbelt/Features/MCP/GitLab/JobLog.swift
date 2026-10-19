//
//  JobLog.swift
//  Toolbelt
//
//  A job trace as a terminal would show it: no escape codes, no section markers,
//  progress lines collapsed to their final state.
//

import Foundation

nonisolated enum JobLogError: LocalizedError, Equatable {
    case invalidPattern(String)

    var errorDescription: String? {
        switch self {
        case let .invalidPattern(pattern):
            return "“\(pattern)” is not a valid regular expression"
        }
    }
}

nonisolated enum JobLog {
    static let defaultTail = 200
    static let maxTail = 2000
    static let defaultContext = 3
    static let maxContext = 50

    private static let sectionMarker = try? NSRegularExpression(
        pattern: #"section_(?:start|end):[0-9]+:[A-Za-z0-9_.\-]+(?:\[[^\]]*\])?"#
    )

    private enum ScanState {
        case text
        case escape
        case controlSequence
        case operatingSystemCommand
        case operatingSystemCommandEscape
    }

    static func cleanLines(_ raw: String) -> [String] {
        var lines: [String] = []
        var segment = String.UnicodeScalarView()
        var previousSegment = String.UnicodeScalarView()
        var state = ScanState.text

        func finishLine() {
            let visible = segment.isEmpty ? previousSegment : segment
            segment = String.UnicodeScalarView()
            previousSegment = String.UnicodeScalarView()

            var line = String(visible)
            if line.contains("section_") {
                let stripped = removingSectionMarkers(line)
                if stripped.allSatisfy(\.isWhitespace) { return }
                line = stripped
            }
            lines.append(line)
        }

        for scalar in raw.unicodeScalars {
            if scalar == "\n" {
                finishLine()
                state = .text
                continue
            }

            switch state {
            case .text:
                switch scalar {
                case "\u{1B}":
                    state = .escape
                case "\r":
                    if !segment.isEmpty { previousSegment = segment }
                    segment = String.UnicodeScalarView()
                default:
                    segment.append(scalar)
                }
            case .escape:
                switch scalar {
                case "[": state = .controlSequence
                case "]": state = .operatingSystemCommand
                default: state = .text
                }
            case .controlSequence:
                if (0x40...0x7E).contains(scalar.value) { state = .text }
            case .operatingSystemCommand:
                if scalar == "\u{07}" {
                    state = .text
                } else if scalar == "\u{1B}" {
                    state = .operatingSystemCommandEscape
                }
            case .operatingSystemCommandEscape:
                state = .text
            }
        }
        if !segment.isEmpty || !previousSegment.isEmpty { finishLine() }

        while let last = lines.last, last.allSatisfy(\.isWhitespace) {
            lines.removeLast()
        }
        return lines
    }

    static func tail(_ lines: [String], count: Int) -> (header: String, body: String) {
        let wanted = min(max(count, 1), maxTail)
        let start = max(0, lines.count - wanted)
        let header = start == 0
            ? "All \(lines.count) lines of the log:"
            : "Lines \(start + 1)–\(lines.count) of \(lines.count):"
        return (header, lines[start...].joined(separator: "\n"))
    }

    /// grep -n style: "123:" marks a match, "122-" a line of context, "--" a gap.
    static func grep(_ lines: [String], pattern: String, context: Int) throws -> (header: String, body: String) {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            throw JobLogError.invalidPattern(pattern)
        }

        let context = min(max(context, 0), maxContext)
        var matches: [Int] = []
        for (index, line) in lines.enumerated()
        where regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
            matches.append(index)
        }

        guard !matches.isEmpty else {
            return ("No line of \(lines.count) matches /\(pattern)/.", "")
        }

        let matched = Set(matches)
        let width = String(lines.count).count
        var output: [String] = []
        var lastPrinted = -1

        for index in matches {
            let from = max(index - context, lastPrinted + 1)
            let to = min(index + context, lines.count - 1)
            guard from <= to else { continue }
            if lastPrinted >= 0, from > lastPrinted + 1 { output.append("--") }
            for line in from...to {
                let number = String(line + 1)
                let padded = String(repeating: " ", count: max(0, width - number.count)) + number
                output.append(padded + (matched.contains(line) ? ":" : "-") + lines[line])
            }
            lastPrinted = to
        }

        let noun = matches.count == 1 ? "line matches" : "lines match"
        let header = "\(matches.count) of \(lines.count) \(noun) /\(pattern)/, with \(context) lines of context:"
        return (header, output.joined(separator: "\n"))
    }

    private static func removingSectionMarkers(_ line: String) -> String {
        guard let sectionMarker else { return line }
        let range = NSRange(line.startIndex..., in: line)
        return sectionMarker.stringByReplacingMatches(in: line, range: range, withTemplate: "")
    }
}
