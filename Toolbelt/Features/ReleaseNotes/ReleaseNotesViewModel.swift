//
//  ReleaseNotesViewModel.swift
//  Toolbelt
//

import Observation
import SwiftUI

@Observable
@MainActor
final class ReleaseNotesViewModel {
    private static let repositoryPathKey = "releaseNotes.repositoryPath"
    private static let languageKey = "releaseNotes.language"

    private let git: GitRepositoryReading
    private let generator: ReleaseNotesGenerating
    private let defaults: UserDefaults

    private(set) var repositoryPath: String
    private(set) var tags: [String] = []
    private(set) var status: String?
    private(set) var isError = false
    private(set) var isLoadingTags = false
    private(set) var isBuilding = false
    private(set) var isGenerating = false

    var fromTag = ""
    var toRef = GitRepositoryService.headRef
    var includeTechnical = false
    var draft = ""

    private var storedLanguage: ReleaseNotesLanguage

    var language: ReleaseNotesLanguage {
        get { storedLanguage }
        set {
            storedLanguage = newValue
            defaults.set(newValue.rawValue, forKey: Self.languageKey)
        }
    }

    private var reloadTagsTask: Task<Void, Never>?

    convenience init() {
        self.init(git: GitRepositoryService(), generator: ClaudeReleaseNotesGenerator(), defaults: .standard)
    }

    init(git: GitRepositoryReading, generator: ReleaseNotesGenerating, defaults: UserDefaults) {
        self.git = git
        self.generator = generator
        self.defaults = defaults
        repositoryPath = defaults.string(forKey: Self.repositoryPathKey) ?? ""
        storedLanguage = .restored(from: defaults.string(forKey: Self.languageKey))
    }

    var hasRepository: Bool { !repositoryPath.isEmpty }

    var canGenerate: Bool {
        hasRepository
            && !isBuilding
            && !isGenerating
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func selectRepository(at path: String) {
        repositoryPath = path
        defaults.set(path, forKey: Self.repositoryPathKey)
        draft = ""
        status = nil
        isError = false
        reloadTagsTask?.cancel()
        reloadTagsTask = Task { await reloadTags() }
    }

    func reloadTags() async {
        // The path is captured before the first await: the user can pick another
        // repository while git is still answering.
        let path = repositoryPath
        guard !path.isEmpty else {
            tags = []
            return
        }

        isLoadingTags = true
        defer { isLoadingTags = false }

        guard await git.isRepository(at: path) else {
            guard path == repositoryPath else { return }
            tags = []
            report("The selected folder is not a git repository", isError: true)
            return
        }

        let loaded = (try? await git.tags(at: path)) ?? []
        guard path == repositoryPath else { return }

        tags = loaded
        if loaded.isEmpty {
            report("No tags — the whole history is available", isError: false)
        }

        if !tags.contains(fromTag) { fromTag = "" }
        if toRef != GitRepositoryService.headRef && !tags.contains(toRef) {
            toRef = GitRepositoryService.headRef
        }
    }

    func build() async {
        isBuilding = true
        defer { isBuilding = false }

        let subjects: [String]
        do {
            subjects = try await git.commitSubjects(
                at: repositoryPath,
                from: fromTag.isEmpty ? nil : fromTag,
                to: toRef
            )
        } catch {
            fail(error.localizedDescription)
            return
        }

        guard !subjects.isEmpty else {
            fail("No commits in this range")
            return
        }

        let commits = ReleaseNotesBuilder.commits(from: subjects, includeTechnical: includeTechnical)
        guard !commits.isEmpty else {
            fail("Every commit in the range is technical — turn on \"Technical\"")
            return
        }

        draft = ReleaseNotesBuilder.draft(commits: commits)

        report("\(commits.count) of \(subjects.count) commits in the draft", isError: false)
    }

    func generateWithClaude() async {
        isGenerating = true
        defer { isGenerating = false }
        report("Claude is writing the release notes…", isError: false)

        do {
            draft = try await generator.paragraph(from: draft, language: language, in: repositoryPath)
            report("Rewritten by Claude in \(language.title) — Build draft brings the list back", isError: false)
        } catch {
            report(error.localizedDescription, isError: true)
        }
    }

    /// A build failure clears the draft: valid text from a previous range must not
    /// sit next to a red status.
    private func fail(_ message: String) {
        draft = ""
        report(message, isError: true)
    }

    private func report(_ message: String?, isError: Bool) {
        status = message
        self.isError = isError
    }
}
