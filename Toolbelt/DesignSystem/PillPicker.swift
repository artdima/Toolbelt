//
//  PillPicker.swift
//  Toolbelt
//
//  Tabs as a pill sliding along a track. The system segmented control tints the
//  selected segment with the accent color on macOS 26; the design keeps it neutral.
//

import SwiftUI

struct PillPicker<Value: Hashable>: View {
    @Binding private var selection: Value
    private let options: [Value]
    private let title: (Value) -> String

    @Namespace private var namespace

    init(selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.title = title
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection

                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 22)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color(.selectedSegment))
                                    .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.065), in: Capsule())
        .fixedSize()
    }
}
