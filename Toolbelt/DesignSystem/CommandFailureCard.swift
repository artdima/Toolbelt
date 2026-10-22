//
//  CommandFailureCard.swift
//  Toolbelt
//
//  A command-line tool that failed: what was run and what it printed.
//

import SwiftUI

struct CommandFailureCard: View {
    let title: String
    let command: String
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if !command.isEmpty {
                    CopyButton(value: command, help: "Copy command")
                }
            }

            if !command.isEmpty {
                Text(verbatim: command)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !output.isEmpty {
                Text(verbatim: output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .card()
    }
}
