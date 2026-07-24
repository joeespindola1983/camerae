import CameraeCore
import CameraeMedia
import SwiftUI
import UIKit

struct CameraeNextAlignmentView: View {
    @ObservedObject var model: CameraeNextAlignmentViewModel
    let document: EditProjectDocument
    let assets: [MediaAssetID: ResolvedMediaAsset]
    let projectReferenceURL: URL?
    let onUseAlignment: () -> Void
    let onContinueWithoutAlignment: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var comparison = CameraeNextAlignmentComparisonMode.split

    private let theme = CameraeNextTheme(workflow: .editor)

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    comparisonView

                    VStack(alignment: .leading, spacing: 8) {
                        CameraeNextSectionLabel(title: "Modo", theme: theme)
                        Picker("Modo de alinhamento", selection: modeBinding) {
                            ForEach(CameraeNextAlignmentMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    stateContent
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Alinhamento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CameraeNextAlignmentStatusChip(status: model.snapshot.status)
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(.dark)
        .task(id: preparationSignature) {
            model.prepare(
                document: document,
                assets: assets,
                projectReferenceURL: projectReferenceURL
            )
        }
        .onDisappear { model.cancel() }
    }

    private var modeBinding: Binding<CameraeNextAlignmentMode> {
        Binding(get: { model.mode }, set: model.setMode)
    }

    private var preparationSignature: String {
        [
            document.items.map(\.id.uuidString).joined(separator: ":"),
            projectReferenceURL?.standardizedFileURL.path ?? "no-reference"
        ].joined(separator: ":")
    }

    private var comparisonView: some View {
        CameraeNextAlignmentComparison(
            mode: comparison,
            previewURL: projectReferenceURL ?? assets.values.first?.url,
            cropPercentage: model.snapshot.cropPercentage
        )
        .frame(height: 250)
        .contentShape(Rectangle())
        .onTapGesture {
            comparison = comparison.next
        }
        .accessibilityHint("Toque para alternar entre antes, depois e comparação dividida")
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.snapshot.status {
        case .off:
            CameraeNextAlignmentMessageCard(
                title: "Alinhamento desligado",
                message: "A sequência será exportada sem correção espacial.",
                color: theme.muted
            )
        case .ready, .stale:
            CameraeNextAlignmentMessageCard(
                title: model.snapshot.status == .stale ? "Resultado desatualizado" : "Pronto para analisar",
                message: model.snapshot.status == .stale
                    ? "A timeline mudou. Analise novamente antes da exportação."
                    : projectReferenceURL == nil
                        ? "Comparamos amostras no início, meio e fim. Seus arquivos originais não são alterados."
                        : "Comparamos cada vídeo com a imagem de referência do projeto. Seus arquivos originais não são alterados.",
                color: model.snapshot.status == .stale ? .yellow : theme.accent
            )
            CameraeNextActionButton(
                title: model.snapshot.status == .stale ? "Analisar novamente" : "Analisar alinhamento",
                systemImage: "viewfinder",
                theme: theme
            ) {
                Task { await model.analyze() }
            }
            Text("A análise é cancelável e será reutilizada enquanto a timeline não mudar.")
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
        case .analyzing:
            CameraeNextAlignmentProgressCard()
            CameraeNextActionButton(
                title: "Cancelar análise",
                systemImage: "xmark",
                theme: theme,
                style: .secondary,
                action: model.cancel
            )
        case .applied:
            resultCard(
                title: "Alinhamento pronto",
                message: "Movimento consistente; seguro para aplicar na exportação.",
                color: .green
            )
            cropCard(color: cropColor)
            CameraeNextActionButton(
                title: "Usar na exportação",
                systemImage: "checkmark",
                theme: theme
            ) {
                onUseAlignment()
                dismiss()
            }
            CameraeNextActionButton(
                title: "Remover alinhamento",
                systemImage: "trash",
                theme: theme,
                style: .quiet
            ) {
                model.removeAlignment()
            }
        case .review:
            resultCard(
                title: "Revisão recomendada",
                message: "Há variação entre amostras. Compare antes de continuar.",
                color: .yellow
            )
            cropCard(color: .yellow)
            CameraeNextActionButton(
                title: "Tentar somente posição",
                systemImage: "move.3d",
                theme: theme
            ) {
                model.setMode(.position)
                Task { await model.analyze() }
            }
            continueWithoutButton
        case .rejected:
            resultCard(
                title: "Não foi possível alinhar",
                message: "Paralaxe ou área útil insuficiente para um resultado estável.",
                color: .red
            )
            CameraeNextActionButton(
                title: "Tentar somente posição",
                systemImage: "move.3d",
                theme: theme
            ) {
                model.setMode(.position)
                Task { await model.analyze() }
            }
            continueWithoutButton
        case .failed:
            resultCard(
                title: "Análise interrompida",
                message: model.snapshot.message ?? "Ocorreu um erro. Os arquivos originais continuam intactos.",
                color: .red
            )
            CameraeNextActionButton(
                title: "Tentar novamente",
                systemImage: "arrow.clockwise",
                theme: theme
            ) {
                Task { await model.analyze() }
            }
            continueWithoutButton
        }
    }

    private var continueWithoutButton: some View {
        CameraeNextActionButton(
            title: "Continuar sem alinhamento",
            systemImage: "arrow.right",
            theme: theme,
            style: .quiet
        ) {
            model.setMode(.off)
            onContinueWithoutAlignment()
            dismiss()
        }
    }

    private func resultCard(title: String, message: String, color: Color) -> some View {
        CameraeNextAlignmentMessageCard(
            title: title,
            message: message,
            color: color,
            metric: metricDescription
        )
    }

    private func cropCard(color: Color) -> some View {
        CameraeNextAlignmentMessageCard(
            title: "Crop estimado: \(model.snapshot.cropPercentage ?? 0)%",
            message: cropMessage,
            color: color
        )
    }

    private var metricDescription: String? {
        guard let confidence = model.snapshot.confidence else { return nil }
        return "Confiança " + confidence.formatted(.percent.precision(.fractionLength(0)))
    }

    private var cropMessage: String {
        (model.snapshot.cropPercentage ?? 0) >= 15
            ? "Confira detalhes nas bordas antes de aplicar."
            : "Pequeno recorte comum para manter todos os quadros estáveis."
    }

    private var cropColor: Color {
        (model.snapshot.cropPercentage ?? 0) >= 15 ? .yellow : .blue
    }
}

private enum CameraeNextAlignmentComparisonMode: CaseIterable {
    case before
    case after
    case split

    var next: Self {
        switch self {
        case .before: .after
        case .after: .split
        case .split: .before
        }
    }
}

private struct CameraeNextAlignmentComparison: View {
    let mode: CameraeNextAlignmentComparisonMode
    let previewURL: URL?
    let cropPercentage: Int?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                preview
                if mode == .before {
                    Color.red.opacity(0.08)
                } else if mode == .after {
                    Color.green.opacity(0.06)
                    cropBoundary.padding(20)
                } else {
                    HStack(spacing: 0) {
                        Color.clear
                        Color.green.opacity(0.10)
                    }
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 3)
                    Circle()
                        .fill(.white)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "arrow.left.and.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(CameraeColor.canvas)
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.custom("Outfit-Medium", size: 12, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(CameraeColor.canvas.opacity(0.78), in: Capsule())
                    .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let previewURL, let image = UIImage(contentsOfFile: previewURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.20, blue: 0.35), Color(red: 0.03, green: 0.06, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 70, weight: .thin))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var cropBoundary: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.green, lineWidth: 2)
    }

    private var label: String {
        switch mode {
        case .before: "Antes"
        case .after: "Depois"
        case .split: "Antes / Depois"
        }
    }
}

private struct CameraeNextAlignmentStatusChip: View {
    let status: CameraeNextAlignmentStatus

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.custom("Outfit-Medium", size: 12, relativeTo: .caption))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(color.opacity(0.14), in: Capsule())
        .overlay { Capsule().stroke(color.opacity(0.55), lineWidth: 1) }
    }

    private var label: String {
        switch status {
        case .off: "Desligado"
        case .ready: "Pronto"
        case .analyzing: "Analisando"
        case .applied: "Aplicado"
        case .review: "Revisar"
        case .rejected: "Rejeitado"
        case .failed: "Erro"
        case .stale: "Desatualizado"
        }
    }

    private var color: Color {
        switch status {
        case .off: CameraeColor.textMuted
        case .ready: .blue
        case .analyzing: CameraeColor.accentEditor
        case .applied: .green
        case .review, .stale: .yellow
        case .rejected, .failed: .red
        }
    }
}

private struct CameraeNextAlignmentMessageCard: View {
    let title: String
    let message: String
    let color: Color
    var metric: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "circle.fill")
                .font(.custom("Outfit-SemiBold", size: 16, relativeTo: .headline))
                .foregroundStyle(CameraeColor.textPrimary)
                .symbolRenderingMode(.monochrome)
                .imageScale(.small)
            Text(message)
                .font(.custom("Outfit-Regular", size: 13, relativeTo: .subheadline))
                .foregroundStyle(CameraeColor.textPrimary.opacity(0.7))
            if let metric {
                Text(metric)
                    .font(.custom("Outfit-Medium", size: 12, relativeTo: .caption))
                    .foregroundStyle(color)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(color.opacity(0.14), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(CameraeColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.55), lineWidth: 1)
        }
        .tint(color)
    }
}

private struct CameraeNextAlignmentProgressCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Analisando alinhamento")
                .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .headline))
                .foregroundStyle(CameraeColor.textPrimary)
            Text("Comparando amostras da sequência…")
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(CameraeColor.textPrimary.opacity(0.7))
            ProgressView()
                .tint(CameraeColor.accentEditor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(CameraeColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CameraeColor.borderStrong, lineWidth: 1)
        }
    }
}
