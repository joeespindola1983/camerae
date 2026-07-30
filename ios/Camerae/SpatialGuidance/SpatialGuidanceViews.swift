import SwiftUI

struct SpatialGuidanceConfigurationCard: View {
    let availability: SpatialGuidanceAvailability
    let hasReference: Bool
    let action: () -> Void
    let remapAction: () -> Void

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
                if hasReference {
                    CameraeNextActionButton(
                        title: "Mapear novamente",
                        systemImage: nil,
                        theme: theme,
                        style: .secondary,
                        isDisabled: availability != .available,
                        action: remapAction
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spatial-guidance-configuration-card")
    }

    private var status: String {
        if availability != .available { return "INDISPONÍVEL" }
        return hasReference ? "CENA SALVA" : "NÃO CONFIGURADO"
    }

    private var title: String {
        if availability != .available { return "Orientação espacial indisponível" }
        return hasReference ? "Posição do tripé salva" : "Mapeamento espacial"
    }

    private var detail: String {
        switch availability {
        case .available:
            hasReference
                ? "Navegue pela cena para reencontrar a base e a direção da câmera."
                : "Mapeie o local, marque o centro da base e indique a direção da câmera."
        case .moduleUnavailable:
            "Por enquanto, este recurso está disponível somente no Repeatable."
        case .temporarilyUnavailable:
            "O iPhone precisa esfriar antes de iniciar um mapeamento espacial."
        case .hardwareUnavailable, .performanceUnavailable:
            "O timelapse continua disponível sem orientação espacial."
        }
    }

    private var actionTitle: String {
        hasReference ? "Navegar cena" : "Criar mapa espacial"
    }

    private var statusColor: Color {
        availability == .available ? theme.accent : theme.muted
    }
}

struct SpatialGuidanceProjectTab: View {
    let project: CameraProject

    @State private var reference: SpatialReferenceBundle?
    @State private var mode: SpatialGuidanceFlowMode?

    private let store: SpatialReferenceStore
    private let configuration: CameraeNextCaptureConfiguration
    private let theme = CameraeNextTheme(workflow: .repeatable)

    init(project: CameraProject) {
        self.project = project
        let store = SpatialReferenceStore(projectDirectory: project.directoryURL)
        let summaries = TimelapseSessionStore(project: project).sessionSummaries()
        let profile = try? ProjectCaptureConfigurationStore(
            projectDirectory: project.directoryURL
        ).loadProfileOrMigrate(module: project.module, summaries: summaries)
        self.store = store
        configuration = profile?.selectedConfiguration ?? .repeatableDefault
        _reference = State(initialValue: try? store.load())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Group {
                    if let image = referencePreviewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 560)
                            .frame(height: 385)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(theme.border, lineWidth: 1)
                            }
                            .accessibilityLabel("Imagem de referência da posição do tripé")
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 34, weight: .light))
                            Text("Nenhuma posição de tripé salva")
                                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                        }
                        .foregroundStyle(theme.muted)
                        .frame(height: 180)
                    }
                }
                .frame(maxWidth: .infinity)

                tripodActions
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $mode) { activeMode in
            SpatialGuidanceFlowView(
                mode: activeMode,
                project: project,
                configuration: configuration,
                onReferenceSaved: {
                    reference = try? store.load()
                },
                onContinueWithoutReference: {
                    mode = nil
                },
                onAlignedCapture: {
                    mode = nil
                },
                onDismiss: {
                    mode = nil
                }
            )
        }
    }

    private var tripodActions: some View {
        CameraeNextCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                Text(reference == nil ? "NÃO CONFIGURADO" : "POSIÇÃO SALVA")
                    .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.accent)
                Text(reference == nil ? "Mapeamento espacial" : "Tripé de referência")
                    .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                CameraeNextActionButton(
                    title: reference == nil ? "Criar mapa espacial" : "Navegar cena",
                    systemImage: nil,
                    theme: theme,
                    style: reference == nil ? .primary : .secondary,
                    action: openGuide
                )
                if reference != nil {
                    CameraeNextActionButton(
                        title: "Mapear novamente",
                        systemImage: nil,
                        theme: theme,
                        style: .secondary,
                        action: { mode = .createReference }
                    )
                }
            }
        }
    }

    private var referencePreviewImage: UIImage? {
        reference?.keyframes.last.flatMap(UIImage.init(data:))
    }

    private func openGuide() {
        if let reference {
            mode = .relocalize(reference)
        } else {
            mode = .createReference
        }
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

            if !model.phase.showsLiveCamera {
                CameraeColor.captureScrim
                    .ignoresSafeArea()
            }

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
            switch mode {
            case .createReference:
                model.startMapping()
            case .relocalize(let reference):
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
            case .idle, .initializingMapping:
                busyPanel(
                    title: "Preparando câmera",
                    detail: "Iniciando o LiDAR e reconhecendo o chão ao redor do tripé."
                )
            case .readyToStartMapping:
                mappingStartPanel
            case .mapping, .insufficientCoverage:
                mappingPanel
            case .reviewingScene:
                busyPanel(
                    title: "Captura suficiente",
                    detail: "Preparando a marcação do tripé."
                )
            case .selectingTripodBase:
                tripodBaseSelectionPanel(hasSelection: false)
            case .tripodBaseSelected:
                tripodBaseSelectionPanel(hasSelection: true)
            case .selectingTripodDirection:
                tripodDirectionSelectionPanel(hasSelection: false)
            case .tripodDirectionSelected:
                tripodDirectionSelectionPanel(hasSelection: true)
            case .readyToMount:
                busyPanel(
                    title: "Preparando cena",
                    detail: "Validando a posição e a direção do tripé."
                )
            case .saving:
                busyPanel(
                    title: "Salvando cena",
                    detail: "Arquivando mapa, posição, direção e imagens de referência."
                )
            case .saved:
                savedPanel
            case .relocalizing:
                relocalizationPanel
            case .positioning:
                navigationPanel
            case .aligned:
                navigationPanel
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

    private var mappingStartPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialStatusBadgeView(label: "ARKIT PRONTO", tone: .success)
            Text("Posicione-se para começar")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text("Confira se o tripé, o chão e os elementos fixos importantes estão visíveis. A captura só começa após sua confirmação.")
                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            captureAction(title: "Iniciar captura", style: .primary) {
                model.beginSceneCapture()
            }
            captureAction(title: "Reiniciar local", style: .secondary) {
                model.restartLocalCapture()
            }
        }
    }

    private var mappingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialProgressCardView(
                status: model.mappingQuality.canSave ? "MAPA PRONTO" : "MAPEANDO",
                title: model.mappingQuality.canDefineScene ? "Captura suficiente" : "Circule o tripé",
                detail: missingRequirementsDescription,
                progress: model.mappingQuality.progress,
                tone: model.mappingQuality.canDefineScene ? .success : .accent
            )
            Text("Ao atingir o mínimo confiável, a captura termina automaticamente e você marca a posição do tripé.")
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            captureAction(title: "Reiniciar local", style: .secondary) {
                model.restartLocalCapture()
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

    private func tripodDirectionSelectionPanel(hasSelection: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialStatusBadgeView(
                label: hasSelection ? "DIREÇÃO MARCADA" : "DEFINA A DIREÇÃO",
                tone: hasSelection ? .success : .accent
            )
            Text(hasSelection ? "Confira a linha da câmera" : "Toque à frente do tripé")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text(
                hasSelection
                    ? "O tripé padrão mostra tubo, pernas e orientação. Arraste a ponta ou toque em qualquer parte mapeada para ajustar o ângulo."
                    : "Calculando uma direção inicial a partir da sua posição."
            )
            .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
            .foregroundStyle(CameraeColor.captureForegroundMuted)

            if hasSelection {
                captureAction(title: "Confirmar direção", style: .primary) {
                    Task {
                        model.confirmTripodDirection()
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
    }

    private var savedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpatialStatusBadgeView(label: "CENA SALVA", tone: .success)
            Text("Posição memorizada")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text("O centro da base e a direção da câmera foram salvos. O mapa anterior foi preservado em “previous” quando existia.")
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
            Text("Repita o movimento da primeira visita. O ponto do tripé aparece quando a cena for reconhecida.")
                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            ProgressView()
                .tint(CameraeColor.captureForeground)
        }
    }

    private var navigationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpatialStatusBadgeView(label: "CENA LOCALIZADA", tone: .success)
            Text("Encontre o ponto")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
            Text("Sobreponha a base ao ponto e use o tripé fantasma e a seta para recuperar a orientação.")
                .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(CameraeColor.captureForegroundMuted)
            captureAction(title: "Concluir navegação", style: .primary) {
                model.stop()
                onAlignedCapture()
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
        case .createReference: "Mapeie a cena"
        case .relocalize: "Volte ao mesmo lugar"
        }
    }

    private var missingRequirementsDescription: String {
        let missing = model.mappingQuality.missingRequirements
        if missing.contains(.tracking) { return "Mova o iPhone mais devagar para recuperar o tracking." }
        if missing.contains(.coverage) { return "Inclua mais chão e objetos fixos ao redor do tripé." }
        if missing.contains(.detail) { return "Aproxime-se de superfícies com textura e boa luz." }
        if missing.contains(.keyframes) { return "Continue por mais alguns segundos para registrar referências." }
        return "Cobertura suficiente para definir a cena."
    }

    private var currentOrientation: SpatialCaptureOrientation {
        switch UIDevice.current.orientation {
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: .portrait
        }
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
