//
//  IssuesBoardViewModel.swift
//  Toolbelt
//

import Observation
import SwiftUI

@Observable
@MainActor
final class IssuesBoardViewModel {
    private let tracker: TrackerService
    private let credentialsStore: TrackerCredentialsStore

    private(set) var issues: [Issue] = []
    private(set) var board = IssuesBoard.empty
    private(set) var errorMessage: String?

    private var inFlightCount = 0
    private var loadTask: Task<Void, Never>?

    var includeResolved = false
    /// Пересборка вызывается из вью по .onChange: макрос @Observable переписывает
    /// хранимые свойства в вычисляемые, и срабатывание didSet не гарантировано.
    var searchQuery = ""

    init(
        tracker: TrackerService = TrackerClient(),
        credentialsStore: TrackerCredentialsStore = .shared
    ) {
        self.tracker = tracker
        self.credentialsStore = credentialsStore
    }

    var isLoading: Bool { inFlightCount > 0 }
    var credentials: TrackerCredentials { credentialsStore.credentials }
    var isConfigured: Bool { credentials.isConfigured }
    var hasLoadedIssues: Bool { !issues.isEmpty }

    var summary: String {
        let issues = Plural.counted(board.issueCount, "задача", "задачи", "задач")
        let columns = Plural.counted(board.columns.count, "статусе", "статусах", "статусах")
        return "\(issues) в \(columns)"
    }

    func reload() async {
        loadTask?.cancel()
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        guard isConfigured else {
            issues = []
            rebuildBoard()
            return
        }

        let requestedIncludeResolved = includeResolved

        inFlightCount += 1
        errorMessage = nil
        defer { inFlightCount -= 1 }

        do {
            let loaded = try await tracker.myIssues(includeResolved: requestedIncludeResolved)
            try Task.checkCancellation()
            guard requestedIncludeResolved == includeResolved else { return }
            issues = loaded
            rebuildBoard()
        } catch is CancellationError {
            // Запрос вытеснен более свежим.
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rebuildBoard() {
        board = IssuesBoard(issues: issues, searchQuery: searchQuery)
    }
}
