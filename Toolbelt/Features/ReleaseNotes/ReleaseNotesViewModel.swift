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
    var locale: NoteLocale = .ru

    private var drafts: [DraftKey: String] = [:]
    private var reloadTagsTask: Task<Void, Never>?

    init(
        git: GitRepositoryReading = GitRepositoryService(),
        defaults: UserDefaults = .standard
    ) {
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
        // Путь фиксируется до первого await: пользователь может выбрать другой
        // репозиторий, пока git ещё отвечает.
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
            report("В выбранной папке нет git-репозитория", isError: true)
            return
        }

        let loaded = (try? await git.tags(at: path)) ?? []
        guard path == repositoryPath else { return }

        tags = loaded
        if loaded.isEmpty {
            report("Тегов нет — доступна вся история", isError: false)
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
            fail("В этом диапазоне нет коммитов")
            return
        }

        let commits = ReleaseNotesBuilder.commits(from: subjects, includeTechnical: includeTechnical)
        guard !commits.isEmpty else {
            fail("Все коммиты диапазона технические — включите «Технические»")
            return
        }

        // Черновики строятся сразу для обеих локалей: иначе переключение языка
        // показывало бы пустые поля при непустом статусе.
        for noteLocale in NoteLocale.allCases {
            for store in StoreTarget.allCases {
                drafts[DraftKey(locale: noteLocale, store: store)] = ReleaseNotesBuilder.draft(
                    commits: commits,
                    locale: noteLocale,
                    store: store
                )
            }
        }

        report("В черновике \(commits.count) из \(subjects.count) коммитов", isError: false)
    }

    /// Ошибка сборки очищает черновики: рядом с красным статусом не должен
    /// оставаться валидный текст от прошлого диапазона.
    private func fail(_ message: String) {
        drafts.removeAll()
        report(message, isError: true)
    }

    private func report(_ message: String?, isError: Bool) {
        status = message
        self.isError = isError
    }
}
