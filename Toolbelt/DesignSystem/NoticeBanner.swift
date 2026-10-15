//
//  NoticeBanner.swift
//  Toolbelt
//
//  A tinted note under the content: a hint, a warning, optionally dismissable.
//

import SwiftUI

struct NoticeBanner<Message: View>: View {
    private let systemImage: String
    private let tint: Color
    private let onClose: (() -> Void)?
    private let message: Message

    init(
        systemImage: String,
        tint: Color,
        onClose: (() -> Void)? = nil,
        @ViewBuilder message: () -> Message
    ) {
        self.systemImage = systemImage
        self.tint = tint
        self.onClose = onClose
        self.message = message()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            message
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension Text {
    /// Code inside a sentence: monospaced, at the size of the surrounding text.
    static func code(_ value: String) -> Text {
        Text(verbatim: value).monospaced()
    }
}
