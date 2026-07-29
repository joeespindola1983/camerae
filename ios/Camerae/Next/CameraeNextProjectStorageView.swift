import CameraeCore
import SwiftUI

struct CameraeNextProjectStorageView: View {
    let project: CameraProject
    let onChanged: () -> Void
    let onRequestProjectDeletion: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var inventory: ProjectStorageInventory?
    @State private var isLoading = true
    @State private var isRemovingFrames = false
    @State private var isConfirmingFrameRemoval = false
    @State private var errorMessage: String?
    @State private var removedSummary: OriginalFrameRemovalSummary?

    private var theme: CameraeNextTheme {
        .init(workflow: project.module == .astrophotography ? .astro : .repeatable)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                if project.module == .astrophotography {
                    ProjectListStarField(color: theme.text)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if isLoading {
                    ProgressView()
                        .tint(theme.accent)
                } else {
                    content
                }
            }
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .task { await loadInventory() }
        .alert("Apagar \(inventory?.removableFrameCount ?? 0) frames?", isPresented: $isConfirmingFrameRemoval) {
            Button(frameRemovalActionTitle, role: .destructive) {
                Task { await removeFrames() }
            }
            Button(CameraeL10n.cancel, role: .cancel) {}
        } message: {
            Text("A imagem de referência, as fotos e os vídeos já gerados serão mantidos. Os frames originais não poderão ser recuperados.")
        }
        .alert(CameraeL10n.error, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(CameraeL10n.okay, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                projectSummaryCard
                storageInventoryCard

                if let removedSummary {
                    cleanupSuccessCard(removedSummary)
                }

                actionCard
            }
            .frame(maxWidth: 620)
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var projectSummaryCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 14) {
                HStack {
                    sectionLabel("CONTEÚDO DO PROJETO")
                    Spacer()
                    Text(formattedBytes(totalProjectBytes))
                        .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                        .tracking(1.8)
                        .foregroundStyle(theme.accent)
                }

                HStack(spacing: 12) {
                    ReferenceThumbnail(
                        imageURL: project.referenceFrameURL,
                        systemImage: "photo",
                        width: 72,
                        height: 72
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Imagem de referência")
                            .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Text((inventory?.referenceCount ?? 0) > 0
                             ? "Mantida para alinhamento"
                             : "Nenhuma referência definida")
                            .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                            .foregroundStyle(theme.muted)
                    }
                    Spacer()
                }
            }
        }
    }

    private var storageInventoryCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 14) {
                inventoryRow(
                    title: "Frames de timelapse",
                    detail: "\(inventory?.removableFrameCount ?? 0) originais",
                    value: formattedBytes(inventory?.removableFrameBytes ?? 0)
                )
                inventoryRow(
                    title: "Vídeos e fotos",
                    detail: "\(inventory?.preservedArtifactCount ?? 0) arquivos preservados",
                    value: formattedBytes(inventory?.preservedBytes ?? 0)
                )
                inventoryRow(
                    title: "Referência",
                    detail: "\(inventory?.referenceCount ?? 0) imagem do projeto",
                    value: (inventory?.referenceCount ?? 0) > 0 ? "MANTER" : "—"
                )
            }
        }
    }

    private func cleanupSuccessCard(_ removed: OriginalFrameRemovalSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("LIMPEZA CONCLUÍDA")
                .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                .tracking(2.1)
                .foregroundStyle(.green)
            Text("\(formattedBytes(removed.knownBytes)) liberados")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                .foregroundStyle(theme.text)
            Text("A referência e os arquivos exportados continuam disponíveis neste projeto.")
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.accent, lineWidth: 1)
        }
    }

    private var actionCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 8) {
                Button {
                    isConfirmingFrameRemoval = true
                } label: {
                    actionRow(
                        title: "Apagar frames do timelapse",
                        detail: "Mantém referência, fotos e vídeos",
                        value: hasRemovableFrames
                            ? "LIBERAR \(formattedBytes(inventory?.removableFrameBytes ?? 0))"
                            : "SEM FRAMES",
                        color: hasRemovableFrames ? theme.accent : theme.muted
                    )
                }
                .buttonStyle(.plain)
                .disabled(!hasRemovableFrames || isRemovingFrames)
                .opacity(hasRemovableFrames ? 1 : 0.48)

                Divider().overlay(theme.border)

                Button(role: .destructive) {
                    onRequestProjectDeletion()
                } label: {
                    actionRow(
                        title: "Excluir projeto",
                        detail: "Remove todo o conteúdo",
                        value: "EXCLUIR",
                        color: .red
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func inventoryRow(title: String, detail: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            Text(value)
                .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                .tracking(1.8)
                .foregroundStyle(theme.accent)
        }
    }

    private func actionRow(
        title: String,
        detail: String,
        value: String,
        color: Color
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            Text(value)
                .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                .tracking(1.8)
                .foregroundStyle(color)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 7)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
            .tracking(2.1)
            .foregroundStyle(theme.muted)
    }

    private var hasRemovableFrames: Bool {
        inventory?.hasRemovableFrames == true
    }

    private var totalProjectBytes: UInt64 {
        (inventory?.removableFrameBytes ?? 0) + (inventory?.preservedBytes ?? 0)
    }

    private var frameRemovalActionTitle: String {
        "Apagar frames e liberar \(formattedBytes(inventory?.removableFrameBytes ?? 0))"
    }

    private func formattedBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    @MainActor
    private func loadInventory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            inventory = try await TimelapseSessionStore(project: project).projectStorageInventory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func removeFrames() async {
        guard !isRemovingFrames else { return }
        isRemovingFrames = true
        defer { isRemovingFrames = false }
        do {
            let store = TimelapseSessionStore(project: project)
            removedSummary = try await store.removeOriginalTimelapseFrames()
            inventory = try await store.projectStorageInventory()
            onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
