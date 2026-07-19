import SwiftUI

struct CameraeNextNewProjectPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let systemImage: String
    let theme: CameraeWorkflowTheme

    init(module: CameraModule) {
        switch module {
        case .repeatable:
            title = "Novo projeto Repeatable"
            message = "Crie um espaço para repetir o mesmo enquadramento ao longo do tempo."
            systemImage = "repeat"
            theme = .repeatable
        case .astrophotography:
            title = "Novo projeto Astro"
            message = "Organize uma sessão noturna e processe suas imagens em um único projeto."
            systemImage = "sparkles"
            theme = .astro
        case .edit:
            title = "Nova montagem"
            message = "Combine e alinhe os vídeos produzidos no Camerae."
            systemImage = "film.stack"
            theme = .editor
        }
    }
}

struct CameraeNextNewProjectSheet: View {
    let module: CameraModule
    @Binding var name: String
    let defaultName: String
    let createAction: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    private var presentation: CameraeNextNewProjectPresentation { .init(module: module) }
    private var theme: CameraeNextTheme { .init(workflow: presentation.theme) }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: 18) {
                    Spacer(minLength: 8)

                    Image(systemName: presentation.systemImage)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 72, height: 72)
                        .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    VStack(spacing: 6) {
                        Text(presentation.title)
                            .font(.custom("Outfit-SemiBold", size: 22, relativeTo: .title2))
                            .foregroundStyle(theme.text)
                        Text(presentation.message)
                            .font(.custom("Outfit-Regular", size: 13, relativeTo: .subheadline))
                            .foregroundStyle(theme.muted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 330)
                    }

                    CameraeNextCard(theme: theme) {
                        VStack(alignment: .leading, spacing: 8) {
                            CameraeNextSectionLabel(title: "Nome do projeto", theme: theme)
                            TextField(defaultName, text: $name)
                                .focused($isNameFocused)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .font(.custom("Outfit-Regular", size: 16, relativeTo: .body))
                                .foregroundStyle(theme.text)
                                .padding(.horizontal, 14)
                                .frame(height: 52)
                                .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isNameFocused ? theme.accent : theme.border, lineWidth: 1)
                                }
                            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? "Será usado: \(defaultName)"
                                 : "Você poderá alterar os detalhes de captura na próxima tela.")
                                .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                                .foregroundStyle(theme.muted)
                        }
                    }

                    CameraeNextActionButton(
                        title: "Criar projeto",
                        systemImage: "arrow.right",
                        theme: theme,
                        action: createAction
                    )

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: 420)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }
}
