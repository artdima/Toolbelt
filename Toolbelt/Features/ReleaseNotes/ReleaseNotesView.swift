//
//  ReleaseNotesView.swift
//  Toolbelt
//
//  Preparing What's New from repository commits.
//

import SwiftUI

struct ReleaseNotesView: View {
    @State private var model = ReleaseNotesViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls

            HStack(alignment: .top, spacing: 13) {
                commitsPane
                    .frame(width: 290)
                draftPane
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 20)
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle("Release Notes")
        .navigationSubtitle(model.hasRepository ? model.repositoryPath : "No repository selected")
        .toolbar { repositoryToolbar }
        .task {
            await model.reloadTags()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var repositoryToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            // A custom label: a Label in the toolbar gets its icon blown up to toolbar size.
            Button(action: chooseRepository) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                    Text("Choose…")
                        .font(.system(size: 13))
                }
            }
            .disabled(model.isGenerating)
            .help("Choose the repository")
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            rangeMenu("From", value: model.fromTag.isEmpty ? "Start of history" : model.fromTag, selection: $model.fromTag) {
                Text("Start of history").tag("")
                ForEach(model.tags, id: \.self) { tag in
                    Text(tag).tag(tag)
                }
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            rangeMenu("To", value: model.toRef, selection: $model.toRef) {
                Text(GitRepositoryService.headRef).tag(GitRepositoryService.headRef)
                ForEach(model.tags, id: \.self) { tag in
                    Text(tag).tag(tag)
                }
            }

            Divider()
                .frame(height: 22)

            languageMenu

            Toggle("Technical", isOn: $model.includeTechnical)
                .toggleStyle(.checkbox)
                .font(.system(size: 14))
                .disabled(model.isGenerating)
                .help("Include chore, refactor, docs, test, ci, build and style")

            Spacer(minLength: 8)

            if model.isLoadingTags || model.isBuilding {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await model.build() }
            } label: {
                Text("Build Draft")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.hasRepository || model.isBuilding || model.isGenerating)
        }
    }

    private func rangeMenu<Options: View>(
        _ title: String,
        value: String,
        selection: Binding<String>,
        @ViewBuilder options: () -> Options
    ) -> some View {
        Menu {
            Picker(title, selection: selection) {
                options()
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            PickerCard(height: 30) {
                HStack(spacing: 8) {
                    Text(title)
                        .foregroundStyle(.secondary)
                    Text(value)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!model.hasRepository || model.isLoadingTags)
    }

    private var languageMenu: some View {
        Menu {
            Picker("Language", selection: $model.language) {
                ForEach(ReleaseNotesLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            PickerCard(height: 30) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text(model.language.title)
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.isGenerating)
        .help("The language Claude writes the paragraph in")
    }

    // MARK: Commits

    private var commitsPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Commits")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !model.commits.isEmpty {
                    Text(verbatim: "\(model.selectedCount) of \(model.commits.count)")
                        .font(.system(size: 14))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if !model.commits.isEmpty {
                    Button(model.areAllSelected ? "Select None" : "Select All") {
                        model.setAllSelected(!model.areAllSelected)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .disabled(model.isGenerating)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)

            Divider()

            if model.commits.isEmpty {
                Text(commitsPlaceholder)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.commits.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider() }
                            commitRow(item)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .card()
    }

    private var commitsPlaceholder: String {
        if !model.hasRepository { return "Choose a repository to read its commits" }
        if model.isBuilding { return "Reading commits…" }
        return "Pick a range and press Build Draft"
    }

    private func commitRow(_ item: ReleaseCommitItem) -> some View {
        Toggle(isOn: Binding(
            get: { model.isSelected(item) },
            set: { _ in model.toggle(item) }
        )) {
            Text(item.commit.summary.capitalizedFirst)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .controlSize(.large)
        .disabled(model.isGenerating)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .help(item.subject)
    }

    // MARK: Draft

    private var draftPane: some View {
        let limit = ReleaseNotesBuilder.characterLimit
        let count = model.draft.count
        let isOverLimit = count > limit

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("What's New")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 8)
                if model.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task { await model.generateWithClaude() }
                } label: {
                    Label {
                        Text("Generate with Claude CLI")
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonBorderShape(.capsule)
                .disabled(!model.canGenerate)
                .help("Rewrite the list as one paragraph for users")

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.draft, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.draft.isEmpty)
                .help("Copy text")
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 40)

            Divider()

            TextEditor(text: $model.draft)
                .font(.system(size: 14))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 10)
                .disabled(model.isGenerating)
                .overlay(alignment: .topLeading) {
                    if model.draft.isEmpty {
                        Text("The What's New text appears here")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                draftStatus
                    .font(.system(size: 13))
                    .lineLimit(2)
                Spacer(minLength: 8)
                ShareBar(fraction: Double(count) / Double(limit), tint: isOverLimit ? .red : .accentColor)
                    .frame(width: 64)
                Text(verbatim: "\(count) / \(limit)")
                    .font(.system(size: 14))
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? Color.red : Color.primary)
                    .help("Google Play caps What's New at \(limit) characters")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
        }
        .card()
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.red.opacity(isOverLimit ? 0.6 : 0), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var draftStatus: some View {
        if let status = model.status {
            Text(status)
                .foregroundStyle(model.isError ? Color.red : Color.secondary)
        } else if !model.commits.isEmpty {
            Text(verbatim: "\(model.selectedCount) of \(model.subjects.count) commits in the draft")
                .foregroundStyle(.secondary)
        }
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
