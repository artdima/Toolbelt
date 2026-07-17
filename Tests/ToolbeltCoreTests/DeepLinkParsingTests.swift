import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Разбор списка устройств")
struct DeepLinkParsingTests {
    @Test("Симуляторы из JSON simctl")
    func simulatorsFromSimctl() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              { "udid": "AAA-111", "name": "iPhone 16 Pro", "state": "Booted" }
            ]
          }
        }
        """

        let targets = DeepLinkParsing.simulators(fromSimctlJSON: Data(json.utf8))
        let target = try #require(targets.first)

        #expect(targets.count == 1)
        #expect(target.platform == .ios)
        #expect(target.identifier == "AAA-111")
        #expect(target.name == "iPhone 16 Pro · iOS 18 0")
    }

    @Test("Несколько рантаймов идут в предсказуемом порядке")
    func simulatorsAreOrdered() {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
              { "udid": "B", "name": "iPhone 17", "state": "Booted" }
            ],
            "com.apple.CoreSimulator.SimRuntime.iOS-18-0": [
              { "udid": "A", "name": "iPhone 16", "state": "Booted" }
            ]
          }
        }
        """

        #expect(DeepLinkParsing.simulators(fromSimctlJSON: Data(json.utf8)).map(\.identifier) == ["A", "B"])
    }

    @Test("Битый JSON даёт пустой список")
    func brokenJSONIsEmpty() {
        #expect(DeepLinkParsing.simulators(fromSimctlJSON: Data("не json".utf8)).isEmpty)
    }

    @Test("Устройства из вывода adb devices -l")
    func androidDevices() throws {
        let output = """
        List of devices attached
        emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1
        """

        let targets = DeepLinkParsing.androidDevices(fromAdbOutput: output)
        let target = try #require(targets.first)

        #expect(targets.count == 1)
        #expect(target.platform == .android)
        #expect(target.identifier == "emulator-5554")
        #expect(target.name == "sdk gphone64 arm64 · emulator-5554")
    }

    /// В список попадают только устройства в состоянии device.
    @Test("Неавторизованные и оффлайн-устройства пропускаются")
    func onlyReadyDevicesAreListed() {
        let output = """
        List of devices attached
        emulator-5554          device
        1234567890             unauthorized
        abcdef                 offline
        """

        #expect(DeepLinkParsing.androidDevices(fromAdbOutput: output).map(\.identifier) == ["emulator-5554"])
    }

    @Test("Устройство без model показывается по серийному номеру")
    func deviceWithoutModel() {
        let output = """
        List of devices attached
        R58M1234ABC            device
        """

        #expect(DeepLinkParsing.androidDevices(fromAdbOutput: output).first?.name == "R58M1234ABC")
    }

    @Test("Пустой вывод adb даёт пустой список")
    func emptyAdbOutput() {
        #expect(DeepLinkParsing.androidDevices(fromAdbOutput: "List of devices attached\n").isEmpty)
    }

    @Test("Идентификатор цели различает платформы")
    func targetIdIncludesPlatform() {
        let ios = DeepLinkTarget(platform: .ios, identifier: "X", name: "n")
        let android = DeepLinkTarget(platform: .android, identifier: "X", name: "n")

        #expect(ios.id != android.id)
    }
}

@Suite("Экранирование команд")
struct ShellQuotingTests {
    /// adb пересобирает команду на устройстве, поэтому `&` из query-строки
    /// обязан остаться внутри кавычек.
    @Test("Ссылка с амперсандом закрывается кавычками")
    func urlWithAmpersandIsQuoted() {
        #expect(Shell.singleQuoted("myapp://x?a=1&b=2") == "'myapp://x?a=1&b=2'")
    }

    @Test("Одинарная кавычка внутри значения экранируется")
    func singleQuoteInsideValue() {
        #expect(Shell.singleQuoted("a'b") == "'a'\\''b'")
    }

    @Test("Команда для терминала берёт спецсимволы в кавычки")
    func displayCommandQuotesSpecialCharacters() {
        let command = Shell.displayCommand("/usr/bin/xcrun", ["simctl", "openurl", "BOOTED", "myapp://x?a=1&b=2"])

        #expect(command == "/usr/bin/xcrun simctl openurl BOOTED \"myapp://x?a=1&b=2\"")
    }

    @Test("Уже закавыченный аргумент оборачивается в двойные кавычки")
    func alreadyQuotedArgument() {
        let command = Shell.displayCommand("/opt/adb", ["-d", "'myapp://x'"])

        #expect(command == "/opt/adb -d \"'myapp://x'\"")
    }

    @Test("Обычные аргументы остаются без кавычек")
    func plainArgumentsStayBare() {
        #expect(Shell.displayCommand("/usr/bin/git", ["status"]) == "/usr/bin/git status")
    }
}

@Suite("Ошибки Трекера")
struct TrackerErrorTests {
    @Test("Коды ответа разбираются в понятные ошибки", arguments: [
        (401, TrackerError.unauthorized),
        (403, TrackerError.forbidden),
        (404, TrackerError.notFound)
    ])
    func knownStatuses(status: Int, expected: TrackerError) {
        #expect(TrackerError.from(status: status, body: "") == expected)
    }

    @Test("Неизвестный код сохраняет тело ответа")
    func unknownStatusKeepsBody() {
        let error = TrackerError.from(status: 500, body: "internal error")

        #expect(error == .http(status: 500, message: "internal error"))
    }

    /// Тело ответа попадает в UI, поэтому обрезается.
    @Test("Длинное тело ответа обрезается")
    func longBodyIsTruncated() {
        let error = TrackerError.from(status: 500, body: String(repeating: "x", count: 1000))

        #expect(error == .http(status: 500, message: String(repeating: "x", count: 300)))
    }

    @Test("У всех ошибок есть текст для пользователя")
    func allErrorsHaveDescription() {
        let errors: [TrackerError] = [
            .missingToken, .missingOrgId, .invalidURL, .unexpectedResponse,
            .unauthorized, .forbidden, .notFound,
            .http(status: 500, message: "x"), .decoding("x"), .unknownUser
        ]

        #expect(errors.allSatisfy { $0.errorDescription?.isEmpty == false })
    }
}
