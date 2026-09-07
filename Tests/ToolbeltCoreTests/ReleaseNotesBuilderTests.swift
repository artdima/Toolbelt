import Foundation
import Testing
@testable import ToolbeltCore

@Suite("Conventional Commits parsing")
struct ReleaseNotesParsingTests {
    @Test("Plain commit: type and description")
    func plainCommit() {
        let commit = ReleaseNotesBuilder.parse(subject: "feat: add deep link tester")

        #expect(commit.type == "feat")
        #expect(commit.isBreaking == false)
        #expect(commit.summary == "add deep link tester")
    }

    @Test("The scope is dropped")
    func scopeIsDropped() {
        let commit = ReleaseNotesBuilder.parse(subject: "fix(ui): dismiss panel")

        #expect(commit.type == "fix")
        #expect(commit.summary == "dismiss panel")
    }

    @Test("A colon inside the scope does not end the header")
    func colonInsideScope() {
        let commit = ReleaseNotesBuilder.parse(subject: "fix(api:v2): keep empty responses from crashing")

        #expect(commit.type == "fix")
        #expect(commit.summary == "keep empty responses from crashing")
    }

    @Test("An exclamation mark marks a breaking change")
    func breakingMarker() {
        let commit = ReleaseNotesBuilder.parse(subject: "feat(ui)!: drop legacy panel")

        #expect(commit.type == "feat")
        #expect(commit.isBreaking)
        #expect(commit.summary == "drop legacy panel")
    }

    @Test("A space before the colon cancels parsing")
    func spaceBeforeColon() {
        let commit = ReleaseNotesBuilder.parse(subject: "Add support for X: details here")

        #expect(commit.type == nil)
        #expect(commit.summary == "Add support for X: details here")
    }

    @Test("A subject without a colon goes to Other")
    func subjectWithoutColon() {
        let commit = ReleaseNotesBuilder.parse(subject: "WIP")

        #expect(commit.type == nil)
        #expect(ReleaseNotesBuilder.section(for: commit) == .other)
    }

    @Test("A capitalized type is not a type")
    func capitalizedTypeIsNotAType() {
        #expect(ReleaseNotesBuilder.parse(subject: "Fix: something").type == nil)
    }

    @Test("An empty description cancels parsing")
    func emptySummary() {
        #expect(ReleaseNotesBuilder.parse(subject: "chore:").type == nil)
    }

    @Test("Mapping types onto sections", arguments: [
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

@Suite("Building the What's New text")
struct ReleaseNotesDraftTests {
    private let subjects = [
        "feat: add deep link tester",
        "fix: dismiss panel on window open",
        "chore: update app icon",
        "feat!: drop legacy panel"
    ]

    @Test("Technical commits are hidden by default")
    func technicalHiddenByDefault() {
        let commits = ReleaseNotesBuilder.commits(from: subjects, includeTechnical: false)

        #expect(commits.count == 3)
        #expect(commits.allSatisfy { $0.type != "chore" })
    }

    @Test("The flag brings technical commits back")
    func technicalIncludedByFlag() {
        #expect(ReleaseNotesBuilder.commits(from: subjects, includeTechnical: true).count == 4)
    }

    @Test("A breaking change is never technical, even typed chore")
    func breakingIsNeverTechnical() {
        #expect(ReleaseNotesBuilder.commits(from: ["chore!: drop API"], includeTechnical: false).count == 1)
    }

    @Test("App Store: the text carries section titles")
    func appStoreDraftHasSectionTitles() {
        let commits = ReleaseNotesBuilder.commits(from: subjects, includeTechnical: false)
        let draft = ReleaseNotesBuilder.draft(commits: commits, locale: .en, store: .appStore)

        #expect(draft.contains("Important"))
        #expect(draft.contains("What's new"))
        #expect(draft.contains("Fixes"))
        #expect(draft.contains("• Add deep link tester"))
    }

    @Test("Google Play: a flat list without titles")
    func googlePlayDraftIsFlat() {
        let commits = ReleaseNotesBuilder.commits(from: subjects, includeTechnical: false)
        let draft = ReleaseNotesBuilder.draft(commits: commits, locale: .en, store: .googlePlay)

        #expect(!draft.contains("What's new"))
        #expect(draft.split(separator: "\n").allSatisfy { $0.hasPrefix("• ") })
    }

    @Test("Section titles are localized")
    func sectionTitlesAreLocalized() {
        let commits = ReleaseNotesBuilder.commits(from: ["feat: a"], includeTechnical: false)
        let english = ReleaseNotesBuilder.draft(commits: commits, locale: .en, store: .appStore)
        let russian = ReleaseNotesBuilder.draft(commits: commits, locale: .ru, store: .appStore)

        #expect(english.contains("What's new"))
        #expect(english != russian)
    }

    @Test("A description starts with a capital letter")
    func summaryIsCapitalized() {
        let commits = ReleaseNotesBuilder.commits(from: ["feat: add thing"], includeTechnical: false)

        #expect(ReleaseNotesBuilder.draft(commits: commits, locale: .en, store: .googlePlay) == "• Add thing")
    }

    @Test("Section order: breaking, new, fixes")
    func sectionOrderIsStable() throws {
        let commits = ReleaseNotesBuilder.commits(
            from: ["fix: b", "feat!: a", "feat: c"],
            includeTechnical: false
        )
        let draft = ReleaseNotesBuilder.draft(commits: commits, locale: .en, store: .appStore)

        let breaking = try #require(draft.range(of: "Important"))
        let feature = try #require(draft.range(of: "What's new"))
        let fix = try #require(draft.range(of: "Fixes"))

        #expect(breaking.lowerBound < feature.lowerBound)
        #expect(feature.lowerBound < fix.lowerBound)
    }
}
