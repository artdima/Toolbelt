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
    /// Every commit subject in the range, technical ones included.
    private(set) var subjects: [String] = []
    private(set) var commits: [ReleaseCommitItem] = []
    private(set) var deselectedIDs: Set<ReleaseCommitItem.ID> = []

    var fromTag = ""
    var toRef = GitRepositoryService.headRef
    var draft = ""

    private var storedIncludeTechnical = false

    /// Re-filters the commits already read: no need to ask git again.
    var includeTechnical: Bool {
        get { storedIncludeTechnical }
        set {
            storedIncludeTechnical = newValue
            if !subjects.isEmpty {
                applyCommitList()
            }
        }
    }

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

    var selectedCount: Int {
        commits.filter(isSelected).count
    }

    var areAllSelected: Bool {
        selectedCount == commits.count
    }

    func isSelected(_ item: ReleaseCommitItem) -> Bool {
        !deselectedIDs.contains(item.id)
    }

    /// Rebuilds the list draft, so a paragraph from Claude or manual edits are replaced.
    func toggle(_ item: ReleaseCommitItem) {
        if deselectedIDs.contains(item.id) {
            deselectedIDs.remove(item.id)
        } else {
            deselectedIDs.insert(item.id)
        }
        rebuildDraft()
    }

    func setAllSelected(_ isSelected: Bool) {
        deselectedIDs = isSelected ? [] : Set(commits.map(\.id))
        rebuildDraft()
    }

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
        subjects = []
        commits = []
        deselectedIDs = []
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

        let loaded: [String]
        do {
            loaded = try await git.commitSubjects(
                at: repositoryPath,
                from: fromTag.isEmpty ? nil : fromTag,
                to: toRef
            )
        } catch {
            subjects = []
            fail(error.localizedDescription)
            return
        }

        subjects = loaded
        deselectedIDs = []
        guard !loaded.isEmpty else {
            fail("No commits in this range")
            return
        }
        applyCommitList()
    }

    private func applyCommitList() {
        commits = ReleaseNotesBuilder.items(from: subjects, includeTechnical: includeTechnical)
        guard !commits.isEmpty else {
            fail("Every commit in the range is technical — turn on \"Technical\"")
            return
        }
        rebuildDraft()
    }

    private func rebuildDraft() {
        draft = ReleaseNotesBuilder.draft(commits: commits.filter(isSelected).map(\.commit))
        report(nil, isError: false)
    }

    func generateWithClaude() async {
        isGenerating = true
        defer { isGenerating = false }
        report("Claude is writing the release notes…", isError: false)

        do {
            draft = try await generator.paragraph(from: draft, language: language, in: repositoryPath)
            report("Rewritten by Claude in \(language.title) — ticking a commit brings the list back", isError: false)
        } catch {
            report(error.localizedDescription, isError: true)
        }
    }

    /// A build failure clears the draft and the list: valid text from a previous range
    /// must not sit next to a red status.
    private func fail(_ message: String) {
        draft = ""
        commits = []
        report(message, isError: true)
    }

    private func report(_ message: String?, isError: Bool) {
        status = message
        self.isError = isError
    }
}
