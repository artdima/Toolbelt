import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Разбор Conventional Commits")
struct ReleaseNotesParsingTests {
    @Test("Простой коммит: тип и описание")
    func plainCommit() {
        let commit = ReleaseNotesBuilder.parse(subject: "feat: add deep link tester")

        #expect(commit.type == "feat")
        #expect(commit.isBreaking == false)
        #expect(commit.summary == "add deep link tester")
    }

    @Test("Scope отбрасывается")
    func scopeIsDropped() {
        let commit = ReleaseNotesBuilder.parse(subject: "fix(ui): dismiss panel")

        #expect(commit.type == "fix")
        #expect(commit.summary == "dismiss panel")
    }

    @Test("Двоеточие внутри scope не заканчивает заголовок")
    func colonInsideScope() {
        let commit = ReleaseNotesBuilder.parse(subject: "fix(api:v2): не падать на пустом ответе")

        #expect(commit.type == "fix")
        #expect(commit.summary == "не падать на пустом ответе")
    }

    @Test("Восклицательный знак помечает breaking change")
    func breakingMarker() {
        let commit = ReleaseNotesBuilder.parse(subject: "feat(ui)!: drop legacy panel")

        #expect(commit.type == "feat")
        #expect(commit.isBreaking)
        #expect(commit.summary == "drop legacy panel")
    }

    @Test("Пробел до двоеточия отменяет разбор")
    func spaceBeforeColon() {
        let commit = ReleaseNotesBuilder.parse(subject: "Add support for X: details here")

        #expect(commit.type == nil)
        #expect(commit.summary == "Add support for X: details here")
    }

    @Test("Коммит без двоеточия попадает в «Прочее»")
    func subjectWithoutColon() {
        let commit = ReleaseNotesBuilder.parse(subject: "WIP")

        #expect(commit.type == nil)
        #expect(ReleaseNotesBuilder.section(for: commit) == .other)
    }

    @Test("Тип с заглавной буквы типом не считается")
    func capitalizedTypeIsNotAType() {
        #expect(ReleaseNotesBuilder.parse(subject: "Fix: something").type == nil)
    }

    @Test("Пустое описание отменяет разбор")
    func emptySummary() {
        #expect(ReleaseNotesBuilder.parse(subject: "chore:").type == nil)
    }

    @Test("Раскладка по разделам", arguments: [
        ("feat: a", ReleaseSection.feature),
        ("fix: a", ReleaseSection.fix),
        ("perf: a", ReleaseSection.performance),
        ("chore: a", ReleaseSection.other),
        ("feat!: a", ReleaseSection.breaking)
    ])
    func sections(subject: String, expected: ReleaseSection) {
        #expect(ReleaseNotesBuilder.section(for: ReleaseNotesBuilder.parse(subject: subject)) == expected)
    }
}

@Suite("Сборка текста What's New")
struct ReleaseNotesDraftTests {
    private let subjects = [
        "feat: add deep link tester",
        "fix: dismiss panel on window open",
        "chore: update app icon",
        "feat!: drop legacy panel"
    ]

    @Test("Технические коммиты скрыты по умолчанию")
    func technicalHiddenByDefault() {
        let commits = ReleaseNotesBuilder.commits(from: subjects, includeTechnical: false)

        #expect(commits.count == 3)
        #expect(commits.allSatisfy { $0.type != "chore" })
    }

    @Test("Флаг включает технические коммиты")
    func technicalIncludedByFlag() {
        #expect(ReleaseNotesBuilder.commits(from: subjects, includeTechnical: true).count == 4)
    }

    @Test("Breaking change не считается техническим даже с типом chore")
    func breakingIsNeverTechnical() {
        #expect(ReleaseNotesBuilder.commits(from: ["chore!: drop API"], includeTechnical: false).count == 1)
    }

    @Test("App Store: текст с заголовками разделов")
    func appStoreDraftHasSectionTitles() {
        let commits = ReleaseNotesBuilder.commits(from: subjects, includeTechnical: false)
        let draft = ReleaseNotesBuilder.draft(commits: commits, locale: .ru, store: .appStore)

        #expect(draft.contains("Важно"))
        #expect(draft.contains("Новое"))
        #expect(draft.contains("Исправления"))
        #expect(draft.contains("• Add deep link tester"))
    }

    @Test("Google Play: плоский список без заголовков")
    func googlePlayDraftIsFlat() {
        let commits = ReleaseNotesBuilder.commits(from: subjects, includeTechnical: false)
        let draft = ReleaseNotesBuilder.draft(commits: commits, locale: .ru, store: .googlePlay)

        #expect(!draft.contains("Новое"))
        #expect(draft.split(separator: "\n").allSatisfy { $0.hasPrefix("• ") })
    }

    @Test("Заголовки разделов локализуются")
    func sectionTitlesAreLocalized() {
        let commits = ReleaseNotesBuilder.commits(from: ["feat: a"], includeTechnical: false)
        let draft = ReleaseNotesBuilder.draft(commits: commits, locale: .en, store: .appStore)

        #expect(draft.contains("What's new"))
    }

    @Test("Описание начинается с заглавной буквы")
    func summaryIsCapitalized() {
        let commits = ReleaseNotesBuilder.commits(from: ["feat: add thing"], includeTechnical: false)

        #expect(ReleaseNotesBuilder.draft(commits: commits, locale: .ru, store: .googlePlay) == "• Add thing")
    }

    @Test("Порядок разделов: важное, новое, исправления")
    func sectionOrderIsStable() throws {
        let commits = ReleaseNotesBuilder.commits(
            from: ["fix: b", "feat!: a", "feat: c"],
            includeTechnical: false
        )
        let draft = ReleaseNotesBuilder.draft(commits: commits, locale: .ru, store: .appStore)

        let breaking = try #require(draft.range(of: "Важно"))
        let feature = try #require(draft.range(of: "Новое"))
        let fix = try #require(draft.range(of: "Исправления"))

        #expect(breaking.lowerBound < feature.lowerBound)
        #expect(feature.lowerBound < fix.lowerBound)
    }
}
