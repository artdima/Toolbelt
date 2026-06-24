//
//  ReleaseNotesView.swift
//  Toolbelt
//
//  Окно подготовки What's New: диапазон коммитов → черновики для двух площадок.
//

import SwiftUI

enum ReleaseNotesWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            DockPresence.activate()
            return
        }

        DockPresence.retain()

        let hosting = NSHostingController(rootView: ReleaseNotesView())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Release Notes"
        newWindow.setContentSize(NSSize(width: 620, height: 680))
        newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        window = newWindow

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { _ in
            window = nil
            DockPresence.release()
        }

        newWindow.makeKeyAndOrderFront(nil)
        DockPresence.activate()
    }
}

private struct DraftKey: Hashable {
    let locale: NoteLocale
    let store: StoreTarget
}

struct ReleaseNotesView: View {
    @State private var repositoryPath = GitRepository.lastPath
    @State private var tags: [String] = []
    @State private var fromTag = ""
    @State private var toRef = "HEAD"
    @State private var includeTechnical = false
    @State private var locale: NoteLocale = .ru
    @State private var drafts: [DraftKey: String] = [:]
    @State private var status: String?
    @State private var isError = false
    @State private var isLoadingTags = false
    @State private var isBuilding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            repositoryRow
            rangeRow

            if let status {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(isError ? Color.red : Color.secondary)
            }

            Divider()

            Picker("", selection: $locale) {
                ForEach(NoteLocale.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            editor(for: .appStore, minHeight: 200)
            editor(for: .googlePlay, minHeight: 110)
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 600)
        .task {
            await reloadTags()
        }
    }

    // MARK: Репозиторий

    private var repositoryRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Репозиторий")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(repositoryPath.isEmpty ? "Папка не выбрана" : repositoryPath)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(repositoryPath.isEmpty ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Выбрать…") { chooseRepository() }
            }
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        repositoryPath = url.path
        GitRepository.lastPath = url.path
        drafts.removeAll()
        status = nil
        isError = false
        Task { await reloadTags() }
    }

    // MARK: Диапазон

    private var rangeRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("От")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $fromTag) {
                    Text("начало истории").tag("")
                    ForEach(tags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("До")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: $toRef) {
                    Text("HEAD").tag("HEAD")
                    ForEach(tags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                .labelsHidden()
            }

            Toggle("Технические", isOn: $includeTechnical)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Включить chore, refactor, docs, test, ci, build и style")

            if isLoadingTags || isBuilding {
                ProgressView().controlSize(.small)
            }

            Button("Собрать черновик") {
                Task { await build() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(repositoryPath.isEmpty || isBuilding)
        }
    }

    // MARK: Редакторы

    private func editor(for store: StoreTarget, minHeight: CGFloat) -> some View {
        let text = drafts[DraftKey(locale: locale, store: store)] ?? ""
        let isOverLimit = text.count > store.limit

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(store.title)
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Text("\(text.count) / \(store.limit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isOverLimit ? Color.red : Color.secondary)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(text.isEmpty)
                .help("Скопировать текст")
            }

            TextEditor(text: binding(for: store))
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isOverLimit ? Color.red.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: 1)
                }
                .frame(minHeight: minHeight)
        }
    }

    private func binding(for store: StoreTarget) -> Binding<String> {
        let key = DraftKey(locale: locale, store: store)
        return Binding(
            get: { drafts[key] ?? "" },
            set: { drafts[key] = $0 }
        )
    }

    // MARK: Действия

    private func reloadTags() async {
        guard !repositoryPath.isEmpty else {
            tags = []
            fromTag = ""
            toRef = "HEAD"
            return
        }

        isLoadingTags = true
        defer { isLoadingTags = false }

        guard await GitRepository.isRepository(repositoryPath) else {
            tags = []
            status = "В выбранной папке нет git-репозитория"
            isError = true
            return
        }

        tags = await GitRepository.tags(at: repositoryPath)
        status = tags.isEmpty ? "Тегов нет — доступна вся история" : nil
        isError = false

        if !tags.contains(fromTag) {
            fromTag = ""
        }
        if toRef != "HEAD" && !tags.contains(toRef) {
            toRef = "HEAD"
        }
    }

    private func build() async {
        isBuilding = true
        defer { isBuilding = false }

        let loaded = await GitRepository.subjects(
            at: repositoryPath,
            from: fromTag.isEmpty ? nil : fromTag,
            to: toRef
        )

        if let error = loaded.error {
            drafts.removeAll()
            status = error
            isError = true
            return
        }

        guard !loaded.subjects.isEmpty else {
            drafts.removeAll()
            status = "В этом диапазоне нет коммитов"
            isError = true
            return
        }

        let commits = ReleaseNotesBuilder.commits(
            from: loaded.subjects,
            includeTechnical: includeTechnical
        )

        guard !commits.isEmpty else {
            drafts.removeAll()
            status = "Все коммиты диапазона технические — включите «Технические»"
            isError = true
            return
        }

        for noteLocale in NoteLocale.allCases {
            for store in StoreTarget.allCases {
                drafts[DraftKey(locale: noteLocale, store: store)] = ReleaseNotesBuilder.draft(
                    commits: commits,
                    locale: noteLocale,
                    store: store
                )
            }
        }

        status = "В черновике \(commits.count) из \(loaded.subjects.count) коммитов"
        isError = false
    }
}

#Preview {
    ReleaseNotesView()
}
