import SwiftUI

enum CameraeNextGridPickerPresentation {
    static let showsLeadingVisibilityToggle = false
    static let closeTitle = "Fechar"
    static let dismissesAfterSelection = true
}

enum CameraeNextGridPreference {
    private static let key = "camerae.capture.defaultGridStyle"

    static func current(in defaults: UserDefaults = .standard) -> CameraeNextGridStyle {
        guard let rawValue = defaults.string(forKey: key),
              let style = CameraeNextGridStyle(rawValue: rawValue) else {
            return .default
        }
        return style
    }

    static func save(_ style: CameraeNextGridStyle, in defaults: UserDefaults = .standard) {
        defaults.set(style.rawValue, forKey: key)
    }
}

enum CameraeNextGridStyle: String, CaseIterable, Identifiable, Sendable {
    case ruleOfThirds
    case goldenRatio
    case goldenSpiral
    case goldenSpiralMirrored
    case diagonals
    case triangles
    case fourByFour
    case centerCross

    static let `default` = CameraeNextGridStyle.ruleOfThirds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruleOfThirds: "Regra dos terços"
        case .goldenRatio: "Proporção áurea"
        case .goldenSpiral: "Espiral áurea"
        case .goldenSpiralMirrored: "Espiral áurea invertida"
        case .diagonals: "Diagonais"
        case .triangles: "Triângulos"
        case .fourByFour: "Grade 4 × 4"
        case .centerCross: "Centro e cruz"
        }
    }

    var usesGoldenSpiral: Bool {
        self == .goldenSpiral || self == .goldenSpiralMirrored
    }

    var isMirrored: Bool { self == .goldenSpiralMirrored }
}

struct CameraeNextGridOverlay: View {
    let style: CameraeNextGridStyle
    var lineColor = Color.white

    var body: some View {
        Canvas { context, size in
            let path = path(in: size)
            context.stroke(path, with: .color(.black.opacity(0.72)), style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(lineColor.opacity(0.88)), style: .init(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private func path(in size: CGSize) -> Path {
        switch style {
        case .ruleOfThirds:
            return orthogonalGrid(in: size, fractions: [1.0 / 3.0, 2.0 / 3.0])
        case .goldenRatio:
            let short = 1.0 - 1.0 / 1.61803398875
            return orthogonalGrid(in: size, fractions: [short, 1 - short])
        case .goldenSpiral, .goldenSpiralMirrored:
            return goldenSpiral(in: size, mirrored: style.isMirrored)
        case .diagonals:
            return diagonalGrid(in: size)
        case .triangles:
            return triangleGrid(in: size)
        case .fourByFour:
            return orthogonalGrid(in: size, fractions: [0.25, 0.5, 0.75])
        case .centerCross:
            return centerCross(in: size)
        }
    }

    private func orthogonalGrid(in size: CGSize, fractions: [Double]) -> Path {
        Path { path in
            for fraction in fractions {
                let x = size.width * fraction
                let y = size.height * fraction
                path.move(to: .init(x: x, y: 0))
                path.addLine(to: .init(x: x, y: size.height))
                path.move(to: .init(x: 0, y: y))
                path.addLine(to: .init(x: size.width, y: y))
            }
        }
    }

    private func diagonalGrid(in size: CGSize) -> Path {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: .init(x: size.width, y: size.height))
            path.move(to: .init(x: size.width, y: 0))
            path.addLine(to: .init(x: 0, y: size.height))
            path.move(to: .init(x: size.width * 0.5, y: 0))
            path.addLine(to: .init(x: size.width, y: size.height * 0.5))
            path.move(to: .init(x: 0, y: size.height * 0.5))
            path.addLine(to: .init(x: size.width * 0.5, y: size.height))
        }
    }

    private func triangleGrid(in size: CGSize) -> Path {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: .init(x: size.width, y: size.height))
            path.move(to: .init(x: size.width * 0.72, y: size.height * 0.72))
            path.addLine(to: .init(x: size.width, y: 0))
            path.move(to: .init(x: size.width * 0.28, y: size.height * 0.28))
            path.addLine(to: .init(x: 0, y: size.height))
        }
    }

    private func centerCross(in size: CGSize) -> Path {
        Path { path in
            path.move(to: .init(x: size.width / 2, y: 0))
            path.addLine(to: .init(x: size.width / 2, y: size.height))
            path.move(to: .init(x: 0, y: size.height / 2))
            path.addLine(to: .init(x: size.width, y: size.height / 2))
            let radius = min(size.width, size.height) * 0.12
            path.addEllipse(in: .init(x: size.width / 2 - radius, y: size.height / 2 - radius, width: radius * 2, height: radius * 2))
        }
    }

    private func goldenSpiral(in size: CGSize, mirrored: Bool) -> Path {
        let center = CGPoint(
            x: size.width * (mirrored ? 0.382 : 0.618),
            y: size.height * 0.382
        )
        let maxRadius = hypot(size.width, size.height) * 0.72
        return Path { path in
            for step in 0...240 {
                let progress = Double(step) / 240
                let angle = progress * Double.pi * 4.5 - Double.pi * 0.72
                let radius = maxRadius * pow(progress, 1.72)
                let direction = mirrored ? -1.0 : 1.0
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle) * radius * direction),
                    y: center.y + CGFloat(sin(angle) * radius)
                )
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

struct CameraeNextGridPickerView: View {
    @Binding var selection: CameraeNextGridStyle
    @Binding var isVisible: Bool
    let theme: CameraeWorkflowTheme

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let landscape = proxy.size.width > proxy.size.height
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: landscape ? 3 : 2),
                        spacing: 12
                    ) {
                        ForEach(CameraeNextGridStyle.allCases) { style in
                            gridCard(style)
                        }
                    }
                    .padding()
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Grade de composição")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(CameraeNextGridPickerPresentation.closeTitle, action: dismiss.callAsFunction)
                }
            }
            .tint(theme.accent)
            .preferredColorScheme(.dark)
        }
    }

    private func gridCard(_ style: CameraeNextGridStyle) -> some View {
        Button {
            selection = style
            isVisible = true
            CameraeNextGridPreference.save(style)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    LinearGradient(
                        colors: theme == .astro
                            ? [Color.indigo.opacity(0.8), Color.black, Color.blue.opacity(0.6)]
                            : [Color.orange.opacity(0.9), Color.purple.opacity(0.7), Color.blue.opacity(0.8)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                    CameraeNextGridOverlay(style: style)
                }
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack {
                    Text(style.title)
                        .font(.custom("Outfit-Medium", size: 13, relativeTo: .subheadline))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if selection == style {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                    }
                }
                .foregroundStyle(.white)
            }
            .padding(10)
            .background(Color.white.opacity(selection == style ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selection == style ? theme.accent : Color.white.opacity(0.12), lineWidth: selection == style ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(selection == style ? .isSelected : [])
    }
}
