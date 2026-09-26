//
//  JSONPretty.swift
//  Toolbelt
//

import Foundation

/// Re-indents JSON by walking its characters instead of decoding it:
/// `JSONSerialization` would lose the order of keys.
enum JSONPretty {
    static let indent = "  "

    /// nil when the text is not JSON.
    static func format(_ text: String) -> String? {
        let data = Data(text.utf8)
        guard !data.isEmpty,
              (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
        else { return nil }

        var output = ""
        var depth = 0
        var isInString = false
        var isEscaped = false
        var hasPendingBreak = false

        func lineBreak() {
            output.append("\n")
            output.append(String(repeating: indent, count: depth))
        }

        func flushBreak() {
            guard hasPendingBreak else { return }
            hasPendingBreak = false
            lineBreak()
        }

        for character in text {
            if isInString {
                output.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                continue
            }

            switch character {
            case "\"":
                flushBreak()
                output.append(character)
                isInString = true
            case "{", "[":
                flushBreak()
                output.append(character)
                depth += 1
                hasPendingBreak = true
            case "}", "]":
                depth -= 1
                if hasPendingBreak {
                    hasPendingBreak = false
                } else {
                    lineBreak()
                }
                output.append(character)
            case ",":
                output.append(character)
                hasPendingBreak = true
            case ":":
                output.append(": ")
            case _ where character.isWhitespace:
                break
            default:
                flushBreak()
                output.append(character)
            }
        }
        return output
    }
}
