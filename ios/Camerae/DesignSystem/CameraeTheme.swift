import SwiftUI

enum CameraeWorkflowTheme: String, CaseIterable, Sendable {
    case repeatable
    case astro
    case editor

    var accent: Color {
        switch self {
        case .repeatable: CameraeColor.accentRepeatable
        case .astro: CameraeColor.accentAstro
        case .editor: CameraeColor.accentEditor
        }
    }

    var assetName: String {
        switch self {
        case .repeatable: "CameraeAccentRepeatable"
        case .astro: "CameraeAccentAstro"
        case .editor: "CameraeAccentEditor"
        }
    }
}

private struct CameraeWorkflowThemeKey: EnvironmentKey {
    static let defaultValue = CameraeWorkflowTheme.repeatable
}

extension EnvironmentValues {
    var cameraeWorkflowTheme: CameraeWorkflowTheme {
        get { self[CameraeWorkflowThemeKey.self] }
        set { self[CameraeWorkflowThemeKey.self] = newValue }
    }
}

extension View {
    func cameraeTheme(_ theme: CameraeWorkflowTheme) -> some View {
        environment(\.cameraeWorkflowTheme, theme)
            .tint(theme.accent)
    }
}

extension CameraModule {
    var designTheme: CameraeWorkflowTheme {
        switch self {
        case .repeatable: .repeatable
        case .astrophotography: .astro
        case .edit: .editor
        }
    }
}

enum CameraeCapturePanelOrientation: Sendable {
    case portrait
    case landscape

    var metricSize: CameraeCaptureMetricSize {
        self == .portrait ? .regular : .compact
    }

    var panelWidth: CGFloat {
        self == .portrait ? 366 : 300
    }

    var actionWidth: CGFloat {
        self == .portrait ? 342 : 276
    }

    var contentWidth: CGFloat { actionWidth }

    var actionHeight: CGFloat {
        self == .portrait ? 52 : 48
    }
}

struct CameraeCaptureMetric: Identifiable, Sendable {
    let title: String
    let value: String

    var id: String { title }
}

struct CameraeNextCaptureSessionPresentation: Sendable {
    let theme: CameraeWorkflowTheme
    let metrics: [CameraeCaptureMetric]
    let actionTitle: String
    let actionSystemImage: String
    let isRunning: Bool
    let showsLandscapePreview: Bool

    static func repeatable(
        frameCount: Int,
        exposure: String,
        lastExposure: String,
        remaining: String,
        isRunning: Bool,
        idleActionTitle: String = "Iniciar captura",
        idleActionSystemImage: String = "camera"
    ) -> Self {
        .init(
            theme: .repeatable,
            metrics: [
                .init(title: "Frames", value: "\(frameCount)"),
                .init(title: "EV", value: exposure),
                .init(title: "Última", value: lastExposure),
                .init(title: "Restante", value: remaining)
            ],
            actionTitle: isRunning ? "Parar" : idleActionTitle,
            actionSystemImage: isRunning ? "stop.fill" : idleActionSystemImage,
            isRunning: isRunning,
            showsLandscapePreview: false
        )
    }

    static func astro(
        originalCount: Int,
        acceptedCount: Int,
        batch: String,
        phase: String,
        baseExposure: String,
        lastExposure: String,
        isRunning: Bool
    ) -> Self {
        .init(
            theme: .astro,
            metrics: [
                .init(title: "Orig", value: "\(originalCount)"),
                .init(title: "Bons", value: "\(acceptedCount)"),
                .init(title: "Lote", value: batch),
                .init(title: "Fase", value: phase),
                .init(title: "Base", value: baseExposure),
                .init(title: "Última", value: lastExposure)
            ],
            actionTitle: isRunning ? "Parar" : "Iniciar lotes Astro",
            actionSystemImage: isRunning ? "stop.fill" : "sparkles",
            isRunning: isRunning,
            showsLandscapePreview: true
        )
    }
}

enum CameraeCaptureMetricSize: Sendable {
    case regular
    case compact

    var width: CGFloat { self == .regular ? 108 : 86 }
    var height: CGFloat { self == .regular ? 32 : 28 }
    var horizontalPadding: CGFloat { self == .regular ? 10 : 8 }
    var labelWidth: CGFloat { self == .regular ? 52 : 42 }
    var valueWidth: CGFloat { self == .regular ? 34 : 28 }
    var labelSize: CGFloat { self == .regular ? 8 : 7 }
    var valueSize: CGFloat { self == .regular ? 10 : 9 }
}

struct CameraeCaptureMetricPill: View {
    let metric: CameraeCaptureMetric
    let size: CameraeCaptureMetricSize

    var body: some View {
        HStack(spacing: 0) {
            Text(metric.title.uppercased())
                .font(.custom("Outfit-Medium", size: size.labelSize, relativeTo: .caption2))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text(metric.value)
                .font(.custom("Outfit-SemiBold", size: size.valueSize, relativeTo: .caption2))
                .foregroundStyle(CameraeColor.captureForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: size.valueWidth, alignment: .trailing)
        }
        .padding(.horizontal, size.horizontalPadding)
        .frame(maxWidth: size.width, minHeight: size.height)
        .background(CameraeColor.captureScrim.opacity(0.62), in: Capsule())
        .overlay {
            Capsule()
                .stroke(CameraeColor.captureHairline.opacity(0.9), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title): \(metric.value)")
    }
}

struct CameraeCaptureMetricsGrid: View {
    let metrics: [CameraeCaptureMetric]
    let orientation: CameraeCapturePanelOrientation

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<rowCount, id: \.self) { row in
                metricRow(startingAt: row * columnCount)
            }
        }
        .frame(maxWidth: orientation.contentWidth)
        .frame(height: orientation == .portrait ? 72 : 64)
    }

    private var columnCount: Int { metrics.count <= 4 ? 2 : 3 }
    private var rowCount: Int { max(1, Int(ceil(Double(metrics.count) / Double(columnCount)))) }

    private func metricRow(startingAt index: Int) -> some View {
        HStack(spacing: 9) {
            ForEach(index..<min(index + columnCount, metrics.count), id: \.self) { metricIndex in
                CameraeCaptureMetricPill(
                    metric: metrics[metricIndex],
                    size: orientation.metricSize
                )
            }
        }
    }
}

struct CameraeCapturePrimaryAction: View {
    let theme: CameraeWorkflowTheme
    let orientation: CameraeCapturePanelOrientation
    let title: String
    let systemImage: String
    let isRunning: Bool
    var isBusy = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(CameraeColor.captureForeground)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))

                    Text(title.uppercased())
                        .font(.custom("Outfit-Bold", size: 12, relativeTo: .caption))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(CameraeColor.captureForeground)
            .frame(maxWidth: orientation.actionWidth)
            .frame(height: orientation.actionHeight)
            .background(
                isRunning ? CameraeColor.captureDanger : theme.accent,
                in: RoundedRectangle(cornerRadius: CameraeRadius.large, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isBusy)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityLabel(title)
    }
}

struct CameraeCaptureSessionPanel<Preview: View>: View {
    let theme: CameraeWorkflowTheme
    let orientation: CameraeCapturePanelOrientation
    let metrics: [CameraeCaptureMetric]
    let actionTitle: String
    let actionSystemImage: String
    let isRunning: Bool
    var isBusy = false
    var isActionDisabled = false
    var showsLandscapePreview = true
    var showsMetrics = true
    let action: () -> Void
    private let preview: Preview

    init(
        theme: CameraeWorkflowTheme,
        orientation: CameraeCapturePanelOrientation,
        metrics: [CameraeCaptureMetric],
        actionTitle: String,
        actionSystemImage: String,
        isRunning: Bool,
        isBusy: Bool = false,
        isActionDisabled: Bool = false,
        showsLandscapePreview: Bool = true,
        showsMetrics: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview
    ) {
        self.theme = theme
        self.orientation = orientation
        self.metrics = metrics
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.isRunning = isRunning
        self.isBusy = isBusy
        self.isActionDisabled = isActionDisabled
        self.showsLandscapePreview = showsLandscapePreview
        self.showsMetrics = showsMetrics
        self.action = action
        self.preview = preview()
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsMetrics {
                CameraeCaptureMetricsGrid(metrics: metrics, orientation: orientation)
            }

            if orientation == .landscape, showsLandscapePreview {
                preview
                    .frame(maxWidth: orientation.contentWidth)
                    .frame(height: 126)
                    .background(
                        theme == .astro ? CameraeColor.astroDarkCard : CameraeColor.repeatableLightCard,
                        in: RoundedRectangle(cornerRadius: CameraeRadius.medium, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: CameraeRadius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CameraeRadius.medium, style: .continuous)
                            .stroke(CameraeColor.captureHairline.opacity(0.8), lineWidth: 1)
                    }
            }

            CameraeCapturePrimaryAction(
                theme: theme,
                orientation: orientation,
                title: actionTitle,
                systemImage: actionSystemImage,
                isRunning: isRunning,
                isBusy: isBusy,
                isDisabled: isActionDisabled,
                action: action
            )
        }
        .padding(12)
        .frame(maxWidth: orientation.panelWidth)
        .frame(height: panelHeight, alignment: .top)
        .background(
            CameraeColor.captureScrim.opacity(0.78),
            in: RoundedRectangle(cornerRadius: CameraeRadius.large, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CameraeRadius.large, style: .continuous)
                .stroke(CameraeColor.captureHairline.opacity(0.95), lineWidth: 1)
        }
        .cameraeTheme(theme)
    }

    private var panelHeight: CGFloat {
        guard showsMetrics else { return orientation.actionHeight + 24 }
        return switch (orientation, showsLandscapePreview) {
        case (.portrait, _): 160
        case (.landscape, true): 286
        case (.landscape, false): 148
        }
    }
}
