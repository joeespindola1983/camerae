import SwiftUI
import UIKit

struct CameraeNextAstroPhotoResultView: View {
    let session: TimelapseSession
    let onClose: () -> Void

    @State private var isShowingIdentification = false
    private let theme = CameraeNextTheme(workflow: .astro)

    private var resultURL: URL? {
        astroResultURLs(in: session).first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    if let resultURL, let image = UIImage(contentsOfFile: resultURL.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(theme.border, lineWidth: 1)
                            }
                            .frame(maxHeight: 560)

                        CameraeNextCard(theme: theme) {
                            HStack(spacing: 10) {
                                resultMetric("Originais", "\(originalFrameCount(in: session))")
                                resultMetric("Stack", "1")
                                resultMetric("Formato", resultURL.pathExtension.uppercased())
                            }
                        }

                        CameraeNextActionButton(
                            title: "Identificar céu",
                            systemImage: "scope",
                            theme: theme
                        ) {
                            isShowingIdentification = true
                        }

                        ShareLink(item: resultURL) {
                            Label("Compartilhar foto", systemImage: "square.and.arrow.up")
                                .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .body))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    } else {
                        ContentUnavailableView(
                            "Resultado indisponível",
                            systemImage: "photo.badge.exclamationmark",
                            description: Text("Os originais foram preservados, mas o stack final não foi encontrado.")
                        )
                        .foregroundStyle(theme.muted)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Foto Astro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Voltar")
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $isShowingIdentification) {
            if let resultURL {
                CameraeNextCelestialIdentificationView(
                    imageURL: resultURL,
                    onClose: { isShowingIdentification = false }
                )
            }
        }
    }

    private func resultMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom("DMMono-Regular", size: 14, relativeTo: .subheadline))
                .foregroundStyle(theme.accent)
            Text(title)
                .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2))
                .foregroundStyle(theme.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CameraeNextCelestialIdentificationView: View {
    let imageURL: URL
    let onClose: () -> Void

    @State private var enabledLayers = Set(CelestialLayerKind.allCases)
    @State private var solution: CelestialPlateSolution?
    @State private var annotations: [CelestialAnnotation] = []
    @State private var isSolving = true
    @State private var errorMessage: String?

    private let theme = CameraeNextTheme(workflow: .astro)
    private let store = CelestialAnnotationStore()

    private var image: UIImage? {
        UIImage(contentsOfFile: imageURL.path)
    }

    private var imageAspectRatio: Double {
        guard let size = image?.size, size.height > 0 else { return 4.0 / 3.0 }
        return size.width / size.height
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 12) {
                    if let image {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()

                            GeometryReader { proxy in
                                ForEach(visibleAnnotations) { annotation in
                                    annotationLabel(annotation)
                                        .position(
                                            x: annotation.normalizedX * proxy.size.width,
                                            y: annotation.normalizedY * proxy.size.height
                                        )
                                }
                            }
                        }
                        .aspectRatio(imageAspectRatio, contentMode: .fit)
                    }

                    layerPanel
                }
                .padding(.horizontal, 12)

                if isSolving {
                    CameraeNextOperationOverlay(
                        state: .processing(
                            title: "Mapeando o céu",
                            detail: "Plate solving offline",
                            canCancel: false
                        ),
                        theme: theme,
                        onCancel: {}
                    )
                }
            }
            .navigationTitle("Identificação celeste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salvar", action: save)
                        .disabled(solution == nil)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadOrSolve() }
        .alert("Não foi possível identificar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var visibleAnnotations: [CelestialAnnotation] {
        annotations.filter { enabledLayers.contains($0.kind) }
    }

    private var layerPanel: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 8) {
                HStack {
                    CameraeNextSectionLabel(title: "Camadas", theme: theme)
                    Spacer()
                    if let solution {
                        Text("\(Int((solution.confidence * 100).rounded()))%")
                            .font(.custom("DMMono-Regular", size: 12, relativeTo: .caption))
                            .foregroundStyle(theme.accent)
                    }
                }

                HStack(spacing: 6) {
                    ForEach(CelestialLayerKind.allCases) { layer in
                        Button {
                            if enabledLayers.contains(layer) {
                                enabledLayers.remove(layer)
                            } else {
                                enabledLayers.insert(layer)
                            }
                        } label: {
                            Label(layer.title, systemImage: layer.systemImage)
                                .font(.custom("Outfit-Medium", size: 11, relativeTo: .caption))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .foregroundStyle(enabledLayers.contains(layer) ? Color.white : theme.muted)
                                .background(
                                    enabledLayers.contains(layer) ? layer.color : theme.surface,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func annotationLabel(_ annotation: CelestialAnnotation) -> some View {
        VStack(spacing: 2) {
            Circle()
                .fill(annotation.kind.color)
                .frame(width: 8, height: 8)
                .overlay { Circle().stroke(.white, lineWidth: 1) }
            Text(annotation.displayName)
                .font(.custom("Outfit-SemiBold", size: 10, relativeTo: .caption2))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.72), in: Capsule())
        }
    }

    @MainActor
    private func loadOrSolve() async {
        defer { isSolving = false }
        do {
            if let document = try store.load(for: imageURL) {
                solution = document.plateSolution
                enabledLayers = document.enabledLayers
                annotations = document.annotations
                return
            }

            let solved = try await Task.detached(priority: .userInitiated) {
                try AstroPhotoPlateSolvingService().solve(imageURL: imageURL)
            }.value
            solution = solved
            annotations = CelestialAnnotationEngine.annotations(
                objects: CelestialDeepSkyCatalog.principalObjects
                    + CelestialSolarSystemCatalog.objects(at: sessionCaptureDate),
                solution: solved,
                enabledLayers: enabledLayers,
                imageAspectRatio: imageAspectRatio
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var sessionCaptureDate: Date {
        (try? imageURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }

    private func save() {
        guard let solution else { return }
        do {
            try store.save(
                CelestialAnnotationDocument(
                    sourceAssetIdentifier: imageURL.lastPathComponent,
                    plateSolution: solution,
                    enabledLayers: enabledLayers,
                    annotations: annotations
                ),
                for: imageURL
            )
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func astroResultURLs(in session: TimelapseSession) -> [URL] {
    let directory = session.directoryURL.appendingPathComponent("Astro Frames", isDirectory: true)
    return ((try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
    )) ?? [])
    .filter { $0.lastPathComponent.hasPrefix("astro_frame_") && $0.pathExtension.lowercased() == "jpg" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func originalFrameCount(in session: TimelapseSession) -> Int {
    ((try? FileManager.default.contentsOfDirectory(
        at: session.directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey]
    )) ?? [])
    .filter { $0.lastPathComponent.hasPrefix("frame_") }
    .count
}

private extension CelestialLayerKind {
    var title: String {
        switch self {
        case .planets: "Planetas"
        case .nebulae: "Nebulosas"
        case .galaxies: "Galáxias"
        }
    }

    var systemImage: String {
        switch self {
        case .planets: "circle.grid.cross"
        case .nebulae: "cloud"
        case .galaxies: "hurricane"
        }
    }

    var color: Color {
        switch self {
        case .planets: CameraeColor.accentAstro
        case .nebulae: Color(red: 0.65, green: 0.36, blue: 0.95)
        case .galaxies: Color(red: 0.2, green: 0.76, blue: 0.55)
        }
    }
}
