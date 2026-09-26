//
//  CurlBuilder.swift
//  Toolbelt
//

import Foundation

enum CurlBuilder {
    /// A command curl runs exactly as the form shows: `--data-raw` keeps `@` literal,
    /// single quotes keep everything else. One option per line, so it reads in a chat.
    static func command(for draft: HTTPRequestDraft) -> String {
        let trimmedMethod = draft.method.trimmingCharacters(in: .whitespaces).uppercased()
        let method = trimmedMethod.isEmpty ? "GET" : trimmedMethod
        let url = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)

        var first = ["curl"]
        if method == "HEAD" {
            first.append("-I")
        } else if method != "GET" || !draft.body.isEmpty {
            first += ["-X", method]
        }
        first.append(Shell.singleQuoted(url))

        var lines = [first.joined(separator: " ")]
        for header in draft.enabledHeaders {
            let name = header.name.trimmingCharacters(in: .whitespaces)
            // `Name;` is curl's syntax for an empty header; `Name:` would drop it.
            let line = header.value.isEmpty ? "\(name);" : "\(name): \(header.value)"
            lines.append("-H " + Shell.singleQuoted(line))
        }
        if !draft.body.isEmpty {
            lines.append("--data-raw " + Shell.singleQuoted(draft.body))
        }
        return lines.joined(separator: " \\\n  ")
    }
}
