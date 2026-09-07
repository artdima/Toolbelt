//
//  ReleaseNotesView.swift
//  Toolbelt
//
//  Preparing What's New for the App Store and Google Play from repository commits.
//

import SwiftUI

struct ReleaseNotesView: View {
    @State private var model = ReleaseNotesViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            repositoryRow
            rangeRow

            if let status = model.status {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(model.isError ? Color.red : Color.secondary)
            }

            Divider()

            Picker("", selection: $model.locale) {
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
            await model.reloadTags()
        }
    }

    private var repositoryRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Repository")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(model.hasRepository ? model.repositoryPath : "No folder selected")
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(model.hasRepository ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Choose…", action: chooseRepository)
            }
        }
    }

    private var rangeRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            labeled("From") {
                Picker("", selection: $model.fromTag) {
                    Text("Start of history").tag("")
                    ForEach(model.tags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                .labelsHidden()
            }

            labeled("To") {
                Picker("", selection: $model.toRef) {
                    Text(GitRepositoryService.headRef).tag(GitRepositoryService.headRef)
                    ForEach(model.tags, id: \.self) { tag in
                        Text(tag).tag(tag)
                    }
                }
                .labelsHidden()
            }

            Toggle("Technical", isOn: $model.includeTechnical)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("Include chore, refactor, docs, test, ci, build and style")

            if model.isLoadingTags || model.isBuilding {
                ProgressView().controlSize(.small)
            }

            Button("Build draft") {
                Task { await model.build() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.hasRepository || model.isBuilding)
        }
    }

    private func labeled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func editor(for store: StoreTarget, minHeight: CGFloat) -> some View {
        let text = model.draft(for: store)
        let isOverLimit = text.count > store.characterLimit

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(store.title)
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Text("\(text.count) / \(store.characterLimit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isOverLimit ? Color.red : Color.secondary)

                CopyButton(value: text, help: "Copy text")
            }

            TextEditor(text: binding(for: store))
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isOverLimit ? Color.red.opacity(0.6) : Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                }
                .frame(minHeight: minHeight)
        }
    }

    private func binding(for store: StoreTarget) -> Binding<String> {
        Binding(
            get: { model.draft(for: store) },
            set: { model.setDraft($0, for: store) }
        )
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.selectRepository(at: url.path)
    }
}

#Preview {
    ReleaseNotesView()
}
