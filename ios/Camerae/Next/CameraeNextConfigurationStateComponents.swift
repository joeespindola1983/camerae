import CameraeCore
import SwiftUI

enum CameraeNextCapturePlanningState: Equatable, Sendable {
    case evaluating
    case ready
    case warning
    case blocked
    case error
    case adjusted
    case externalPower
}

struct CameraeNextCapturePlanningPresentation: Equatable, Sendable {
    let state: CameraeNextCapturePlanningState
    let canStart: Bool
    let status: String
    let title: String
    let detail: String
    let progress: Double?

    init(
        storage: CaptureAdmissionResult,
        formatWasAdjusted: Bool = false,
        externalPowerRecommended: Bool = false,
        metricsDetail: String
    ) {
        let preflight = CapturePreflightPresentation(storage: storage)
        canStart = preflight.canStart

        if !preflight.canStart {
            state = storage.decision == .blocked ? .blocked : .error
        } else if formatWasAdjusted {
            state = .adjusted
        } else if externalPowerRecommended {
            state = .externalPower
        } else if storage.decision == .warning {
            state = .warning
        } else {
            state = .ready
        }

        switch state {
        case .evaluating:
            status = CameraeL10n.calculating
            title = CameraeL10n.calculatingResources
            detail = CameraeL10n.calculatingResourcesDetail
            progress = 0.34
        case .ready:
            status = CameraeL10n.ready
            title = CameraeL10n.captureViable
            detail = Self.join(metricsDetail, preflight.detail)
            progress = 1
        case .warning:
            status = CameraeL10n.attention
            title = CameraeL10n.reducedSpaceMargin
            detail = preflight.detail
            progress = 0.76
        case .blocked:
            status = CameraeL10n.blocked
            title = CameraeL10n.insufficientSpace
            detail = preflight.detail
            progress = 0.96
        case .error:
            status = CameraeL10n.error.uppercased()
            title = CameraeL10n.planningUnavailable
            detail = preflight.detail
            progress = nil
        case .adjusted:
            status = CameraeL10n.adjusted
            title = CameraeL10n.formatAdjusted
            detail = Self.join(CameraeL10n.formatAdjustedDetail, metricsDetail)
            progress = 1
        case .externalPower:
            status = CameraeL10n.power
            title = CameraeL10n.externalPowerRecommended
            detail = Self.join(CameraeL10n.externalPowerDetail, metricsDetail)
            progress = 1
        }
    }

    init(result: CapturePreflightResult) {
        let metrics = CapturePreflightMetricsPresentation(
            plan: result.resolvedPlan,
            estimate: result.estimate
        )
        self.init(
            storage: result.storage,
            formatWasAdjusted: result.formatFallbackReason != nil,
            externalPowerRecommended: result.energy.externalPowerRecommended,
            metricsDetail: Self.join(metrics.primary, metrics.secondary)
        )
    }

    static let evaluating = Self(
        state: .evaluating,
        canStart: false,
        status: CameraeL10n.calculating,
        title: CameraeL10n.calculatingResources,
        detail: CameraeL10n.calculatingResourcesDetail,
        progress: 0.34
    )

    static func error(_ message: String?) -> Self {
        Self(
            state: .error,
            canStart: false,
            status: CameraeL10n.error.uppercased(),
            title: CameraeL10n.planningUnavailable,
            detail: message ?? CameraeL10n.planningCheckFailed,
            progress: nil
        )
    }

    private init(
        state: CameraeNextCapturePlanningState,
        canStart: Bool,
        status: String,
        title: String,
        detail: String,
        progress: Double?
    ) {
        self.state = state
        self.canStart = canStart
        self.status = status
        self.title = title
        self.detail = detail
        self.progress = progress
    }

    private static func join(_ first: String, _ second: String) -> String {
        [first, second].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum CameraeNextCameraSetupState: Equatable, Sendable {
    case available
    case single
    case fallback
    case locked
    case lockedUnavailable
    case unavailable
}

struct CameraeNextCameraSetupPresentation: Equatable, Sendable {
    let state: CameraeNextCameraSetupState
    let canStart: Bool
    let title: String
    let detail: String
    let status: String

    init(
        module: CameraModule = .repeatable,
        availableLenses: [RepeatableCameraLens],
        selectedLens: RepeatableCameraLens,
        preferredLens: RepeatableCameraLens,
        lockedLens: RepeatableCameraLens? = nil,
        lockedZoomFactor: Double = 1
    ) {
        if let lockedLens, !availableLenses.contains(lockedLens) {
            state = .lockedUnavailable
            canStart = false
            title = CameraeL10n.cameraProjectUnavailable
            detail = CameraeL10n.connectCamera(Self.cameraDescription(lockedLens, zoomFactor: lockedZoomFactor))
            status = CameraeL10n.cameraLockedStatus
        } else if let lockedLens {
            state = .locked
            canStart = true
            title = CameraeL10n.cameraProject
            detail = Self.cameraDescription(lockedLens, zoomFactor: lockedZoomFactor)
            status = CameraeL10n.cameraLockedStatus
        } else if availableLenses.isEmpty {
            state = .unavailable
            canStart = false
            title = CameraeL10n.noCompatibleCamera
            detail = CameraeL10n.noCompatibleCameraDetail
            status = CameraeL10n.cameraUnavailableStatus
        } else if !availableLenses.contains(preferredLens) {
            state = .fallback
            canStart = true
            title = CameraeL10n.cameraReplaced
            detail = CameraeL10n.unavailableUsing(preferredLens.title, Self.lensDescription(selectedLens))
            status = CameraeL10n.cameraAdjustedStatus
        } else if availableLenses.count == 1 {
            state = .single
            canStart = true
            title = CameraeL10n.onlyMainCamera
            detail = CameraeL10n.onlyMainCameraDetail
            status = CameraeL10n.cameraSingleStatus
        } else {
            state = .available
            canStart = true
            title = module == .astrophotography ? CameraeL10n.cameraInUse : CameraeL10n.camerasDetected
            detail = module == .astrophotography
                ? Self.lensDescription(selectedLens)
                : "\(CameraeL10n.lensUltraWide) · \(CameraeL10n.lensMain) · \(CameraeL10n.lensTelephoto)"
            status = CameraeL10n.cameraAvailableStatus
        }
    }

    private static func lensDescription(_ lens: RepeatableCameraLens) -> String {
        switch lens {
        case .ultraWide: "\(CameraeL10n.lensUltraWide) · 0,5×"
        case .wide: "\(CameraeL10n.lensMain) · 1×"
        case .telephoto: "\(CameraeL10n.lensTelephoto) · TELE"
        }
    }

    private static func cameraDescription(
        _ lens: RepeatableCameraLens,
        zoomFactor: Double
    ) -> String {
        guard zoomFactor > 1.01 else { return lensDescription(lens) }
        let zoom = zoomFactor.formatted(
            .number.locale(.current).precision(.fractionLength(0...1))
        )
        return "\(lensDescription(lens)) · zoom \(zoom)×"
    }
}

enum CameraeNextReferenceState: Equatable, Sendable {
    case active
    case missing
    case loading
    case unavailable
}

struct CameraeNextReferencePresentation: Equatable, Sendable {
    let showsPlaceholder: Bool
    let primaryActionTitle: String
    let secondaryActionTitle: String

    init(module: CameraModule, state: CameraeNextReferenceState) {
        _ = module
        switch state {
        case .missing:
            showsPlaceholder = true
            primaryActionTitle = CameraeL10n.takePhoto
            secondaryActionTitle = CameraeL10n.importPhoto
        case .active:
            showsPlaceholder = false
            primaryActionTitle = CameraeL10n.replace
            secondaryActionTitle = CameraeL10n.remove
        case .loading:
            showsPlaceholder = true
            primaryActionTitle = CameraeL10n.wait
            secondaryActionTitle = CameraeL10n.cancel
        case .unavailable:
            showsPlaceholder = true
            primaryActionTitle = CameraeL10n.chooseAnother
            secondaryActionTitle = CameraeL10n.remove
        }
    }
}

struct CameraeNextProjectCameraPolicy: Equatable, Sendable {
    let lockedLens: RepeatableCameraLens?
    let lockedZoomFactor: Double

    var isLocked: Bool { lockedLens != nil }

    func accepts(lens: RepeatableCameraLens, zoomFactor: Double) -> Bool {
        guard let lockedLens else { return true }
        return lockedLens == lens && abs(lockedZoomFactor - max(zoomFactor, 1)) < 0.01
    }

    init(
        summaries: [TimelapseSessionSummary],
        legacyFallbackLens: RepeatableCameraLens = .wide
    ) {
        let firstCapture = summaries
            .filter(\.containsCapturedMedia)
            .min { $0.session.createdAt < $1.session.createdAt }
        lockedLens = firstCapture.map { $0.session.cameraLens ?? legacyFallbackLens }
        lockedZoomFactor = max(firstCapture?.session.cameraZoomFactor ?? 1, 1)
    }
}

private extension TimelapseSessionSummary {
    var containsCapturedMedia: Bool {
        if captureKind == .photo, session.cameraLens == nil {
            return false
        }
        return frameCount > 0 ||
            videoURL != nil ||
            videoClipURL != nil ||
            isAstroProcessed
    }
}

enum CameraeNextCustomDuration {
    static let quickMinutes = [60, 120, 240, 480]

    static func format(minutes: Int) -> String {
        String(format: "%02d h %02d min", minutes / 60, minutes % 60)
    }

    static func parse(_ value: String) -> Int? {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let numbers = normalized
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
            .compactMap(Int.init)

        let total: Int?
        if normalized.contains("h") || normalized.contains(":") {
            guard let hours = numbers.first else { return nil }
            let minutes = numbers.dropFirst().first ?? 0
            guard minutes < 60 else { return nil }
            total = hours * 60 + minutes
        } else {
            total = numbers.first
        }

        guard let total, (1...(24 * 60)).contains(total) else { return nil }
        return total
    }
}

struct CameraeNextCapturePlanningCard: View {
    let presentation: CameraeNextCapturePlanningPresentation
    let theme: CameraeNextTheme

    var body: some View {
        CameraeNextCard(theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CameraeNextSectionLabel(title: CameraeL10n.planningSection, theme: theme)
                    Text(presentation.status)
                        .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                        .foregroundStyle(theme.accent)
                }
                Text(presentation.title)
                    .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text(presentation.detail)
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = presentation.progress {
                    ProgressView(value: progress)
                        .tint(theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CameraeNextCameraSetupStateCard: View {
    let presentation: CameraeNextCameraSetupPresentation
    let theme: CameraeNextTheme

    var body: some View {
        CameraeNextStatusCard(
            iconLabel: "CAM",
            sectionTitle: CameraeL10n.cameraSection,
            title: presentation.title,
            detail: presentation.detail,
            status: presentation.status,
            theme: theme
        )
    }
}

struct CameraeNextReferenceStateCard: View {
    let presentation: CameraeNextReferencePresentation
    let imageURL: URL?
    let theme: CameraeNextTheme
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 10) {
                ReferenceThumbnail(
                    imageURL: presentation.showsPlaceholder ? nil : imageURL,
                    systemImage: "photo",
                    width: nil,
                    height: 160,
                    maxPixelSize: 900,
                    usesNeutralImagePlaceholder: true
                )

                HStack(spacing: 8) {
                    compactAction(
                        title: presentation.primaryActionTitle,
                        systemImage: "camera",
                        isPrimary: true,
                        action: primaryAction
                    )
                    compactAction(
                        title: presentation.secondaryActionTitle,
                        systemImage: presentation.secondaryActionTitle == CameraeL10n.remove ? "trash" : "photo.on.rectangle",
                        isPrimary: false,
                        action: secondaryAction
                    )
                }
            }
        }
    }

    private func compactAction(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.custom("Outfit-SemiBold", size: 13, relativeTo: .footnote))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isPrimary ? Color.white : theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isPrimary ? theme.accent : theme.surface, in: Capsule())
                .overlay {
                    if !isPrimary {
                        Capsule().stroke(theme.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct CameraeNextStatusCard: View {
    let iconLabel: String
    let sectionTitle: String
    let title: String
    let detail: String
    let status: String
    let theme: CameraeNextTheme

    var body: some View {
        CameraeNextCard(theme: theme) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: CameraeRadius.medium, style: .continuous)
                    .fill(theme.surface)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Text(iconLabel)
                            .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                            .foregroundStyle(theme.accent)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    CameraeNextSectionLabel(title: sectionTitle, theme: theme)
                    Text(title)
                        .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Text(detail)
                        .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption2))
                        .foregroundStyle(theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Text(status)
                    .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                    .foregroundStyle(theme.accent)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CameraeNextCustomDurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding private var minutes: Int
    let module: CameraModule
    let theme: CameraeNextTheme
    let onApply: () -> Void

    @State private var draft: String

    init(
        minutes: Binding<Int>,
        module: CameraModule,
        theme: CameraeNextTheme,
        onApply: @escaping () -> Void = {}
    ) {
        _minutes = minutes
        self.module = module
        self.theme = theme
        self.onApply = onApply
        _draft = State(initialValue: CameraeNextCustomDuration.format(minutes: minutes.wrappedValue))
    }

    private var parsedMinutes: Int? { CameraeNextCustomDuration.parse(draft) }
    private var isAstro: Bool { module == .astrophotography }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isAstro ? CameraeL10n.sessionDuration : CameraeL10n.customDuration)
                    .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                Text(isAstro
                     ? CameraeL10n.sessionDurationMessage
                     : CameraeL10n.customDurationMessage)
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(CameraeL10n.duration)
                    .font(.custom("Outfit-SemiBold", size: 11, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
                TextField("02 h 30 min", text: $draft)
                    .font(.custom("Outfit-Regular", size: 15, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: CameraeRadius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CameraeRadius.medium, style: .continuous)
                            .stroke(parsedMinutes == nil ? Color.red : theme.accent, lineWidth: 2)
                    }
                    .accessibilityLabel(CameraeL10n.duration)
            }

            HStack(spacing: 8) {
                ForEach(CameraeNextCustomDuration.quickMinutes, id: \.self) { value in
                    let selected = parsedMinutes == value
                    Button {
                        draft = CameraeNextCustomDuration.format(minutes: value)
                    } label: {
                        Text("\(value / 60) h")
                            .font(.custom("Outfit-SemiBold", size: 12, relativeTo: .caption))
                            .foregroundStyle(selected ? Color.white : theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 45)
                            .background(selected ? theme.accent : theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                sheetButton(CameraeL10n.cancel, background: theme.surface, foreground: theme.text) {
                    dismiss()
                }
                sheetButton(CameraeL10n.apply, background: theme.accent, foreground: .white) {
                    guard let parsedMinutes else { return }
                    minutes = parsedMinutes
                    onApply()
                    dismiss()
                }
                .disabled(parsedMinutes == nil)
                .opacity(parsedMinutes == nil ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background(theme.card)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.card)
        .preferredColorScheme(theme.colorScheme)
    }

    private func sheetButton(
        _ title: String,
        background: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .body))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(background, in: RoundedRectangle(cornerRadius: CameraeRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
