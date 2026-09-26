//
//  CurlParser.swift
//  Toolbelt
//
//  A pasted curl command becomes a request. Pure functions: the tests run them on
//  commands copied from Chrome, Postman and API docs.
//

import Foundation

nonisolated enum CurlParseError: LocalizedError, Equatable {
    case empty
    case unterminatedQuote
    case missingURL
    case missingValue(option: String)

    var errorDescription: String? {
        switch self {
        case .empty: return "The command is empty"
        case .unterminatedQuote: return "A quote is never closed"
        case .missingURL: return "No URL in the command"
        case let .missingValue(option): return "\(option) expects a value"
        }
    }
}

struct CurlParseResult: Equatable {
    var draft: HTTPRequestDraft
    var warnings: [String]
}

/// Splits a command line the way bash does — quotes, backslashes, `$'…'` and
/// line continuations — into the arguments curl itself would receive.
enum ShellWords {
    static func split(_ input: String) throws -> [String] {
        let characters = Array(input)
        var words: [String] = []
        var word = ""
        var hasWord = false
        var index = 0

        func endWord() {
            if hasWord { words.append(word) }
            word = ""
            hasWord = false
        }

        while index < characters.count {
            let character = characters[index]

            if character == "\\" {
                index += 1
                guard index < characters.count else { break }
                // Pasted commands often carry spaces after the continuation backslash.
                var lookahead = index
                while lookahead < characters.count, characters[lookahead] == " " || characters[lookahead] == "\t" {
                    lookahead += 1
                }
                if lookahead < characters.count, characters[lookahead].isNewline {
                    index = lookahead + 1
                    continue
                }
                word.append(characters[index])
                hasWord = true
                index += 1
                continue
            }

            if character == "'" {
                hasWord = true
                index += 1
                while index < characters.count, characters[index] != "'" {
                    word.append(characters[index])
                    index += 1
                }
                guard index < characters.count else { throw CurlParseError.unterminatedQuote }
                index += 1
                continue
            }

            if character == "$", index + 1 < characters.count, characters[index + 1] == "'" {
                hasWord = true
                index += 2
                var isClosed = false
                while index < characters.count {
                    let inner = characters[index]
                    if inner == "'" {
                        isClosed = true
                        index += 1
                        break
                    }
                    if inner == "\\", index + 1 < characters.count {
                        let (unescaped, consumed) = ansiEscape(characters, at: index + 1)
                        word.append(unescaped)
                        index += 1 + consumed
                        continue
                    }
                    word.append(inner)
                    index += 1
                }
                guard isClosed else { throw CurlParseError.unterminatedQuote }
                continue
            }

            if character == "\"" {
                hasWord = true
                index += 1
                var isClosed = false
                while index < characters.count {
                    let inner = characters[index]
                    if inner == "\"" {
                        isClosed = true
                        index += 1
                        break
                    }
                    if inner == "\\", index + 1 < characters.count {
                        let next = characters[index + 1]
                        if next.isNewline {
                            index += 2
                            continue
                        }
                        if next == "\"" || next == "\\" || next == "$" || next == "`" {
                            word.append(next)
                            index += 2
                            continue
                        }
                    }
                    word.append(inner)
                    index += 1
                }
                guard isClosed else { throw CurlParseError.unterminatedQuote }
                continue
            }

            if character.isWhitespace {
                endWord()
                index += 1
                continue
            }

            word.append(character)
            hasWord = true
            index += 1
        }

        endWord()
        return words
    }

    /// One escape inside `$'…'`: the character it stands for and how many characters
    /// after the backslash it used. An unknown escape keeps its backslash.
    private static func ansiEscape(_ characters: [Character], at index: Int) -> (Character, Int) {
        let character = characters[index]
        switch character {
        case "n": return ("\n", 1)
        case "t": return ("\t", 1)
        case "r": return ("\r", 1)
        case "a": return ("\u{07}", 1)
        case "b": return ("\u{08}", 1)
        case "e", "E": return ("\u{1B}", 1)
        case "f": return ("\u{0C}", 1)
        case "v": return ("\u{0B}", 1)
        case "\\", "'", "\"", "?": return (character, 1)
        case "x", "u", "U":
            let width = character == "x" ? 2 : (character == "u" ? 4 : 8)
            let digits = hexDigits(characters, from: index + 1, limit: width)
            if let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) {
                return (Character(scalar), 1 + digits.count)
            }
            return ("\\", 0)
        default:
            return ("\\", 0)
        }
    }

    private static func hexDigits(_ characters: [Character], from start: Int, limit: Int) -> String {
        var digits = ""
        var index = start
        while index < characters.count, digits.count < limit, characters[index].isHexDigit {
            digits.append(characters[index])
            index += 1
        }
        return digits
    }
}

enum CurlParser {
    static func parse(_ command: String) throws -> CurlParseResult {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CurlParseError.empty
        }

        var tokens = try ShellWords.split(command)
        if tokens.first == "$" { tokens.removeFirst() }
        if tokens.first?.lowercased() == "curl" { tokens.removeFirst() }

        var state = ParseState()
        var index = 0

        func value(for option: String) throws -> String {
            index += 1
            guard index < tokens.count else { throw CurlParseError.missingValue(option: option) }
            return tokens[index]
        }

        while index < tokens.count {
            var option = tokens[index]

            if option.hasPrefix("--"), let equals = option.firstIndex(of: "="),
               takesValue(String(option[..<equals])) {
                tokens[index] = String(option[..<equals])
                tokens.insert(String(option[option.index(after: equals)...]), at: index + 1)
                option = tokens[index]
            } else if let expanded = expandShortOptions(option) {
                tokens.replaceSubrange(index...index, with: expanded)
                option = tokens[index]
            }

            switch option {
            case "-X", "--request":
                let method = try value(for: option).uppercased()
                state.explicitMethod = method.isEmpty ? nil : method
            case "-H", "--header":
                try state.addHeaderLine(value(for: option))
            case "-d", "--data", "--data-ascii", "--data-raw", "--data-binary":
                let data = try value(for: option)
                if option != "--data-raw", data.hasPrefix("@") {
                    state.warn("\(data): reading a file with @ is not supported, the text is sent as is")
                }
                state.dataParts.append(data)
            case "--data-urlencode":
                try state.dataParts.append(urlEncodedData(value(for: option)))
            case "--json":
                try state.dataParts.append(value(for: option))
                state.isJSON = true
            case "-G", "--get":
                state.movesDataToQuery = true
            case "-I", "--head":
                state.isHead = true
            case "-u", "--user":
                try state.setBasicAuth(value(for: option))
            case "-b", "--cookie":
                let cookie = try value(for: option)
                if cookie.contains("=") {
                    state.addHeader("Cookie", cookie)
                } else {
                    state.warn("-b \(cookie): cookie files are not supported")
                }
            case "-A", "--user-agent":
                try state.addHeader("User-Agent", value(for: option))
            case "-e", "--referer":
                try state.addHeader("Referer", value(for: option))
            case "--url":
                try state.setURL(value(for: option))
            case "-F", "--form", "--form-string":
                _ = try value(for: option)
                state.warn("\(option): multipart forms are not supported yet, the field was skipped")
            case "-T", "--upload-file":
                _ = try value(for: option)
                state.warn("\(option): file uploads are not supported")
            case "-k", "--insecure":
                state.warn("-k is ignored: TLS certificates are always verified")
            case _ where ignoredFlags.contains(option):
                break
            case _ where ignoredOptionsWithValue.contains(option):
                _ = try value(for: option)
            default:
                if option.hasPrefix("-"), option.count > 1 {
                    state.warn("\(option) is not supported and was ignored")
                } else {
                    state.setURL(option)
                }
            }
            index += 1
        }

        return try state.result()
    }

    // MARK: Options

    private static let longOptionsWithValue: Set<String> = [
        "--request", "--header", "--data", "--data-ascii", "--data-raw", "--data-binary", "--data-urlencode",
        "--json", "--user", "--cookie", "--user-agent", "--referer", "--url", "--form", "--form-string", "--upload-file"
    ]

    private static func takesValue(_ option: String) -> Bool {
        longOptionsWithValue.contains(option) || ignoredOptionsWithValue.contains(option)
    }

    private static let shortOptionsWithValue: Set<String> = [
        "-X", "-H", "-d", "-u", "-b", "-A", "-e", "-F", "-T",
        "-o", "-m", "-x", "-c", "-D", "-w", "-r", "-E", "-K", "-U", "-z", "-C", "-y", "-Y", "-t", "-P", "-Q"
    ]

    private static let ignoredFlags: Set<String> = [
        "-L", "--location", "--location-trusted", "--compressed",
        "-s", "--silent", "-S", "--show-error", "-v", "--verbose", "-i", "--include", "-f", "--fail",
        "-#", "--progress-bar", "--no-progress-meter", "-N", "--no-buffer", "-g", "--globoff",
        "-4", "--ipv4", "-6", "--ipv6", "-0", "--http1.0", "--http1.1", "--http2", "--http3",
        "--tlsv1", "--tlsv1.1", "--tlsv1.2", "--tlsv1.3", "--ssl-no-revoke",
        "-j", "--junk-session-cookies", "-l", "--list-only", "--fail-with-body", "--no-keepalive"
    ]

    private static let ignoredOptionsWithValue: Set<String> = [
        "-o", "--output", "--output-dir", "-m", "--max-time", "--connect-timeout",
        "-x", "--proxy", "-U", "--proxy-user", "--cacert", "--capath", "-E", "--cert", "--key",
        "-c", "--cookie-jar", "--retry", "--retry-delay", "--retry-max-time", "--max-redirs",
        "-w", "--write-out", "-r", "--range", "--resolve", "--interface", "-D", "--dump-header",
        "--limit-rate", "--proto", "-K", "--config", "--ciphers", "--stderr", "--trace", "--trace-ascii",
        "-z", "--time-cond", "-C", "--continue-at", "--keepalive-time", "--dns-servers",
        "--unix-socket", "--abstract-unix-socket", "--pinnedpubkey", "--expect100-timeout",
        "--happy-eyeballs-timeout-ms", "--tls-max", "--variable", "-y", "--speed-time", "-Y", "--speed-limit",
        "-t", "--telnet-option", "-P", "--ftp-port", "-Q", "--quote"
    ]

    /// `-XPOST` is `-X POST` and `-sSL` is `-s -S -L`; nil when the token is not a short option cluster.
    private static func expandShortOptions(_ token: String) -> [String]? {
        guard token.hasPrefix("-"), !token.hasPrefix("--"), token.count > 2 else { return nil }
        var expanded: [String] = []
        var rest = token.dropFirst()
        while let flag = rest.first {
            rest = rest.dropFirst()
            let option = "-\(flag)"
            expanded.append(option)
            if shortOptionsWithValue.contains(option) {
                if !rest.isEmpty { expanded.append(String(rest)) }
                break
            }
        }
        return expanded
    }

    // MARK: Encoding

    /// curl's rules: `name=value` encodes the value, `=value` and a bare value encode all of it.
    private static func urlEncodedData(_ argument: String) -> String {
        guard let equals = argument.firstIndex(of: "=") else { return percentEncoded(argument) }
        let name = String(argument[..<equals])
        let value = percentEncoded(String(argument[argument.index(after: equals)...]))
        return name.isEmpty ? value : "\(name)=\(value)"
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    // MARK: State

    private struct ParseState {
        var explicitMethod: String?
        var url: String?
        var headers: [HTTPHeader] = []
        var dataParts: [String] = []
        var movesDataToQuery = false
        var isHead = false
        var isJSON = false
        var warnings: [String] = []

        mutating func warn(_ message: String) {
            warnings.append(message)
        }

        mutating func addHeader(_ name: String, _ value: String) {
            headers.append(HTTPHeader(name: name, value: value))
        }

        /// `Name: value`; `Name;` is how curl sends an empty header.
        mutating func addHeaderLine(_ line: String) {
            if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if name.isEmpty {
                    warn("Header \"\(line)\" has no name and was skipped")
                } else {
                    addHeader(name, value)
                }
            } else if line.hasSuffix(";"), line.count > 1 {
                addHeader(String(line.dropLast()).trimmingCharacters(in: .whitespaces), "")
            } else {
                warn("Header \"\(line)\" has no colon and was skipped")
            }
        }

        mutating func setBasicAuth(_ credentials: String) {
            let pair = credentials.contains(":") ? credentials : credentials + ":"
            addHeader("Authorization", "Basic " + Data(pair.utf8).base64EncodedString())
        }

        /// The first bare argument is the URL; a later one with a scheme replaces a bare host.
        mutating func setURL(_ candidate: String) {
            guard let current = url else {
                url = candidate
                return
            }
            if !current.contains("://"), candidate.contains("://") {
                url = candidate
                warn("\(current) was ignored: \(candidate) looks more like the URL")
            } else {
                warn("\(candidate) was ignored: the URL is already \(current)")
            }
        }

        func result() throws -> CurlParseResult {
            guard var url = url, !url.isEmpty else { throw CurlParseError.missingURL }
            var headers = headers
            var warnings = warnings
            var body = ""

            if !url.contains("://") {
                url = "http://" + url
                warnings.append("The URL has no scheme, http:// was assumed")
            }

            if !dataParts.isEmpty {
                let data = dataParts.joined(separator: "&")
                if movesDataToQuery {
                    url += (url.contains("?") ? "&" : "?") + data
                } else {
                    body = data
                    func addMissing(_ name: String, _ value: String) {
                        let exists = headers.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                        if !exists { headers.append(HTTPHeader(name: name, value: value)) }
                    }
                    if isJSON {
                        addMissing("Content-Type", "application/json")
                        addMissing("Accept", "application/json")
                    } else {
                        addMissing("Content-Type", "application/x-www-form-urlencoded")
                    }
                }
            }

            let method = explicitMethod ?? (isHead ? "HEAD" : (body.isEmpty ? "GET" : "POST"))
            let draft = HTTPRequestDraft(method: method, url: url, headers: headers, body: body)
            return CurlParseResult(draft: draft, warnings: warnings)
        }
    }
}
