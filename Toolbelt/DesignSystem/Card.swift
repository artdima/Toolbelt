//
//  Card.swift
//  Toolbelt
//
//  A raised surface for grouped content inside a window.
//

import SwiftUI

extension View {
    /// In Dark mode the fill is a translucent lift rather than a fixed gray, so the
    /// card stays a step above the window whatever the system background is.
    func card(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(Color(.cardBackground), in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}
