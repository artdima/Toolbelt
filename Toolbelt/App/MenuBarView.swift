//
//  MenuBarView.swift
//  Toolbelt
//
//  Панель приложения в строке меню.
//

import SwiftUI

struct MenuBarView: View {
    @State private var model = MenuBarViewModel()
    @State private var isConfirmingDerivedDataCleanup = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 18) {
            header
            profiles
            tools
            footer
        }
        .padding(16)
        .frame(width: 330)
        .environment(\.colorScheme, .dark)
        .background(MenuBarPanelReader().frame(width: 0, height: 0))
        .task {
            await model.refreshActiveProfile()
        }
        .onChange(of: model.profiles) { _, _ in
            Task { await model.refreshActiveProfile() }
        }
        .confirmationDialog(
            "Удалить Derived Data?",
            isPresented: $isConfirmingDerivedDataCleanup
        ) {
            Button("Удалить", role: .destructive) {
                Task { await model.cleanDerivedData() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все проекты придётся собрать заново — это может занять время.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
            Text("Toolbelt")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                AppWindows.settings()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Настройки")
        }
    }

    @ViewBuilder
    private var profiles: some View {
        if model.profiles.isEmpty {
            ToolButton(title: "Добавить профиль Git", systemImage: "person.crop.circle.badge.plus") {
                AppWindows.settings(tab: .profiles)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(model.profiles) { profile in
                    Button {
                        Task { await model.apply(profile) }
                    } label: {
                        profileCard(profile)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func profileCard(_ profile: GitProfile) -> some View {
        let isActive = model.activeProfileID == profile.id

        return VStack(alignment: .leading, spacing: 6) {
            Text(profile.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Text(profile.email)
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isActive ? .white.opacity(0.72) : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(isActive ? Color.accentColor.opacity(0.88) : Color.white.opacity(0.07))
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tools: some View {
        VStack(spacing: 8) {
            ToolButton(title: "Получить отчёт за неделю", systemImage: "chart.bar.doc.horizontal") {
                AppWindows.weeklyReport()
            }
            ToolButton(title: "Мои задачи", systemImage: "square.grid.3x2") {
                AppWindows.issuesBoard()
            }
            ToolButton(title: "Deep Link", systemImage: "link") {
                AppWindows.deepLink()
            }
            ToolButton(title: "Release Notes", systemImage: "doc.text") {
                AppWindows.releaseNotes()
            }
            ToolButton(title: "Удалить Derived Data", systemImage: "trash", isDestructive: true) {
                isConfirmingDerivedDataCleanup = true
            }
            .disabled(model.isWorking)
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if model.status.isEmpty {
                Spacer(minLength: 0)
            } else {
                Text(model.status)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.07))
                    .foregroundStyle(.secondary)
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Завершить Toolbelt")
        }
    }
}

#Preview {
    MenuBarView()
}
