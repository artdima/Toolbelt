//
//  LittleText.swift
//  Toolbelt
//
//  Post text in LinkedIn's Little Text format: taken literally, except for hashtags.
//

import Foundation

nonisolated enum LittleText {
    static let maxLength = 3_000

    /// Unescaped, these turn into mentions, hashtags or templates, or make LinkedIn reject the post.
    static let reserved: Set<Character> = ["|", "{", "}", "@", "[", "]", "(", ")", "<", ">", "#", "\\", "*", "_", "~"]

    /// `#word` stays a hashtag; every other reserved character, a lone `#` included, gets a backslash.
    static func escape(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        result.reserveCapacity(characters.count)
        for (index, character) in characters.enumerated() {
            if reserved.contains(character), !(character == "#" && startsHashtag(characters, at: index)) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    /// Counted in characters, as people count them: Cyrillic and emoji are one each.
    static func problem(with text: String) -> String? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "The post text is empty."
        }
        let length = text.count
        if length > maxLength {
            return "The post is \(length) characters long; LinkedIn allows \(maxLength)."
        }
        return nil
    }

    /// A hashtag starts a word: `C#` and `#` followed by a space are not one.
    private static func startsHashtag(_ characters: [Character], at index: Int) -> Bool {
        guard index + 1 < characters.count, isWordCharacter(characters[index + 1]) else { return false }
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        return !isWordCharacter(previous) && previous != "_"
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
