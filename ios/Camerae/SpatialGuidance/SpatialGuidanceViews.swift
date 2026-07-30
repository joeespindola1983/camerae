import SwiftUI

struct SpatialGuidanceConfigurationCard: View {
    let availability: SpatialGuidanceAvailability
    let hasReference: Bool
    let action: () -> Void

    private let theme = CameraeNextTheme(workflow: .repeatable)

    var body: some View {
        CameraeNextCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(status)
                        .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(statusColor)
                    Spacer()
                    Image(systemName: "viewfinder")
                        .foregroundStyle(statusColor)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                    .foregroundStyle(theme.text)

                Text(detail)
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.muted)

                CameraeNextActionButton(
                    title: actionTitle,
                    systemImage: nil,
                    theme: theme,
                    style: hasReference ? .secondary : .primary,
                    isDisabled: availability != .available,
                    action: action
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spatial-guidance-configuration-card")
    }

    private var status: String {
        if availability != .available { return "INDISPONÍVEL" }
        return hasReference ? "GUIA SALVO" : "NÃO CONFIGURADO"
    }

    private var title: String {
        if availability != .available { return "Orientação espacial indisponível" }
        return hasReference ? "Posição memorizada" : "Memória da posição"
    }

    private var detail: String {
        switch availability {
        case .available:
            hasReference
                ? "Cena e pose da câmera prontas para a próxima visita."
                : "Mapeie o local para reencontrar a posição exata do tripé."
        case .moduleUnavailable:
            "Por enquanto, este recurso está disponível somente no Repeatable."
        case .temporarilyUnavailable:
            "O iPhone precisa esfriar antes de iniciar um mapeamento espacial."
        case .hardwareUnavailable, .performanceUnavailable:
            "O timelapse continua disponível sem orientação espacial."
        }
    }

    private var actionTitle: String {
        hasReference ? "Refazer guia" : "Criar guia espacial"
    }

    private var statusColor: Color {
        availability == .available ? theme.accent : theme.muted
    }
}

struct SpatialGuidanceFlowView: View {
    let mode: SpatialGuidanceFlowMode
    let project: CameraProject
    let configuration: CameraeNextCaptureConfiguration
    let onReferenceSaved: () -> Void
    let onContinueWithoutReference: () -> Void
    let onAlignedCapture: () -> Void
    let onDismiss: () -> Void

    @StateObject private var model: SpatialGuidanceSessionModel
    @State private var hasStartedCreation = false

    private let store: SpatialReferenceStore
    private let lightTheme = CameraeNextTheme(workflow: .repeatable)

    init(
        mode: SpatialGuidanceFlowMode,
        project: CameraProject,
        configuration: CameraeNextCaptureConfiguration,
        onReferenceSaved: @escaping () -> Void,
        onContinueWithoutReference: @escaping () -> Void,
        onAlignedCapture: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.project = project
        self.configuration = configuration
        self.onReferenceSaved = onReferenceSaved
        self.onContinueWithoutReference = onContinueWithoutReference
        self.onAlignedCapture = onAlignedCapture
        self.onDismiss = onDismiss
        store = SpatialReferenceStore(projectDirectory: project.directoryURL)
        _model = StateObject(wrappedValue: SpatialGuidanceSessionModel())
    }

    var body: some View {
        ZStack {
            SpatialGuidanceARView(model: model)
                .ignoresSafeArea()

            CameraeColor.captureScrim.opacity(0.18)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                topBar
                Spacer(minLength: 0)
                guidancePanel
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .task {
            if case .relocalize(let reference) = mode {
                model.startRelocalization(reference: reference)
            }
        }
        .onDisappear { model.stop() }
        .interactiveDismissDisabled()
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("REPEATABLE · GUIA ESPACIAL")
                    .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(CameraeColor.captureForegroundMuted)
                Text(navigationTitle)
                    .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                    .foregroundStyle(CameraeColor.captureForeground)
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(CameraeColor.captureForeground)
            .accessibilityLabel("Fechar guia espacial")
        }
    }

    @ViewBuilder
    private var guidancePanel: some View {
        VStack(spacing: 12) {
            switch model.phase {
            case .idle:
                creationIntroduction
            case .mapping, .insufficientCoverage:
                mappingPanel
            case .reviewingScene:
                sceneReviewPanel
            case .selectingTripodBase:
                tripodBaseSelectionPanel(hasSelection: false)
            case .tripodBaseSelected:
                tripodBaseSelectionPanel(hasSelection: true)
            case .readyToMount:
                readyToMountPanel
            case .saving:
                busyPanel(title: "Salvando posição", detail: "Arquivando mapa, pose e imagens de referência.")
            case .saved:
                savedPanel
            case .relocalizing:
                relocalizationPanel
            case .positioning:
                positioningPanel(isAligned: false)
            case .aligned:
                positioningPanel(isAligned: true)
            case .failed(let failure):
                failurePanel(failure)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(CameraeColor.captureHairline, lineWidth: 1)
        }
        .frame(maxWidth: 390)
    }

    private var creationIntroduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialStatusBadgeView(label: "PRIMEIRA VISITA", tone: .accent)
            Text("Circule o tripé")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text("Ande devagar como se filmasse um 360°. Mantenha o tripé parado e inclua bastante chão e objetos fixos.")
                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            captureAction(title: "Começar mapeamento", style: .primary) {
                hasStartedCreation = true
                model.startMapping()
            }
            captureAction(title: "Agora não", style: .secondary, action: close)
        }
    }

    private var mappingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialProgressCardView(
                status: model.mappingQuality.canSave ? "MAPA PRONTO" : "MAPEANDO",
                title: model.mappingQuality.canSave ? "Agora monte o telefone" : "Circule o tripé",
                detail: missingRequirementsDescription,
                progress: model.mappingQuality.progress,
                tone: model.mappingQuality.canSave ? .success : .accent
            )
            Text("O botão de salvar só aparece quando tracking, cobertura, detalhes e imagens passam juntos.")
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            if model.mappingQuality.canDefineScene {
                captureAction(title: "Parar e revisar", style: .primary) {
                    model.freezeMappedScene()
                }
                Text("Você pode encerrar agora. Continuar caminhando melhora a chance de reconhecer o local na próxima visita.")
                    .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption2))
                    .foregroundStyle(CameraeColor.captureForegroundMuted)
            }
        }
    }

    private var readyToMountPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialProgressCardView(
                status: "MAPA PRONTO",
                title: "Monte o telefone",
                detail: "Fixe o iPhone no tripé sem mover as pernas. Depois salve a pose exata da câmera.",
                progress: 1,
                tone: .success
            )
            captureAction(title: "Salvar posição", style: .primary) {
                Task {
                    do {
                        _ = try await model.saveReference(
                            store: store,
                            configuration: configuration,
                            orientation: currentOrientation
                        )
                        onReferenceSaved()
                    } catch {
                        model.reportPersistenceFailure(error)
                    }
                }
            }
        }
    }

    private var sceneReviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialStatusBadgeView(label: "CENA MAPEADA", tone: .success)
            Text("Revise os polígonos")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text("As linhas laranja mostram somente as superfícies que o LiDAR já reconstruiu. Continue caminhando se faltarem objetos ou chão importantes.")
                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            ProgressView(value: mappingQualityProgress)
                .tint(.green)
            captureAction(title: "Definir esta cena", style: .primary) {
                model.freezeMappedScene()
            }
        }
    }

    private func tripodBaseSelectionPanel(hasSelection: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialStatusBadgeView(
                label: hasSelection ? "CENTRO MARCADO" : "SELECIONE A BASE",
                tone: hasSelection ? .success : .accent
            )
            Text(hasSelection ? "Confira o centro" : "Toque no centro do tripé")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text(
                hasSelection
                    ? "Arraste o marcador laranja sobre o chão para corrigir. Ele deve ficar no centro entre as pernas."
                    : "Toque no chão, no centro entre as pernas do tripé. Depois você poderá arrastar para ajustar."
            )
            .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
            .foregroundStyle(CameraeColor.captureForegroundMuted)

            if hasSelection {
                captureAction(title: "Confirmar centro", style: .primary) {
                    model.confirmTripodBase()
                }
            }
        }
    }

    private var savedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialStatusBadgeView(label: "GUIA SALVO", tone: .success)
            Text("Posição memorizada")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text("O mapa anterior foi preservado em “previous” quando existia.")
                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            captureAction(title: "Concluir", style: .primary, action: close)
        }
    }

    private var relocalizationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialStatusBadgeView(label: "RELOCALIZANDO", tone: .accent)
            Text("Reconhecendo a cena")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text("Repita o movimento da primeira visita. O tripé fantasma só aparece quando a âncora for restaurada com tracking normal.")
                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            ProgressView()
                .tint(CameraeColor.captureForeground)
        }
    }

    private func positioningPanel(isAligned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SpatialStatusBadgeView(
                label: isAligned ? "ALINHADO" : "ATENÇÃO",
                tone: isAligned ? .success : .attention
            )
            Text(isAligned ? "Posição confirmada" : "Ajuste o tripé")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))

            if let evaluation = model.poseEvaluation {
                SpatialPoseDeltaView(
                    label: "POSIÇÃO",
                    value: isAligned ? "Alinhado" : horizontalDescription(evaluation),
                    systemImage: isAligned ? "checkmark" : "arrow.left.and.right",
                    isAligned: isAligned
                )
                SpatialPoseDeltaView(
                    label: "ALTURA",
                    value: isAligned ? "Alinhado" : verticalDescription(evaluation),
                    systemImage: isAligned ? "checkmark" : "arrow.up.and.down",
                    isAligned: isAligned
                )
                SpatialPoseDeltaView(
                    label: "ROTAÇÃO",
                    value: isAligned ? "Alinhado" : rotationDescription(evaluation),
                    systemImage: isAligned ? "checkmark" : "rotate.right",
                    isAligned: isAligned
                )
            }

            if isAligned {
                captureAction(title: "Abrir câmera", style: .primary) {
                    model.stop()
                    onAlignedCapture()
                }
            }
        }
    }

    private func failurePanel(_ failure: SpatialGuidanceFailure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialStatusBadgeView(label: "NÃO LOCALIZADO", tone: .attention)
            Text("Cena não reconhecida")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text(model.errorMessage ?? "Melhore a luz ou repita o caminho da primeira visita.")
                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            if case .relocalize(let reference) = mode {
                captureAction(title: "Tentar novamente", style: .primary) {
                    model.startRelocalization(reference: reference)
                }
            }
            captureAction(title: "Continuar sem guia", style: .secondary) {
                model.stop()
                onContinueWithoutReference()
            }
            if failure == .incompatibleReference {
                captureAction(title: "Fechar", style: .secondary, action: close)
            }
        }
    }

    private func busyPanel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
            Text(title)
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text(detail)
                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func captureAction(
        title: String,
        style: CameraeNextActionButton.Style,
        action: @escaping () -> Void
    ) -> some View {
        CameraeNextActionButton(
            title: title,
            systemImage: nil,
            theme: lightTheme,
            style: style,
            isBusy: model.isBusy,
            action: action
        )
    }

    private var navigationTitle: String {
        switch mode {
        case .createReference: hasStartedCreation ? "Mapeie a cena" : "Guia espacial"
        case .relocalize: "Volte ao mesmo lugar"
        }
    }

    private var missingRequirementsDescription: String {
        let missing = model.mappingQuality.missingRequirements
        if missing.contains(.tracking) { return "Mova o iPhone mais devagar para recuperar o tracking." }
        if missing.contains(.coverage) { return "Inclua mais chão e objetos fixos ao redor do tripé." }
        if missing.contains(.detail) { return "Aproxime-se de superfícies com textura e boa luz." }
        if missing.contains(.keyframes) { return "Continue por mais alguns segundos para registrar referências." }
        return "Cobertura suficiente para salvar a pose."
    }

    private var mappingQualityProgress: Double {
        max(0, min(model.mappingQuality.progress, 1))
    }

    private var currentOrientation: SpatialCaptureOrientation {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: .portrait
        }
    }

    private func horizontalDescription(_ evaluation: SpatialPoseEvaluation) -> String {
        let centimeters = Int((evaluation.horizontalDistanceMeters * 100).rounded())
        return "\(centimeters) cm"
    }

    private func verticalDescription(_ evaluation: SpatialPoseEvaluation) -> String {
        let centimeters = Int((evaluation.verticalDistanceMeters * 100).rounded())
        return "\(centimeters) cm"
    }

    private func rotationDescription(_ evaluation: SpatialPoseEvaluation) -> String {
        evaluation.maximumRotationDegrees.formatted(
            .number.precision(.fractionLength(1))
        ) + "°"
    }

    private func close() {
        model.stop()
        onDismiss()
    }
}

private enum SpatialGuidanceTone {
    case accent
    case attention
    case success

    var color: Color {
        switch self {
        case .accent: CameraeColor.accentRepeatable
        case .attention: .yellow
        case .success: .green
        }
    }
}

private struct SpatialStatusBadgeView: View {
    let label: String
    let tone: SpatialGuidanceTone

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                .tracking(1)
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .overlay { Capsule().stroke(tone.color, lineWidth: 1) }
    }
}

private struct SpatialProgressCardView: View {
    let status: String
    let title: String
    let detail: String
    let progress: Double
    let tone: SpatialGuidanceTone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(status)
                .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                .tracking(1)
                .foregroundStyle(tone.color)
            Text(title)
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text(detail)
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            ProgressView(value: progress)
                .tint(tone.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SpatialPoseDeltaView: View {
    let label: String
    let value: String
    let systemImage: String
    let isAligned: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tone)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .body))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(CameraeColor.repeatableLightText)
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(CameraeColor.repeatableLightCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(tone, lineWidth: 1)
        }
    }

    private var tone: Color { isAligned ? .green : .yellow }
}
