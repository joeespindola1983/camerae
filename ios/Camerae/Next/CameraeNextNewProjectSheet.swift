import SwiftUI

struct CameraeNextNewProjectPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let systemImage: String
    let theme: CameraeWorkflowTheme

    init(module: CameraModule) {
        switch module {
        case .repeatable:
            title = CameraeL10n.newProjectTitle(for: module)
            message = CameraeL10n.newProjectMessage(for: module)
            systemImage = "repeat"
            theme = .repeatable
        case .astrophotography:
            title = CameraeL10n.newProjectTitle(for: module)
            message = CameraeL10n.newProjectMessage(for: module)
            systemImage = "sparkles"
            theme = .astro
        case .edit:
            title = CameraeL10n.newProjectTitle(for: module)
            message = CameraeL10n.newProjectMessage(for: module)
            systemImage = "film.stack"
            theme = .editor
        }
    }
}

struct CameraeNextNewProjectLayout: Equatable, Sendable {
    let preferredSheetHeight: CGFloat?
    let contentMaxWidth: CGFloat

    init(isPad: Bool) {
        preferredSheetHeight = isPad ? 620 : nil
        contentMaxWidth = 420
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
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var layout: CameraeNextNewProjectLayout { .init(isPad: isPad) }
    private var supportedDetents: Set<PresentationDetent> {
        if let height = layout.preferredSheetHeight {
            return [.height(height)]
        }
        return [.medium, .large]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                GeometryReader { geometry in
                    ScrollView {
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
                                    .accessibilityIdentifier(CameraeAccessibility.newProjectTitle)
                                Text(presentation.message)
                                    .font(.custom("Outfit-Regular", size: 13, relativeTo: .subheadline))
                                    .foregroundStyle(theme.muted)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 330)
                            }

                            CameraeNextCard(theme: theme) {
                                VStack(alignment: .leading, spacing: 8) {
                                    CameraeNextSectionLabel(title: CameraeL10n.projectName, theme: theme)
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
                                         ? CameraeL10n.defaultNameWillBeUsed(defaultName)
                                         : CameraeL10n.nextCaptureDetails)
                                        .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                                        .foregroundStyle(theme.muted)
                                }
                            }

                            CameraeNextActionButton(
                                title: CameraeL10n.createProject,
                                systemImage: "arrow.right",
                                theme: theme,
                                action: createAction
                            )
                            .accessibilityIdentifier(CameraeAccessibility.createProject)

                            Spacer(minLength: 8)
                        }
                        .frame(maxWidth: layout.contentMaxWidth)
                        .frame(minHeight: geometry.size.height)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CameraeL10n.cancel) { dismiss() }
                }
            }
            .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .presentationDragIndicator(.visible)
        .presentationDetents(supportedDetents)
    }
}
