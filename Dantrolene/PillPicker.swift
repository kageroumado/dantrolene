import SwiftUI

/// Layout constants at file scope — static stored properties aren't allowed in generic types.
private enum PillPickerLayout {
    static let highlightInset: CGFloat = 2
    static let dividerHeight: CGFloat = 12
}

/// A Safari-style capsule selector (Refrax's sidebar-footer pattern): equal-width segments
/// inside a glass capsule, a lilac pill sliding behind the selection, and hairline dividers
/// that fade out next to the selected segment. Used for the mode and display-sleep rows —
/// single-choice controls where a row of independent buttons over-states the options.
struct PillPicker<Value: Hashable>: View {
    let title: String
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var height: CGFloat = 30
    var font: Font = .callout

    private typealias Layout = PillPickerLayout

    private var selectedIndex: Int {
        options.firstIndex { $0.value == selection } ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            let dividers = CGFloat(options.count - 1)
            let segmentWidth = (proxy.size.width - dividers) / CGFloat(options.count)
            let stride = segmentWidth + 1

            ZStack(alignment: .leading) {
                highlightPill(segmentWidth: segmentWidth, stride: stride)
                segments(segmentWidth: segmentWidth)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
        }
        .frame(height: height)
        .glassEffect(.regular, in: Capsule())
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func highlightPill(segmentWidth: CGFloat, stride: CGFloat) -> some View {
        let inset = Layout.highlightInset
        return Capsule()
            .fill(Theme.active)
            .frame(width: segmentWidth - inset * 2, height: height - inset * 2)
            .offset(x: CGFloat(selectedIndex) * stride + inset)
    }

    private func segments(segmentWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(font.weight(index == selectedIndex ? .semibold : .regular))
                        .foregroundStyle(index == selectedIndex ? Theme.onActive : .primary)
                        .lineLimit(1)
                        .frame(width: segmentWidth, height: height)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if index < options.count - 1 {
                    divider(at: index)
                }
            }
        }
    }

    private func divider(at index: Int) -> some View {
        let adjacentToSelected = index == selectedIndex || index + 1 == selectedIndex
        return Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: Layout.dividerHeight)
            .opacity(adjacentToSelected ? 0 : 1)
    }
}
