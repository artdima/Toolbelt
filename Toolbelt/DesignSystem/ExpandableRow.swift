//
//  ExpandableRow.swift
//  Toolbelt
//
//  A list row with a "+ / −" button and collapsible details.
//

import SwiftUI

struct ExpandableRow<Leading: View, Trailing: View, Details: View>: View {
    private let isExpanded: Bool
    private let toggle: () -> Void
    private let leading: Leading
    private let trailing: Trailing
    private let details: Details

    init(
        isExpanded: Bool,
        toggle: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder details: () -> Details
    ) {
        self.isExpanded = isExpanded
        self.toggle = toggle
        self.leading = leading()
        self.trailing = trailing()
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { toggle() }
                } label: {
                    Image(systemName: isExpanded ? "minus" : "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide details" : "Show details")
                .padding(.top, 1)

                leading

                Spacer(minLength: 12)

                trailing
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)

            if isExpanded {
                details
                    .padding(.leading, 24)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
            }
        }
    }
}
