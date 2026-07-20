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
            status = "CALCULANDO"
            title = "Calculando espaço e bateria"
            detail = "Estimativa será atualizada antes da captura"
            progress = 0.34
        case .ready:
            status = "PRONTO"
            title = "Captura viável"
            detail = Self.join(metricsDetail, preflight.detail)
            progress = 1
        case .warning:
            status = "ATENÇÃO"
            title = "Margem de espaço reduzida"
            detail = preflight.detail
            progress = 0.76
        case .blocked:
            status = "BLOQUEADO"
            title = "Espaço insuficiente"
            detail = preflight.detail
            progress = 0.96
        case .error:
            status = "ERRO"
            title = "Planejamento indisponível"
            detail = preflight.detail
            progress = nil
        case .adjusted:
            status = "AJUSTADO"
            title = "Formato ajustado por compatibilidade"
            detail = Self.join("HEIC indisponível · captura será salva em JPEG", metricsDetail)
            progress = 1
        case .externalPower:
            status = "ENERGIA"
            title = "Alimentação externa recomendada"
            detail = Self.join("Sessão longa · conecte o carregador", metricsDetail)
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
        status: "CALCULANDO",
        title: "Calculando espaço e bateria",
        detail: "Estimativa será atualizada antes da captura",
        progress: 0.34
    )

    static func error(_ message: String?) -> Self {
        Self(
            state: .error,
            canStart: false,
            status: "ERRO",
            title: "Planejamento indisponível",
            detail: message ?? "Não foi possível verificar espaço e bateria",
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
        preferredLens: RepeatableCameraLens
    ) {
        if availableLenses.isEmpty {
            state = .unavailable
            canStart = false
            title = "Nenhuma câmera compatível"
            detail = "Revise as permissões ou use outro aparelho"
            status = "INDISPONÍVEL"
        } else if !availableLenses.contains(preferredLens) {
            state = .fallback
            canStart = true
            title = "Câmera substituída"
            detail = "\(preferredLens.title) indisponível · usando \(Self.lensDescription(selectedLens))"
            status = "AJUSTADA"
        } else if availableLenses.count == 1 {
            state = .single
            canStart = true
            title = "Apenas Principal disponível"
            detail = "As outras lentes não estão presentes neste aparelho"
            status = "ÚNICA"
        } else {
            state = .available
            canStart = true
            title = module == .astrophotography ? "Câmera em uso" : "Câmeras detectadas"
            detail = module == .astrophotography
                ? Self.lensDescription(selectedLens)
                : "Ultra-wide · Principal · Teleobjetiva"
            status = "DISPONÍVEL"
        }
    }

    private static func lensDescription(_ lens: RepeatableCameraLens) -> String {
        switch lens {
        case .ultraWide: "Ultra-wide · 0,5×"
        case .wide: "Principal · 1×"
        case .telephoto: "Teleobjetiva · TELE"
        }
    }
}

enum CameraeNextReferenceState: Equatable, Sendable {
    case active
    case missing
    case loading
    case unavailable
}

struct CameraeNextReferencePresentation: Equatable, Sendable {
    let sectionTitle: String
    let iconLabel: String
    let title: String
    let detail: String
    let status: String

    init(module: CameraModule, state: CameraeNextReferenceState) {
        let isAstro = module == .astrophotography
        sectionTitle = isAstro ? "GUIA NOTURNO" : "REFERÊNCIA"
        iconLabel = isAstro ? "AST" : "REF"

        switch (isAstro, state) {
        case (false, .active):
            title = "Primeiro enquadramento"
            detail = "Rotação e GPS salvos"
            status = "ATIVA"
        case (false, .missing):
            title = "Nenhuma referência definida"
            detail = "Capture ou escolha uma imagem para alinhar"
            status = "AUSENTE"
        case (false, .loading):
            title = "Preparando referência"
            detail = "Lendo imagem e metadados de orientação"
            status = "CARREGANDO"
        case (false, .unavailable):
            title = "Referência não disponível"
            detail = "O arquivo original foi movido ou removido"
            status = "INDISPONÍVEL"
        case (true, .active):
            title = "Céu e horizonte"
            detail = "Nível e orientação salvos"
            status = "ATIVO"
        case (true, .missing):
            title = "Nenhum guia noturno definido"
            detail = "Capture o céu e o horizonte para orientar a sessão"
            status = "AUSENTE"
        case (true, .loading):
            title = "Preparando guia noturno"
            detail = "Lendo nível e metadados de orientação"
            status = "CARREGANDO"
        case (true, .unavailable):
            title = "Guia noturno indisponível"
            detail = "O arquivo original foi movido ou removido"
            status = "INDISPONÍVEL"
        }
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
                    CameraeNextSectionLabel(title: "Planejamento", theme: theme)
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
            sectionTitle: "CÂMERA",
            title: presentation.title,
            detail: presentation.detail,
            status: presentation.status,
            theme: theme
        )
    }
}

struct CameraeNextReferenceStateCard: View {
    let presentation: CameraeNextReferencePresentation
    let theme: CameraeNextTheme

    var body: some View {
        CameraeNextStatusCard(
            iconLabel: presentation.iconLabel,
            sectionTitle: presentation.sectionTitle,
            title: presentation.title,
            detail: presentation.detail,
            status: presentation.status,
            theme: theme
        )
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
                Text(isAstro ? "Duração da sessão" : "Duração personalizada")
                    .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                Text(isAstro
                     ? "Defina o tempo total disponível para capturas Astro."
                     : "Defina por quanto tempo a captura ficará ativa.")
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Duração")
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
                    .accessibilityLabel("Duração em horas e minutos")
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
                sheetButton("Cancelar", background: theme.surface, foreground: theme.text) {
                    dismiss()
                }
                sheetButton("Aplicar", background: theme.accent, foreground: .white) {
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
