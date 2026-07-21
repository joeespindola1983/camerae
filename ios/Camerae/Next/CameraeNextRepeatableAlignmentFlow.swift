import Foundation
import SwiftUI
import UIKit

enum CameraeNextRepeatableAlignmentModel: String, Codable, CaseIterable, Hashable, Sendable {
    case position
    case automatic
    case perspectiveAndDeformation

    var title: String {
        switch self {
        case .position: "Só posição"
        case .automatic: "Automático"
        case .perspectiveAndDeformation: "Perspectiva e deformação"
        }
    }

    var detail: String {
        switch self {
        case .position: "Translação X/Y · menor crop"
        case .automatic: "Posição, rotação e escala · recomendado"
        case .perspectiveAndDeformation: "Ainda não disponível"
        }
    }
}

enum CameraeNextRepeatableVideoAlignmentScope: String, Codable, CaseIterable, Hashable, Sendable {
    case constantReframe
    case temporalStabilization

    var title: String {
        switch self {
        case .constantReframe: "Reenquadrar o clipe"
        case .temporalStabilization: "Estabilizar ao longo do vídeo"
        }
    }

    var detail: String {
        switch self {
        case .constantReframe: "Uma correção constante para o vídeo inteiro"
        case .temporalStabilization: "Transformações temporais · em desenvolvimento"
        }
    }
}

struct CameraeNextRepeatableAlignmentSettings: Codable, Equatable, Hashable, Sendable {
    var isEnabled: Bool
    var model: CameraeNextRepeatableAlignmentModel
    var videoScope: CameraeNextRepeatableVideoAlignmentScope
    var maximumCropFraction: Double

    static let timelapseDefault = Self(
        isEnabled: true,
        model: .automatic,
        videoScope: .constantReframe,
        maximumCropFraction: 0.20
    )

    static let videoDefault = Self(
        isEnabled: true,
        model: .automatic,
        videoScope: .constantReframe,
        maximumCropFraction: 0.20
    )
}

struct CameraeNextRepeatableAlignmentSetupPresentation: Equatable, Sendable {
    let navigationTitle: String
    let headline: String
    let detail: String
    let availableModels: [CameraeNextRepeatableAlignmentModel]
    let unavailableModel: CameraeNextRepeatableAlignmentModel
    let showsVideoScope: Bool
    let availableVideoScopes: [CameraeNextRepeatableVideoAlignmentScope]
    let unavailableVideoScope: CameraeNextRepeatableVideoAlignmentScope

    init(captureKind: RepeatableCaptureKind, settings: CameraeNextRepeatableAlignmentSettings) {
        let isVideo = captureKind == .video
        navigationTitle = isVideo ? "Alinhamento do vídeo" : "Alinhamento do timelapse"
        headline = isVideo ? "Corrigir o enquadramento do vídeo" : "Corrigir antes de gerar o vídeo"
        detail = isVideo
            ? "A correção disponível é aplicada ao clipe inteiro durante uma única exportação."
            : "A análise usa os frames originais e aplica a correção durante uma única geração do MP4."
        availableModels = [.position, .automatic]
        unavailableModel = .perspectiveAndDeformation
        showsVideoScope = isVideo
        availableVideoScopes = [.constantReframe]
        unavailableVideoScope = .temporalStabilization
    }
}

struct CameraeNextRepeatableAlignmentSettingsStore {
    private struct Document: Codable {
        var timelapse: CameraeNextRepeatableAlignmentSettings
        var video: CameraeNextRepeatableAlignmentSettings

        static let defaults = Self(timelapse: .timelapseDefault, video: .videoDefault)
    }

    let projectDirectoryURL: URL

    private var fileURL: URL {
        projectDirectoryURL.appendingPathComponent("repeatable_alignment.json")
    }

    func load(for captureKind: RepeatableCaptureKind) throws -> CameraeNextRepeatableAlignmentSettings {
        let document = try loadDocument()
        return captureKind == .video ? document.video : document.timelapse
    }

    func save(_ settings: CameraeNextRepeatableAlignmentSettings, for captureKind: RepeatableCaptureKind) throws {
        try FileManager.default.createDirectory(at: projectDirectoryURL, withIntermediateDirectories: true)
        var document = try loadDocument()
        if captureKind == .video {
            document.video = settings
        } else {
            document.timelapse = settings
        }
        let data = try JSONEncoder().encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    private func loadDocument() throws -> Document {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .defaults }
        return try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
    }
}

struct CameraeNextRepeatableAlignmentReviewPresentation: Equatable, Sendable {
    let totalFrames: Int
    let appliedFrames: Int
    let reviewFrames: Int
    let confidence: Double
    let cropFraction: Double

    var readyLabel: String { "PRONTO · \(totalFrames) FRAMES" }
    var confidenceLabel: String {
        "CONFIANÇA \(percent(confidence)) · \(appliedFrames) APLICADOS · \(reviewFrames) REVISÃO"
    }
    var cropLabel: String { "Crop estimado: \(percent(cropFraction))" }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

enum CameraeNextRepeatableAlignmentProcessingStage: Int, CaseIterable, Sendable {
    case analyzing = 1
    case correctingFrames = 2
    case generatingMP4 = 3

    var title: String {
        switch self {
        case .analyzing: "Analisando alinhamento"
        case .correctingFrames: "Corrigindo quadros"
        case .generatingMP4: "Gerando MP4"
        }
    }
}

struct CameraeNextRepeatableAlignmentProgressPresentation: Equatable, Sendable {
    let stage: CameraeNextRepeatableAlignmentProcessingStage
    let completedFrames: Int
    let totalFrames: Int
    let remainingSeconds: Int?

    var progress: Double {
        guard totalFrames > 0 else { return 0 }
        return min(max(Double(completedFrames) / Double(totalFrames), 0), 1)
    }
    var stageLabel: String { "ETAPA \(stage.rawValue) DE 3" }
    var title: String { stage.title }
    var percentageLabel: String { "\(Int((progress * 100).rounded()))%" }
    var detailLabel: String {
        let remaining = remainingSeconds.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? "--:--"
        return "\(completedFrames) / \(totalFrames) FRAMES · \(remaining) RESTANTE"
    }
}

struct CameraeNextRepeatableAlignmentSetupView: View {
    let captureKind: RepeatableCaptureKind
    let onSave: (CameraeNextRepeatableAlignmentSettings) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings: CameraeNextRepeatableAlignmentSettings

    private let theme = CameraeNextTheme(workflow: .repeatable)

    init(
        captureKind: RepeatableCaptureKind,
        settings: CameraeNextRepeatableAlignmentSettings,
        onSave: @escaping (CameraeNextRepeatableAlignmentSettings) -> Void
    ) {
        self.captureKind = captureKind
        self.onSave = onSave
        _settings = State(initialValue: settings)
    }

    private var presentation: CameraeNextRepeatableAlignmentSetupPresentation {
        .init(captureKind: captureKind, settings: settings)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("ALINHAMENTO")
                        Text(presentation.headline)
                            .font(.custom("Outfit-SemiBold", size: 18, relativeTo: .headline))
                            .foregroundStyle(theme.text)
                        Text(presentation.detail)
                            .font(.custom("Outfit-Regular", size: 12, relativeTo: .footnote))
                            .foregroundStyle(theme.muted)

                        enabledCard

                        if presentation.showsVideoScope {
                            sectionLabel("ESCOPO DO VÍDEO")
                            optionGroup(
                                available: presentation.availableVideoScopes,
                                unavailable: presentation.unavailableVideoScope,
                                selection: $settings.videoScope,
                                title: \.title,
                                detail: \.detail
                            )
                            sectionLabel("MODELO DE CORREÇÃO")
                            modelPickerCard
                        } else {
                            sectionLabel("MODELO DE CORREÇÃO")
                            optionGroup(
                                available: presentation.availableModels,
                                unavailable: presentation.unavailableModel,
                                selection: $settings.model,
                                title: \.title,
                                detail: \.detail
                            )
                            referenceSummary
                        }

                        CameraeNextActionButton(
                            title: "Salvar alinhamento",
                            systemImage: nil,
                            theme: theme
                        ) {
                            onSave(settings)
                        }

                        Text(captureKind == .video
                             ? "Referência: imagem do projeto · crop automático até 20%."
                             : "As configurações podem ser alteradas antes de gerar o MP4.")
                            .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2))
                            .foregroundStyle(theme.muted)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(presentation.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Voltar")
                }
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(.light)
    }

    private var enabledCard: some View {
        CameraeNextCard(theme: theme) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(captureKind == .video ? "Alinhar vídeo" : "Alinhar captura")
                        .font(.custom("Outfit-SemiBold", size: 12, relativeTo: .footnote))
                    Text(settings.isEnabled ? "Ativo para esta sessão" : "Desativado para esta sessão")
                        .font(.custom("Outfit-Regular", size: 12, relativeTo: .footnote))
                }
                .foregroundStyle(theme.text)
                Spacer()
                Toggle("", isOn: $settings.isEnabled)
                    .labelsHidden()
                    .frame(minWidth: 56, minHeight: 44)
            }
        }
    }

    private var modelPickerCard: some View {
        CameraeNextCard(theme: theme) {
            HStack {
                Text("Modelo")
                    .font(.custom("Outfit-SemiBold", size: 12, relativeTo: .footnote))
                Spacer()
                Picker("Modelo", selection: $settings.model) {
                    ForEach(presentation.availableModels, id: \.self) { model in
                        Text(model.title).tag(model)
                    }
                }
                .pickerStyle(.menu)
            }
            .foregroundStyle(theme.text)
        }
    }

    private var referenceSummary: some View {
        CameraeNextCard(theme: theme) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Referência").font(.custom("Outfit-SemiBold", size: 12, relativeTo: .footnote))
                    Text("Imagem do projeto").font(.custom("Outfit-Regular", size: 12, relativeTo: .footnote))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("CROP AUTOMÁTICO")
                    Text("ATÉ \(Int(settings.maximumCropFraction * 100))%")
                }
                .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                .foregroundStyle(theme.accent)
            }
            .foregroundStyle(theme.text)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
            .tracking(1.8)
            .foregroundStyle(theme.muted)
    }

    private func optionGroup<Value: Hashable>(
        available: [Value],
        unavailable: Value,
        selection: Binding<Value>,
        title: KeyPath<Value, String>,
        detail: KeyPath<Value, String>
    ) -> some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 12) {
                ForEach(available, id: \.self) { value in
                    optionRow(
                        title: value[keyPath: title],
                        detail: value[keyPath: detail],
                        isSelected: selection.wrappedValue == value,
                        isEnabled: settings.isEnabled
                    ) { selection.wrappedValue = value }
                }
                optionRow(
                    title: unavailable[keyPath: title],
                    detail: unavailable[keyPath: detail],
                    isSelected: false,
                    isEnabled: false,
                    action: {}
                )
            }
        }
        .opacity(settings.isEnabled ? 1 : 0.58)
    }

    private func optionRow(
        title: String,
        detail: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.custom("Outfit-SemiBold", size: 12, relativeTo: .footnote))
                    Text(detail).font(.custom("Outfit-Regular", size: 12, relativeTo: .footnote))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : theme.text)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(isSelected ? theme.accent : theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? theme.accent : theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.62)
    }
}

struct CameraeNextRepeatableAlignmentReviewView: View {
    let imageURL: URL?
    let presentation: CameraeNextRepeatableAlignmentReviewPresentation
    let onApply: () -> Void
    let onGenerateWithoutAlignment: () -> Void

    private let theme = CameraeNextTheme(workflow: .repeatable)

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        sectionLabel("REVISÃO")
                        Spacer()
                        sectionLabel(presentation.readyLabel).foregroundStyle(theme.accent)
                    }
                    comparison
                    resultCard
                    cropCard
                    CameraeNextActionButton(title: "Aplicar e gerar MP4", systemImage: nil, theme: theme, action: onApply)
                    Button("Gerar sem alinhamento", action: onGenerateWithoutAlignment)
                        .font(.custom("Outfit-SemiBold", size: 12, relativeTo: .footnote))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
        }
        .navigationTitle("Revisar alinhamento")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
        .preferredColorScheme(.light)
    }

    private var comparison: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let imageURL, let image = UIImage(contentsOfFile: imageURL.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(theme.surface)
                        .overlay { Image(systemName: "photo").font(.largeTitle).foregroundStyle(theme.muted) }
                }
            }
            .frame(height: 250)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(theme.accent, lineWidth: 2).padding(20)
            }
            Text("Depois")
                .font(.custom("Outfit-SemiBold", size: 11, relativeTo: .caption))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Color.black.opacity(0.72), in: Capsule())
                .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("●  Alinhamento pronto").font(.custom("Outfit-SemiBold", size: 15, relativeTo: .subheadline)).foregroundStyle(successColor)
            Text("Movimento consistente; seguro para aplicar durante a geração.")
                .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption)).foregroundStyle(theme.muted)
            Text(presentation.confidenceLabel)
                .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2)).foregroundStyle(theme.accent)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(successColor, lineWidth: 1) }
    }

    private var cropCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.cropLabel).font(.custom("Outfit-SemiBold", size: 12, relativeTo: .footnote)).foregroundStyle(theme.accent)
            Text("Pequeno recorte comum para manter os quadros estáveis.")
                .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2)).foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.accent, lineWidth: 1) }
    }

    private func sectionLabel(_ text: String) -> Text {
        Text(text).font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2)).foregroundStyle(theme.muted)
    }

    private var successColor: Color { Color(red: 0.24, green: 0.86, blue: 0.59) }
}

struct CameraeNextRepeatableAlignmentProgressView: View {
    let presentation: CameraeNextRepeatableAlignmentProgressPresentation
    let onCancel: () -> Void

    private let theme = CameraeNextTheme(workflow: .repeatable)

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("PROCESSAMENTO").font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2)).foregroundStyle(theme.muted)
                Text("Preparando seu timelapse").font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3)).foregroundStyle(theme.text)
                Text("Os frames originais permanecem preservados durante todo o processo.")
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .footnote)).foregroundStyle(theme.muted)
                operationCard
                pipelineCard
                CameraeNextActionButton(title: "Cancelar processamento", systemImage: nil, theme: theme, style: .secondary, action: onCancel)
                Text("Você pode sair desta tela. O processamento continuará em segundo plano.")
                    .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2)).foregroundStyle(theme.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(16)
        }
        .navigationTitle("Gerando MP4")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent)
        .preferredColorScheme(.light)
    }

    private var operationCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                Text(presentation.stageLabel).font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2)).foregroundStyle(theme.accent)
                HStack {
                    Text(presentation.title).font(.custom("Outfit-SemiBold", size: 17, relativeTo: .headline))
                    Spacer()
                    Text(presentation.percentageLabel).foregroundStyle(theme.accent)
                }.font(.custom("Outfit-SemiBold", size: 17, relativeTo: .headline)).foregroundStyle(theme.text)
                ProgressView(value: presentation.progress).tint(theme.accent)
                Text(presentation.detailLabel).font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2)).foregroundStyle(theme.muted)
                Text("Aplicando transformações e crop comum nos originais.")
                    .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption)).foregroundStyle(theme.muted)
            }
        }
    }

    private var pipelineCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(alignment: .leading, spacing: 16) {
                pipelineLine(.analyzing)
                pipelineLine(.correctingFrames)
                pipelineLine(.generatingMP4)
            }
        }
    }

    private func pipelineLine(_ stage: CameraeNextRepeatableAlignmentProcessingStage) -> some View {
        let isComplete = stage.rawValue < presentation.stage.rawValue
        let isCurrent = stage == presentation.stage
        let prefix = isComplete ? "✓" : (isCurrent ? "●" : "○")
        let suffix = isComplete ? "CONCLUÍDO" : (isCurrent ? presentation.percentageLabel : "A SEGUIR")
        return HStack {
            Text("\(prefix)  \(stage.title)")
            Spacer()
            Text(suffix)
        }
        .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
        .foregroundStyle(isComplete ? Color(red: 0.24, green: 0.86, blue: 0.59) : (isCurrent ? theme.accent : theme.muted))
    }
}
