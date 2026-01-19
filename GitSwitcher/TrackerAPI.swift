//
//  TrackerAPI.swift
//  GitSwitcher
//
//  Работа с API Яндекс Трекера: записи о затраченном времени (worklog).
//

import Foundation
import Security

// MARK: - Ошибки

struct TrackerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Учётные данные

/// Тип организации определяет, какой заголовок отправлять: `X-Org-ID` или `X-Cloud-Org-ID`.
enum TrackerOrgKind: String, CaseIterable, Identifiable {
    case yandex360   // Яндекс 360 для бизнеса → X-Org-ID
    case cloud       // Yandex Identity Hub / Cloud → X-Cloud-Org-ID

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yandex360: return "Яндекс 360"
        case .cloud: return "Yandex Cloud"
        }
    }

    var headerName: String {
        switch self {
        case .yandex360: return "X-Org-ID"
        case .cloud: return "X-Cloud-Org-ID"
        }
    }
}

/// Токен хранится в Keychain, идентификатор организации — в UserDefaults.
enum TrackerCredentials {
    private static let keychainService = "app.dima.GitSwitcher.tracker"
    private static let keychainAccount = "oauth-token"
    private static let orgIdKey = "tracker.orgId"
    private static let orgKindKey = "tracker.orgKind"

    static var token: String {
        get { readKeychain() ?? "" }
        set { writeKeychain(newValue) }
    }

    static var orgId: String {
        get { UserDefaults.standard.string(forKey: orgIdKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: orgIdKey) }
    }

    static var orgKind: TrackerOrgKind {
        get {
            let raw = UserDefaults.standard.string(forKey: orgKindKey) ?? ""
            return TrackerOrgKind(rawValue: raw) ?? .yandex360
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: orgKindKey) }
    }

    static var isConfigured: Bool {
        !token.trimmingCharacters(in: .whitespaces).isEmpty
            && !orgId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Keychain

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(base as CFDictionary)

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }

        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

// MARK: - Модели ответа API

private struct TrackerMyself: Decodable {
    let uid: Int?
    let login: String?
    let display: String?
}

private struct WorklogDTO: Decodable {
    struct IssueRef: Decodable {
        let key: String
        let display: String?
    }
    struct UserRef: Decodable {
        let display: String?
    }

    let id: Int
    let issue: IssueRef
    let comment: String?
    let createdBy: UserRef?
    let start: String
    let duration: String
}

/// Разобранная запись о затраченном времени.
struct Worklog: Identifiable, Hashable {
    let id: Int
    let issueKey: String
    let issueTitle: String
    let comment: String?
    let start: Date
    let seconds: TimeInterval
}

// MARK: - API

enum TrackerAPI {
    static let baseURL = "https://api.tracker.yandex.net/v3"

    /// В Трекере длительности хранятся в «рабочих» единицах.
    static let hoursPerWorkday: Double = 8
    static let daysPerWorkweek: Double = 5

    /// Запас по `createdAt` вокруг недели: запись можно залогировать задним числом.
    private static let createdAtPaddingDays = 30

    private static func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        print("[Tracker \(formatter.string(from: Date()))] \(message)")
    }

    // MARK: Запросы

    private static func makeRequest(path: String, method: String, body: Data?) throws -> URLRequest {
        let token = TrackerCredentials.token.trimmingCharacters(in: .whitespacesAndNewlines)
        let orgId = TrackerCredentials.orgId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else {
            throw TrackerError(message: "Не указан OAuth-токен. Откройте настройки отчёта.")
        }
        guard !orgId.isEmpty else {
            throw TrackerError(message: "Не указан идентификатор организации. Откройте настройки отчёта.")
        }
        guard let url = URL(string: baseURL + path) else {
            throw TrackerError(message: "Некорректный URL запроса")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 60
        request.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(orgId, forHTTPHeaderField: TrackerCredentials.orgKind.headerName)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private static func perform(_ request: URLRequest) async throws -> Data {
        log("→ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?")")
        if let body = request.httpBody {
            log("→ body: \(String(data: body, encoding: .utf8) ?? "<не utf8>")")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TrackerError(message: "Неожиданный ответ сервера")
        }
        log("← HTTP \(http.statusCode), байт: \(data.count)")

        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            log("← ошибка: \(text)")
            switch http.statusCode {
            case 401:
                throw TrackerError(message: "401: токен недействителен или истёк")
            case 403:
                throw TrackerError(message: "403: нет доступа. Проверьте идентификатор организации и её тип")
            case 404:
                throw TrackerError(message: "404: ресурс не найден")
            default:
                throw TrackerError(message: "HTTP \(http.statusCode): \(text.prefix(300))")
            }
        }
        return data
    }

    /// Логин текущего пользователя — по нему фильтруются записи.
    static func fetchMyLogin() async throws -> String {
        let request = try makeRequest(path: "/myself", method: "GET", body: nil)
        let data = try await perform(request)
        let myself = try JSONDecoder().decode(TrackerMyself.self, from: data)

        if let login = myself.login, !login.isEmpty {
            log("Текущий пользователь: \(login)")
            return login
        }
        if let uid = myself.uid {
            log("Текущий пользователь (uid): \(uid)")
            return String(uid)
        }
        throw TrackerError(message: "Не удалось определить текущего пользователя Трекера")
    }

    /// Записи о затраченном времени, у которых `start` попадает в интервал `[from, to)`.
    static func fetchWorklog(from: Date, to: Date) async throws -> [Worklog] {
        let login = try await fetchMyLogin()

        let calendar = Calendar.current
        let createdFrom = calendar.date(byAdding: .day, value: -createdAtPaddingDays, to: from) ?? from
        let createdTo = calendar.date(byAdding: .day, value: createdAtPaddingDays, to: to) ?? to

        let payload: [String: Any] = [
            "createdBy": login,
            "createdAt": [
                "from": apiDateFormatter.string(from: createdFrom),
                "to": apiDateFormatter.string(from: createdTo)
            ]
        ]

        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try makeRequest(path: "/worklog/_search?perPage=1000", method: "POST", body: body)
        let data = try await perform(request)

        let raw: [WorklogDTO]
        do {
            raw = try JSONDecoder().decode([WorklogDTO].self, from: data)
        } catch {
            log("✗ Ошибка разбора ответа: \(error)")
            throw TrackerError(message: "Не удалось разобрать ответ Трекера: \(error.localizedDescription)")
        }

        let entries: [Worklog] = raw.compactMap { dto in
            guard let start = parseDate(dto.start) else {
                log("⚠ Пропущена запись \(dto.id): не разобрана дата \(dto.start)")
                return nil
            }
            guard start >= from, start < to else { return nil }

            return Worklog(
                id: dto.id,
                issueKey: dto.issue.key,
                issueTitle: dto.issue.display ?? dto.issue.key,
                comment: dto.comment?.trimmingCharacters(in: .whitespacesAndNewlines),
                start: start,
                seconds: parseDuration(dto.duration)
            )
        }

        log("Записей всего: \(raw.count), в выбранном периоде: \(entries.count)")
        return entries.sorted { $0.start < $1.start }
    }

    // MARK: Даты

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()

    private static let apiDateFormatterNoMillis: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    static func parseDate(_ string: String) -> Date? {
        apiDateFormatter.date(from: string) ?? apiDateFormatterNoMillis.date(from: string)
    }

    // MARK: Длительность

    /// Разбирает ISO 8601 длительность вида `P1W2DT3H30M` в секунды.
    /// День и неделя считаются рабочими: 1 день = 8 ч, 1 неделя = 5 дней.
    static func parseDuration(_ string: String) -> TimeInterval {
        var value = Substring(string)
        guard value.first == "P" else { return 0 }
        value = value.dropFirst()

        var seconds: TimeInterval = 0
        var isTimePart = false
        var number = ""

        let hour: TimeInterval = 3600
        let workday = hoursPerWorkday * hour
        let workweek = daysPerWorkweek * workday

        for character in value {
            if character == "T" {
                isTimePart = true
                number = ""
                continue
            }
            if character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
                continue
            }

            let amount = Double(number) ?? 0
            number = ""

            switch character {
            case "Y": seconds += amount * 12 * 4 * workweek
            case "W": seconds += amount * workweek
            case "D": seconds += amount * workday
            case "H": seconds += amount * hour
            case "S": seconds += amount
            case "M": seconds += isTimePart ? amount * 60 : amount * 4 * workweek
            default: break
            }
        }
        return seconds
    }

    /// Секунды → «7 ч 30 м».
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total > 0 else { return "0 ч" }

        let hours = total / 3600
        let minutes = (total % 3600) / 60

        if hours > 0 && minutes > 0 { return "\(hours) ч \(minutes) м" }
        if hours > 0 { return "\(hours) ч" }
        return "\(minutes) м"
    }
}
