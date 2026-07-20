import SwiftUI

struct CameraeNextTheme: Equatable, Sendable {
    let workflow: CameraeWorkflowTheme

    var background: Color {
        switch workflow {
        case .repeatable: CameraeColor.repeatableLightBackground
        case .astro: CameraeColor.astroDarkBackground
        case .editor: CameraeColor.canvas
        }
    }

    var card: Color {
        switch workflow {
        case .repeatable: CameraeColor.repeatableLightCard
        case .astro: CameraeColor.astroDarkCard
        case .editor: CameraeColor.surface
        }
    }

    var surface: Color {
        switch workflow {
        case .repeatable: CameraeColor.repeatableLightSurface
        case .astro: CameraeColor.astroDarkSurface
        case .editor: CameraeColor.overlayCard
        }
    }

    var text: Color {
        switch workflow {
        case .repeatable: CameraeColor.repeatableLightText
        case .astro: CameraeColor.astroDarkText
        case .editor: CameraeColor.textPrimary
        }
    }

    var muted: Color {
        switch workflow {
        case .repeatable: CameraeColor.repeatableLightMuted
        case .astro: CameraeColor.astroDarkMuted
        case .editor: CameraeColor.textMuted
        }
    }

    var border: Color {
        switch workflow {
        case .repeatable: CameraeColor.repeatableLightBorder
        case .astro: CameraeColor.astroDarkBorder
        case .editor: CameraeColor.borderStrong
        }
    }

    var accent: Color { workflow.accent }
    var colorScheme: ColorScheme { workflow == .repeatable ? .light : .dark }
}

struct CameraeNextCard<Content: View>: View {
    let theme: CameraeNextTheme
    private let content: Content

    init(theme: CameraeNextTheme, @ViewBuilder content: () -> Content) {
        self.theme = theme
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(theme.card, in: RoundedRectangle(cornerRadius: CameraeRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CameraeRadius.large, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
    }
}

struct CameraeNextActionButton: View {
    let title: String
    let systemImage: String?
    let theme: CameraeNextTheme
    var style = Style.primary
    var isBusy = false
    var isDisabled = false
    let action: () -> Void

    enum Style: Sendable {
        case primary
        case secondary
        case quiet
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .body))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(background, in: Capsule())
            .overlay {
                if style == .secondary {
                    Capsule()
                        .stroke(theme.border, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isBusy)
        .opacity(isDisabled ? 0.5 : 1)
    }

    private var foreground: Color {
        switch style {
        case .primary: .white
        case .secondary, .quiet: theme.text
        }
    }

    private var background: Color {
        switch style {
        case .primary: theme.accent
        case .secondary: theme.surface
        case .quiet: .clear
        }
    }
}

struct CameraeNextSliderRow<Control: View>: View {
    let title: String
    let value: String
    let theme: CameraeNextTheme
    private let control: Control

    init(
        title: String,
        value: String,
        theme: CameraeNextTheme,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.value = value
        self.theme = theme
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(theme.text)
                .fixedSize()
            control
                .tint(theme.accent)
            Text(value)
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: 34)
    }
}

struct CameraeNextSectionLabel: View {
    let title: String
    let theme: CameraeNextTheme

    var body: some View {
        Text(title.uppercased())
            .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
            .tracking(1.5)
            .foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CameraeNextSettingRow<Control: View>: View {
    let title: String
    let helper: String?
    let theme: CameraeNextTheme
    private let control: Control

    init(
        title: String,
        helper: String? = nil,
        theme: CameraeNextTheme,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.helper = helper
        self.theme = theme
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                if let helper {
                    Text(helper)
                        .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.muted)
                }
            }
            Spacer(minLength: 8)
            control
                .tint(theme.accent)
        }
        .frame(minHeight: 52)
    }
}

struct CameraeNextCameraSelector: View {
    @Binding var selection: RepeatableCameraLens
    let theme: CameraeNextTheme
    var availableLenses = RepeatableCameraLens.allCases

    var body: some View {
        CameraeNextCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Câmera")
                    .font(.custom("Outfit-Medium", size: 15, relativeTo: .body))
                    .foregroundStyle(theme.text)

                HStack(spacing: 8) {
                    lensButton(.ultraWide, value: "0,5×", label: "Ultra-wide", symbol: "camera.macro")
                    lensButton(.wide, value: "1×", label: "Principal", symbol: "camera")
                    lensButton(.telephoto, value: "TELE", label: "Teleobjetiva", symbol: "scope")
                }
            }
        }
    }

    private func lensButton(
        _ lens: RepeatableCameraLens,
        value: String,
        label: String,
        symbol: String
    ) -> some View {
        let selected = selection == lens
        let isAvailable = availableLenses.contains(lens)
        return Button { selection = lens } label: {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                Text(value)
                    .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .subheadline))
                Text(label)
                    .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(selected ? Color.white : theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(selected ? theme.accent : theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? theme.accent : theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.38)
        .accessibilityLabel("Câmera \(label)")
        .accessibilityHint(isAvailable ? "" : "Indisponível neste aparelho")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CameraeNextCameraStatus: View {
    let lens: String
    let zoom: String
    let theme: CameraeNextTheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Câmera em uso")
                    .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
                Text("\(lens) · \(zoom)")
                    .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
            }

            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.muted)
                .frame(width: 32, height: 32)
        }
        .padding(12)
        .frame(height: 72)
        .background(theme.card, in: RoundedRectangle(cornerRadius: CameraeRadius.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Câmera em uso, \(lens), \(zoom), bloqueada")
    }
}
