//
//  UserDefaultsRow.swift
//  Toolbelt
//
//  One key of the defaults table: its type, its name and an editable value.
//

import SwiftUI

struct UserDefaultsRow: View {
    @Bindable var model: UserDefaultsViewModel
    let entry: UserDefaultsEntry
    var focusedKey: FocusState<String?>.Binding

    @State private var isHovered = false

    private let valueFont = Font.system(size: 13, design: .monospaced)

    var body: some View {
        HStack(spacing: 14) {
            UserDefaultsTypeBadge(value: entry.value)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.key)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.key)
                Text(entry.value.typeName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 248, alignment: .leading)

            valueCell
                .frame(maxWidth: .infinity, alignment: .leading)

            actions
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy Key") { copy(entry.key) }
            Button("Copy Value") { copy(entry.value.display) }
            Divider()
            Button("Delete Key", role: .destructive) {
                Task { await model.delete(entry) }
            }
        }
    }

    @ViewBuilder
    private var valueCell: some View {
        switch entry.value {
        case let .bool(isOn):
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in Task { await model.set(entry, to: .bool(newValue)) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

        case .string, .integer, .double:
            if model.editingKey == entry.key {
                TextField("", text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .font(valueFont)
                    .foregroundStyle(model.isDraftValid ? Color.primary : Color.red)
                    .focused(focusedKey, equals: entry.key)
                    .onSubmit { Task { await model.commitEditing() } }
                    .onExitCommand { model.cancelEditing() }
            } else {
                Button {
                    model.beginEditing(entry)
                } label: {
                    Text(entry.value.display.isEmpty ? "empty" : entry.value.display)
                        .font(valueFont)
                        .foregroundStyle(entry.value.display.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to edit")
            }

        case .date, .data, .array, .dictionary:
            Text(entry.value.display)
                .font(valueFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(entry.value.display)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            CopyButton(value: entry.value.display, help: "Copy value")

            Button {
                Task { await model.delete(entry) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete key")
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

struct UserDefaultsTypeBadge: View {
    let value: UserDefaultsValue

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.08))
            glyph
                .foregroundStyle(.secondary)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch value {
        case .data:
            Text(verbatim: "101")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
        case .string:
            symbol("quote.closing")
        case .integer, .double:
            symbol("number")
        case .bool:
            symbol("switch.2")
        case .date:
            symbol("calendar")
        case .array:
            symbol("list.bullet")
        case .dictionary:
            symbol("curlybraces")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .medium))
    }
}
