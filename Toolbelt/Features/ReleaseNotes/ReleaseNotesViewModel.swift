//
//  ReleaseNotesViewModel.swift
//  Toolbelt
//

import Observation
import SwiftUI

@Observable
@MainActor
final class ReleaseNotesViewModel {
    struct DraftKey: Hashable {
        let locale: NoteLocale
        let store: StoreTarget
    }

    private static let repositoryPathKey = "releaseNotes.repositoryPath"

    private let git: GitRepositoryReading
    private let defaults: UserDefaults

    private(set) var repositoryPath: String
    private(set) var tags: [String] = []
    private(set) var status: String?
    private(set) var isError = false
    private(set) var isLoadingTags = false
    private(set) var isBuilding = false

    var fromTag = ""
    var toRef = GitRepositoryService.headRef
    var includeTechnical = false
    var locale: NoteLocale = .en

    private var drafts: [DraftKey: String] = [:]
    private var reloadTagsTask: Task<Void, Never>?

    convenience init() {
        self.init(git: GitRepositoryService(), defaults: .standard)
    }

    init(git: GitRepositoryReading, defaults: UserDefaults) {
        self.git = git
        self.defaults = defaults
        repositoryPath = defaults.string(forKey: Self.repositoryPathKey) ?? ""
    }

    var hasRepository: Bool { !repositoryPath.isEmpty }

    func draft(for store: StoreTarget) -> String {
        drafts[DraftKey(locale: locale, store: store)] ?? ""
    }

    func setDraft(_ text: String, for store: StoreTarget) {
        drafts[DraftKey(locale: locale, store: store)] = text
    }

    func selectRepository(at path: String) {
        repositoryPath = path
        defaults.set(path, forKey: Self.repositoryPathKey)
        drafts.removeAll()
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

        // Drafts are built for both locales at once: otherwise switching the language
        // would show empty fields next to a non-empty status.
        for noteLocale in NoteLocale.allCases {
            for store in StoreTarget.allCases {
                drafts[DraftKey(locale: noteLocale, store: store)] = ReleaseNotesBuilder.draft(
                    commits: commits,
                    locale: noteLocale,
                    store: store
                )
            }
        }

        report("\(commits.count) of \(subjects.count) commits in the draft", isError: false)
    }

    /// A build failure clears the drafts: valid text from a previous range must not
    /// sit next to a red status.
    private func fail(_ message: String) {
        drafts.removeAll()
        report(message, isError: true)
    }

    private func report(_ message: String?, isError: Bool) {
        status = message
        self.isError = isError
    }
}
