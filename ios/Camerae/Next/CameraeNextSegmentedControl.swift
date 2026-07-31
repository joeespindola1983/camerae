import SwiftUI

struct CameraeNextSegmentItem<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var systemImage: String? = nil

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
                    Group {
                        if let systemImage = item.systemImage {
                            Label(item.label, systemImage: systemImage)
                        } else {
                            Text(item.label)
                        }
                    }
                        .font(.custom("Outfit-SemiBold", size: height >= 38 ? 13 : 12, relativeTo: .body))
                        .foregroundStyle(selection == item.value ? Color.white : theme.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Capsule())
                        .background(
                            selection == item.value ? theme.accent : theme.surface,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("camerae.segment.\(String(describing: item.value))")
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
    case photo
    case video
    case timelapse
    case automatic
    case manual

    static var repeatableItems: [CameraeNextSegmentItem<Self>] { [
        CameraeNextSegmentItem(value: Self.photo, label: CameraeL10n.photo, systemImage: "camera.fill"),
        CameraeNextSegmentItem(value: Self.video, label: CameraeL10n.video, systemImage: "video.fill"),
        CameraeNextSegmentItem(value: Self.timelapse, label: CameraeL10n.timelapse, systemImage: "timelapse"),
    ] }

    static var astroItems: [CameraeNextSegmentItem<Self>] { [
        CameraeNextSegmentItem(value: Self.photo, label: CameraeL10n.photo, systemImage: "camera.fill"),
        CameraeNextSegmentItem(value: Self.video, label: CameraeL10n.video, systemImage: "video.fill"),
        CameraeNextSegmentItem(value: Self.timelapse, label: CameraeL10n.timelapse, systemImage: "timelapse")
    ] }
}

struct CameraeNextProjectCaptureCapabilityPolicy: Equatable, Sendable {
    let availableCaptureKinds: [RepeatableCaptureKind]
    let locksCameraHardware: Bool
    let allowsEditingCaptureDefaults: Bool

    static let repeatable = Self(
        availableCaptureKinds: [.photo, .video, .timelapse],
        locksCameraHardware: true,
        allowsEditingCaptureDefaults: true
    )
}
