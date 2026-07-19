import SwiftUI

struct CameraeNextSegmentItem<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    var id: Value { value }
}

struct CameraeNextSegmentedControlModel<Value: Hashable> {
    let items: [CameraeNextSegmentItem<Value>]
    let selection: Value

    var selectedIndex: Int? { items.firstIndex { $0.value == selection } }
}

struct CameraeNextSegmentedControl<Value: Hashable>: View {
    let items: [CameraeNextSegmentItem<Value>]
    @Binding var selection: Value
    let theme: CameraeNextTheme
    var height: CGFloat = 38

    var body: some View {
        HStack(spacing: 3) {
            ForEach(items) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = item.value
                    }
                } label: {
                    Text(item.label)
                        .font(.custom("Outfit-Regular", size: height >= 38 ? 14 : 12, relativeTo: .body))
                        .foregroundStyle(selection == item.value ? Color.white : theme.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Capsule())
                        .background(
                            selection == item.value ? theme.accent : theme.surface,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item.value ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: height)
        .background(theme.surface, in: Capsule())
        .overlay {
            Capsule().stroke(theme.border, lineWidth: 1)
        }
    }
}

enum CameraeNextCaptureModeOption: String, Hashable, Sendable {
    case video
    case timelapse
    case automatic
    case manual

    static let repeatableItems = [
        CameraeNextSegmentItem(value: Self.video, label: "Vídeo"),
        CameraeNextSegmentItem(value: Self.timelapse, label: "Timelapse")
    ]

    static let astroItems = [
        CameraeNextSegmentItem(value: Self.automatic, label: "Automática"),
        CameraeNextSegmentItem(value: Self.manual, label: "Manual")
    ]
}
