//
//  MenuBarViewModel.swift
//  Toolbelt
//

import Observation
import SwiftUI

@Observable
@MainActor
final class MenuBarViewModel {
    private let profileStore: GitProfileStore
    private let gitConfig: GitConfigService
    private let derivedData: DerivedDataCleaning

    private(set) var activeProfileID: GitProfile.ID?
    private(set) var status = ""
    private(set) var isWorking = false

    var profiles: [GitProfile] { profileStore.profiles }

    init(
        profileStore: GitProfileStore = .shared,
        gitConfig: GitConfigService = SystemGitConfigService(),
        derivedData: DerivedDataCleaning = DerivedDataCleaner()
    ) {
        self.profileStore = profileStore
        self.gitConfig = gitConfig
        self.derivedData = derivedData
    }

    func refreshActiveProfile() async {
        do {
            let identity = try await gitConfig.currentIdentity()
            activeProfileID = profiles.first { $0.identity == identity }?.id
        } catch {
            activeProfileID = nil
            setStatus("⚠ Не удалось прочитать настройки git: \(error.localizedDescription)")
        }
    }

    func apply(_ profile: GitProfile) async {
        do {
            try await gitConfig.apply(profile.identity)
            activeProfileID = profile.id
            setStatus("✓ Применено: \(profile.name) <\(profile.email)>")
        } catch {
            setStatus("⚠ \(error.localizedDescription)")
        }
    }

    func cleanDerivedData() async {
        isWorking = true
        defer { isWorking = false }
        setStatus("Удаляем Derived Data…")

        do {
            switch try await derivedData.clean() {
            case .removed:
                setStatus("✓ Derived Data удалена")
            case .nothingToRemove:
                setStatus("Derived Data уже отсутствует")
            }
        } catch {
            setStatus("⚠ Не удалось удалить Derived Data: \(error.localizedDescription)")
        }
    }

    private func setStatus(_ text: String) {
        withAnimation { status = text }
    }
}
