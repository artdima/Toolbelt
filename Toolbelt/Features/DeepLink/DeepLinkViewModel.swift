//
//  DeepLinkViewModel.swift
//  Toolbelt
//

import Observation
import SwiftUI

@Observable
@MainActor
final class DeepLinkViewModel {
    private let runner: DeepLinkOpening
    let history: DeepLinkHistoryStore

    var url = ""
    var selectedTargetID: DeepLinkTarget.ID = ""

    private(set) var targets: [DeepLinkTarget] = []
    private(set) var warning: String?
    private(set) var result: DeepLinkResult?
    private(set) var isLoadingTargets = false
    private(set) var isOpening = false

    init(
        runner: DeepLinkOpening = DeepLinkRunner(),
        history: DeepLinkHistoryStore = .shared
    ) {
        self.runner = runner
        self.history = history
    }

    var selectedTarget: DeepLinkTarget? {
        targets.first { $0.id == selectedTargetID }
    }

    var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canOpen: Bool {
        !trimmedURL.isEmpty && selectedTarget != nil && !isOpening
    }

    var showsSchemeHint: Bool {
        !trimmedURL.isEmpty && !trimmedURL.contains("://")
    }

    func reloadTargets() async {
        isLoadingTargets = true
        defer { isLoadingTargets = false }

        let loaded = await runner.targets()
        targets = loaded.targets
        warning = loaded.warning

        if !targets.contains(where: { $0.id == selectedTargetID }) {
            selectedTargetID = targets.first?.id ?? ""
        }
    }

    func open() async {
        guard canOpen, let target = selectedTarget else { return }
        let link = trimmedURL

        isOpening = true
        defer { isOpening = false }

        let outcome = await runner.open(url: link, on: target)
        result = outcome

        if outcome.isSuccess {
            history.record(link)
        }
    }
}
