//
//  DeepLinkView.swift
//  Toolbelt
//
//  Окно проверки deep link: ссылка + выбор устройства + результат команды.
//

import SwiftUI

enum DeepLinkWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            DockPresence.activate()
            return
        }

        DockPresence.retain()

        let hosting = NSHostingController(rootView: DeepLinkView())
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Deep Link"
        newWindow.setContentSize(NSSize(width: 560, height: 560))
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

struct DeepLinkView: View {
    private let history = DeepLinkHistoryStore.shared

    @State private var url = ""
    @State private var targets: [DeepLinkTarget] = []
    @State private var selection: DeepLinkTarget.ID = ""
    @State private var warning: String?
    @State private var isLoadingTargets = false
    @State private var isOpening = false
    @State private var result: DeepLinkResult?

    private var selectedTarget: DeepLinkTarget? {
        targets.first { $0.id == selection }
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canOpen: Bool {
        !trimmedURL.isEmpty && selectedTarget != nil && !isOpening
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            devicePicker

            if let warning {
                Text("⚠ \(warning)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            linkField

            if let result {
                resultCard(result)
            }

            historySection
        }
        .padding(18)
        .frame(minWidth: 520, minHeight: 460)
        .task {
            await reloadTargets()
        }
    }

    // MARK: Устройство

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Устройство")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if targets.isEmpty {
                    Text("Нет загруженных симуляторов и подключённых устройств")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker("", selection: $selection) {
                        ForEach(targets) { target in
                            Text("\(target.platform.title) · \(target.name)").tag(target.id)
                        }
                    }
                    .labelsHidden()
                }

                if isLoadingTargets {
                    ProgressView().controlSize(.small)
                }

                Button {
                    Task { await reloadTargets() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(isLoadingTargets)
                .help("Обновить список устройств")
            }
        }
    }

    // MARK: Ссылка

    private var linkField: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Ссылка")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("myapp://profile/123", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit { Task { await open() } }

                Button("Открыть") {
                    Task { await open() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canOpen)
            }

            if !trimmedURL.isEmpty && !trimmedURL.contains("://") {
                Text("В ссылке нет схемы — обычно нужно что-то вида myapp://path")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Результат

    private func resultCard(_ result: DeepLinkResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.isSuccess ? .green : .red)
                Text(result.isSuccess ? "Ссылка отправлена" : "Не удалось открыть")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Скопировать команду")
            }

            Text(result.command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !result.output.isEmpty {
                Text(result.output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: История

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("История")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if history.entries.isEmpty {
                Text("Открытые ссылки будут сохраняться здесь")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(sortedHistory) { entry in
                            historyRow(entry)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sortedHistory: [DeepLinkEntry] {
        history.entries.filter(\.isPinned) + history.entries.filter { !$0.isPinned }
    }

    private func historyRow(_ entry: DeepLinkEntry) -> some View {
        HStack(spacing: 8) {
            Button {
                history.togglePin(entry)
            } label: {
                Image(systemName: entry.isPinned ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.isPinned ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(entry.isPinned ? "Открепить" : "Закрепить")

            Button {
                url = entry.url
            } label: {
                Text(entry.url)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Подставить в поле ввода")

            Button {
                history.remove(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("Удалить из истории")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Действия

    private func reloadTargets() async {
        isLoadingTargets = true
        defer { isLoadingTargets = false }

        let loaded = await DeepLinkRunner.loadTargets()
        targets = loaded.targets
        warning = loaded.warning

        if !targets.contains(where: { $0.id == selection }) {
            selection = targets.first?.id ?? ""
        }
    }

    private func open() async {
        guard canOpen, let target = selectedTarget else { return }
        let link = trimmedURL

        isOpening = true
        defer { isOpening = false }

        let outcome = await DeepLinkRunner.open(url: link, on: target)
        result = outcome

        if outcome.isSuccess {
            history.record(link)
        }
    }
}

#Preview {
    DeepLinkView()
}
