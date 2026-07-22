import Foundation

enum CameraeLocalization {
    static let developmentLocaleIdentifier = "pt-BR"
    static let supportedLocaleIdentifiers = ["pt-BR", "es", "en", "fr", "de", "ru"]

    static func text(
        _ key: String,
        defaultValue: String,
        locale: Locale? = nil
    ) -> String {
        let bundle = locale.flatMap(localizedBundle(for:)) ?? .main
        return bundle.localizedString(forKey: key, value: defaultValue, table: "Localizable")
    }

    static func format(
        _ key: String,
        defaultValue: String,
        locale: Locale = .current,
        _ arguments: CVarArg...
    ) -> String {
        let format = text(key, defaultValue: defaultValue, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    private static func localizedBundle(for locale: Locale) -> Bundle? {
        let requested = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let candidates = [requested, String(requested.split(separator: "-").first ?? "")]
        for candidate in candidates where !candidate.isEmpty {
            if let path = Bundle.main.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }
}

enum CameraeL10n {
    static var cancel: String { text("common.cancel", "Cancelar") }
    static var okay: String { text("common.ok", "OK") }
    static var error: String { text("common.error", "Erro") }
    static var archive: String { text("project.archive", "Arquivar") }
    static var projectsSection: String { text("project.section", "PROJETOS") }
    static var filterProjects: String { text("project.filter", "Filtrar projetos") }
    static var createProject: String { text("project.create", "Criar projeto") }
    static var newProject: String { text("project.new", "Novo projeto") }
    static var projectName: String { text("project.name", "Nome do projeto") }
    static var recent: String { text("project.filter.recent", "Recentes") }
    static var inProgress: String { text("project.filter.in_progress", "Em andamento") }
    static var completed: String { text("project.filter.completed", "Concluídos") }
    static var statusInProgress: String { text("project.status.in_progress", "EM ANDAMENTO") }
    static var statusCompleted: String { text("project.status.completed", "CONCLUÍDO") }
    static var lastOpened: String { text("project.last_opened", "ÚLTIMO ABERTO") }
    static var noProjectsYet: String { text("project.empty.all", "Nenhum projeto ainda") }
    static var noProjectsInFilter: String { text("project.empty.filter", "Nenhum projeto neste filtro") }
    static var startFirstProject: String { text("project.empty.action", "Comece seu primeiro projeto") }
    static var emptyTemporaryProject: String { text("project.temporary.empty.title", "Projeto temporário vazio") }
    static var removeProject: String { text("project.remove", "Remover projeto") }
    static var emptyTemporaryProjectMessage: String {
        text(
            "project.temporary.empty.message",
            "Nenhuma captura foi criada. Este projeto temporário será removido para manter sua lista organizada."
        )
    }
    static var nextCaptureDetails: String {
        text(
            "project.new.capture_details",
            "Você poderá alterar os detalhes de captura na próxima tela."
        )
    }

    static var moduleRepeatable: String { text("home.module.repeatable", "Repetível") }
    static var moduleAstro: String { text("home.module.astro", "Astrofotografia") }
    static var moduleEdit: String { text("home.module.edit", "Editar") }
    static var configure: String { text("workflow.tab.configure", "Configurar") }
    static var captures: String { text("workflow.tab.captures", "Capturas") }
    static var video: String { text("workflow.mode.video", "Vídeo") }
    static var timelapse: String { text("workflow.mode.timelapse", "Timelapse") }
    static var automatic: String { text("workflow.mode.automatic", "Automática") }
    static var manual: String { text("workflow.mode.manual", "Manual") }
    static var newAstro: String { text("workflow.title.new_astro", "Nova astrofotografia") }
    static var newVideo: String { text("workflow.title.new_video", "Novo vídeo") }
    static var newTimelapse: String { text("workflow.title.new_timelapse", "Novo timelapse") }
    static var captureSection: String { text("workflow.section.capture", "CAPTURA") }
    static var sessionSection: String { text("workflow.section.session", "SESSÃO") }
    static var adjustmentsSection: String { text("workflow.section.adjustments", "AJUSTES") }
    static var astroCaptureSection: String { text("workflow.section.astro_capture", "CAPTURA ASTRO") }
    static var videoSection: String { text("workflow.section.video", "VÍDEO") }
    static var cameraSection: String { text("workflow.section.camera", "CÂMERA") }
    static var planningSection: String { text("workflow.section.planning", "PLANEJAMENTO") }
    static var format: String { text("workflow.summary.format", "FORMATO") }
    static var estimate: String { text("workflow.summary.estimate", "ESTIMATIVA") }
    static var exposure: String { text("workflow.adjustment.exposure", "Exposição") }
    static var interval: String { text("workflow.adjustment.interval", "Intervalo") }
    static var capturesPerFrame: String { text("workflow.adjustment.captures_per_frame", "Capturas/frame") }
    static var resolution: String { text("workflow.video.resolution", "Resolução") }
    static var resolutionHelper: String { text("workflow.video.resolution.helper", "Tamanho do arquivo final") }
    static var quality: String { text("workflow.video.quality", "Qualidade") }
    static var qualityHelper: String { text("workflow.video.quality.helper", "Compressão do MP4") }
    static var qualityStandard: String { text("workflow.video.quality.standard", "Padrão") }
    static var qualityHigh: String { text("workflow.video.quality.high", "Alta") }
    static var qualityMaximum: String { text("workflow.video.quality.maximum", "Máxima") }
    static var preview: String { text("workflow.video.resolution.preview", "Prévia") }
    static var customDurationShort: String { text("workflow.duration.custom.short", "Personal.") }
    static var takePhoto: String { text("workflow.reference.take_photo", "Tirar foto") }
    static var importPhoto: String { text("workflow.reference.import", "Importar") }
    static var replace: String { text("workflow.reference.replace", "Substituir") }
    static var remove: String { text("workflow.reference.remove", "Remover") }
    static var wait: String { text("workflow.reference.wait", "Aguarde") }
    static var chooseAnother: String { text("workflow.reference.choose_another", "Escolher outra") }
    static var openCamera: String { text("workflow.action.open_camera", "Abrir câmera") }
    static var cameraUnavailable: String { text("workflow.action.camera_unavailable", "Câmera indisponível") }
    static var freeSpaceToContinue: String { text("workflow.action.free_space", "Libere espaço para continuar") }
    static var planningUnavailable: String { text("workflow.action.planning_unavailable", "Planejamento indisponível") }
    static var openExistingSessions: String { text("workflow.sessions.open", "Abrir sessões existentes") }
    static var referenceImage: String { text("workflow.reference.title", "Imagem de referência") }
    static var duration: String { text("workflow.duration", "Duração") }
    static var customDuration: String { text("workflow.duration.custom", "Duração personalizada") }
    static var sessionDuration: String { text("workflow.duration.session", "Duração da sessão") }
    static var customDurationMessage: String { text("workflow.duration.custom.message", "Defina por quanto tempo a captura ficará ativa.") }
    static var sessionDurationMessage: String { text("workflow.duration.session.message", "Defina o tempo total disponível para capturas Astro.") }
    static var apply: String { text("common.apply", "Aplicar") }
    static var calculating: String { text("workflow.planning.status.calculating", "CALCULANDO") }
    static var ready: String { text("workflow.planning.status.ready", "PRONTO") }
    static var attention: String { text("workflow.planning.status.warning", "ATENÇÃO") }
    static var blocked: String { text("workflow.planning.status.blocked", "BLOQUEADO") }
    static var adjusted: String { text("workflow.planning.status.adjusted", "AJUSTADO") }
    static var power: String { text("workflow.planning.status.power", "ENERGIA") }
    static var calculatingResources: String { text("workflow.planning.calculating.title", "Calculando espaço e bateria") }
    static var calculatingResourcesDetail: String { text("workflow.planning.calculating.detail", "Estimativa será atualizada antes da captura") }
    static var captureViable: String { text("workflow.planning.ready.title", "Captura viável") }
    static var reducedSpaceMargin: String { text("workflow.planning.warning.title", "Margem de espaço reduzida") }
    static var insufficientSpace: String { text("workflow.planning.blocked.title", "Espaço insuficiente") }
    static var formatAdjusted: String { text("workflow.planning.adjusted.title", "Formato ajustado por compatibilidade") }
    static var formatAdjustedDetail: String { text("workflow.planning.adjusted.detail", "HEIC indisponível · captura será salva em JPEG") }
    static var externalPowerRecommended: String { text("workflow.planning.power.title", "Alimentação externa recomendada") }
    static var externalPowerDetail: String { text("workflow.planning.power.detail", "Sessão longa · conecte o carregador") }
    static var planningCheckFailed: String { text("workflow.planning.error.detail", "Não foi possível verificar espaço e bateria") }
    static var cameraProjectUnavailable: String { text("workflow.camera.locked_unavailable.title", "Câmera do projeto indisponível") }
    static var cameraProject: String { text("workflow.camera.locked.title", "Câmera do projeto") }
    static var noCompatibleCamera: String { text("workflow.camera.unavailable.title", "Nenhuma câmera compatível") }
    static var noCompatibleCameraDetail: String { text("workflow.camera.unavailable.detail", "Revise as permissões ou use outro aparelho") }
    static var cameraReplaced: String { text("workflow.camera.fallback.title", "Câmera substituída") }
    static var onlyMainCamera: String { text("workflow.camera.single.title", "Apenas Principal disponível") }
    static var onlyMainCameraDetail: String { text("workflow.camera.single.detail", "As outras lentes não estão presentes neste aparelho") }
    static var cameraInUse: String { text("workflow.camera.in_use", "Câmera em uso") }
    static var camerasDetected: String { text("workflow.camera.detected", "Câmeras detectadas") }
    static var cameraLockedStatus: String { text("workflow.camera.status.locked", "BLOQUEADA") }
    static var cameraUnavailableStatus: String { text("workflow.camera.status.unavailable", "INDISPONÍVEL") }
    static var cameraAdjustedStatus: String { text("workflow.camera.status.adjusted", "AJUSTADA") }
    static var cameraSingleStatus: String { text("workflow.camera.status.single", "ÚNICA") }
    static var cameraAvailableStatus: String { text("workflow.camera.status.available", "DISPONÍVEL") }
    static var lensUltraWide: String { text("workflow.camera.lens.ultrawide", "Ultra-wide") }
    static var lensMain: String { text("workflow.camera.lens.main", "Principal") }
    static var lensTelephoto: String { text("workflow.camera.lens.telephoto", "Teleobjetiva") }

    static func frameCount(_ count: Int) -> String {
        format("workflow.summary.frames", defaultValue: "%lld frames", Int64(count))
    }

    static func estimatedValue(_ value: String) -> String {
        format("workflow.summary.estimated", defaultValue: "%@ estimado", value)
    }

    static func requiredAvailable(required: String, available: String) -> String {
        format("workflow.planning.capacity", defaultValue: "Necessário %@ · disponível %@", required, available)
    }

    static func captureSize(_ value: String) -> String {
        format("workflow.planning.capture_size", defaultValue: "captura ~%@", value)
    }

    static func videoDuration(_ value: String) -> String {
        format("workflow.planning.video_duration", defaultValue: "Vídeo %@", value)
    }

    static func framesVideo(count: UInt64, duration: String) -> String {
        format("workflow.planning.frames_video", defaultValue: "%lld frames · vídeo %@", Int64(clamping: count), duration)
    }

    static func connectCamera(_ description: String) -> String {
        format("workflow.camera.locked_unavailable.detail", defaultValue: "Conecte um aparelho com %@", description)
    }

    static func unavailableUsing(_ preferred: String, _ selected: String) -> String {
        format("workflow.camera.fallback.detail", defaultValue: "%@ indisponível · usando %@", preferred, selected)
    }

    static func moduleTitle(_ module: CameraModule) -> String {
        switch module {
        case .repeatable: moduleRepeatable
        case .astrophotography: moduleAstro
        case .edit: moduleEdit
        }
    }

    static func openModule(_ title: String) -> String {
        format("home.module.open", defaultValue: "Abrir %@", title)
    }

    static func projectCount(_ count: Int) -> String {
        format("home.projects.count", defaultValue: "Projetos: %lld", Int64(count))
    }

    static func newProject(_ title: String) -> String {
        format("project.new.module", defaultValue: "Novo projeto %@", title)
    }

    static func openProject(_ name: String) -> String {
        format("project.open", defaultValue: "Abrir projeto %@", name)
    }

    static func openedAt(_ date: String) -> String {
        format("project.opened_at", defaultValue: "Aberto %@", date)
    }

    static func createdAt(_ date: String) -> String {
        format("project.created_at", defaultValue: "Criado %@", date)
    }

    static func editProjectDetail(clipCount: Int) -> String {
        format("project.detail.edit", defaultValue: "Clipes: %lld", Int64(clipCount))
    }

    static func captureProjectDetail(sessionCount: Int, frameCount: Int) -> String {
        format(
            "project.detail.capture",
            defaultValue: "Capturas: %lld · Frames: %lld",
            Int64(sessionCount),
            Int64(frameCount)
        )
    }

    static func lastOpenedProject(_ name: String) -> String {
        format("project.last_opened.named", defaultValue: "Último projeto aberto, %@", name)
    }

    static func defaultNameWillBeUsed(_ name: String) -> String {
        format("project.new.default_name", defaultValue: "Será usado: %@", name)
    }

    static func newProjectTitle(for module: CameraModule) -> String {
        switch module {
        case .repeatable: text("project.new.repeatable.title", "Novo projeto Repeatable")
        case .astrophotography: text("project.new.astro.title", "Novo projeto Astro")
        case .edit: text("project.new.edit.title", "Nova montagem")
        }
    }

    static func newProjectMessage(for module: CameraModule) -> String {
        switch module {
        case .repeatable:
            text("project.new.repeatable.message", "Crie um espaço para repetir o mesmo enquadramento ao longo do tempo.")
        case .astrophotography:
            text("project.new.astro.message", "Organize uma sessão noturna e processe suas imagens em um único projeto.")
        case .edit:
            text("project.new.edit.message", "Combine e alinhe os vídeos produzidos no Camerae.")
        }
    }

    private static func text(_ key: String, _ defaultValue: String) -> String {
        CameraeLocalization.text(key, defaultValue: defaultValue)
    }

    private static func format(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        let format = CameraeLocalization.text(key, defaultValue: defaultValue)
        return String(format: format, locale: .current, arguments: arguments)
    }
}

enum CameraeAccessibility {
    static let createProject = "camerae.project.create"
    static let createFirstProject = "camerae.project.empty.create"
    static let newProjectTitle = "camerae.project.new.title"

    static func openModule(_ module: CameraModule) -> String {
        "camerae.module.\(module.rawValue).open"
    }

    static func newProject(_ module: CameraModule) -> String {
        "camerae.project.\(module.rawValue).new"
    }

    static func openProject(_ id: UUID) -> String {
        "camerae.project.\(id.uuidString.lowercased()).open"
    }
}
