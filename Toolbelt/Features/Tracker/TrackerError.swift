//
//  TrackerError.swift
//  Toolbelt
//

import Foundation

enum TrackerError: LocalizedError, Equatable {
    case missingToken
    case missingOrgId
    case invalidURL
    case unexpectedResponse
    case unauthorized
    case forbidden
    case notFound
    case http(status: Int, message: String)
    case decoding(String)
    case unknownUser

    /// Разбор HTTP-ответа отделён от транспорта: так его можно проверить тестами
    /// без сети и без подмены URLSession.
    static func from(status: Int, body: String) -> TrackerError {
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        default: return .http(status: status, message: String(body.prefix(300)))
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Не указан OAuth-токен. Откройте настройки."
        case .missingOrgId:
            return "Не указан идентификатор организации. Откройте настройки."
        case .invalidURL:
            return "Некорректный URL запроса"
        case .unexpectedResponse:
            return "Неожиданный ответ сервера"
        case .unauthorized:
            return "401: токен недействителен или истёк"
        case .forbidden:
            return "403: нет доступа. Проверьте идентификатор организации и её тип"
        case .notFound:
            return "404: ресурс не найден"
        case let .http(status, message):
            return message.isEmpty ? "HTTP \(status)" : "HTTP \(status): \(message)"
        case let .decoding(details):
            return "Не удалось разобрать ответ Трекера: \(details)"
        case .unknownUser:
            return "Не удалось определить текущего пользователя Трекера"
        }
    }
}
