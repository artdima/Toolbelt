//
//  WorklogCommentEditor.swift
//  Toolbelt
//
//  A sheet for rewriting the comment of a logged time entry.
//

import SwiftUI

struct WorklogCommentEditor: View {
    let entry: Worklog
    let save: (String) async -> TrackerFailure?

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var failure: TrackerFailure?
    @FocusState private var isFocused: Bool

    init(entry: Worklog, save: @escaping (String) async -> TrackerFailure?) {
        self.entry = entry
        self.save = save
        _text = State(initialValue: entry.comment ?? "")
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedText != (entry.comment ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit Comment")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            header
                .padding(.top, 8)

            field
                .padding(.top, 12)

            if let failure {
                ErrorBanner(text: failure.message, details: failure.details)
                    .padding(.top, 10)
            }

            buttons
                .padding(.top, 16)
        }
        .padding(20)
        .frame(width: 400)
        .interactiveDismissDisabled(isSaving)
        .onAppear { isFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.issueKey)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.accentColor)

                if !entry.issueTitle.isEmpty {
                    Text(entry.issueTitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(entry.issueTitle)
                }
            }

            Text(verbatim: subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return TextField("No comment", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineLimit(3...8)
            .focused($isFocused)
            .disabled(isSaving)
            .onSubmit(submit)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(isFocused ? 0.25 : 0.12)))
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }

            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)

            Button("Save", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(!hasChanges || isSaving)
        }
    }

    private var subtitle: String {
        let day = AppFormatters.weekdayAndDay.string(from: entry.start)
        let time = AppFormatters.time.string(from: entry.start)
        return "\(day) · \(time) · \(DurationFormatter.short(entry.seconds))"
    }

    private func submit() {
        guard hasChanges, !isSaving else { return }
        isSaving = true
        failure = nil

        Task {
            failure = await save(trimmedText)
            isSaving = false
            if failure == nil {
                dismiss()
            } else {
                isFocused = true
            }
        }
    }
}

#Preview {
    WorklogCommentEditor(
        entry: Worklog(
            id: 1,
            issueKey: "MOB-142",
            issueTitle: "Offline mode for the cart",
            comment: "Synced the cart with the local store",
            start: Date(),
            seconds: 9000
        ),
        save: { _ in nil }
    )
}
