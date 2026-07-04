import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var camera: CameraController
    private let project: CameraProject
    private let onDeleteProject: () throws -> Void

    @State private var timelapseIntervalSeconds = 5.0
    @State private var astroIntervalSeconds = 1.0
    @State private var astroBatchSize = 30.0
    @State private var usesAutomaticAstroExposure = true
    @State private var isControlsVisible = true
    @State private var isShowingExporter = false
    @State private var shareURL: URL?
    @State private var processingSession: TimelapseSession?

    init(project: CameraProject, onDeleteProject: @escaping () throws -> Void = {}) {
        self.project = project
        self.onDeleteProject = onDeleteProject
        _camera = StateObject(wrappedValue: CameraController(project: project))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                if isControlsVisible {
                    controls
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await camera.start()
        }
        .sheet(isPresented: $isShowingExporter) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
        .navigationDestination(item: $processingSession) { session in
            AstroProcessingView(session: session) {
                processingSession = nil
            } onDeleteProject: {
                try onDeleteProject()
            }
        }
        .onChange(of: camera.completedSession) { _, session in
            processingSession = session
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 18, weight: .semibold))
                Text(camera.status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isControlsVisible.toggle()
                }
            } label: {
                Image(systemName: isControlsVisible ? "eye.slash" : "eye")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(isControlsVisible ? "Esconder controles" : "Mostrar controles")

            Button {
                Task {
                    await camera.exportLastSession()
                    shareURL = camera.lastExportURL
                    isShowingExporter = shareURL != nil
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .disabled(camera.currentSession == nil)
            .accessibilityLabel("Exportar ZIP")
        }
        .foregroundStyle(.white)
        .shadow(radius: 12)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    HStack {
                        MetricPill(title: "Originais", value: "\(camera.frameCount)")
                        MetricPill(title: "Bons", value: "\(camera.astroCompositeFrameCount)")
                        MetricPill(title: "Lote", value: camera.astroBatchProgressLabel)
                    }

                    HStack {
                        MetricPill(title: "Fase", value: camera.astroExposurePhaseLabel)
                        MetricPill(title: "Base", value: camera.baseExposureLabel)
                        MetricPill(title: "Ultima", value: camera.lastCapturedExposureLabel)
                    }

                    AstroBatchPreview(url: camera.astroPreviewURL)

                    Toggle(isOn: $usesAutomaticAstroExposure) {
                        Label("Auto -> Astro", systemImage: "camera.aperture")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(camera.isTimelapseRunning)

                    if usesAutomaticAstroExposure {
                        ControlSlider(
                            title: "Intervalo timelapse",
                            value: $timelapseIntervalSeconds,
                            range: 2...120,
                            step: 1,
                            suffix: "s",
                            isDisabled: camera.isTimelapseRunning
                        )
                    }

                    ControlSlider(
                        title: "Intervalo astro",
                        value: $astroIntervalSeconds,
                        range: 1...10,
                        step: 1,
                        suffix: "s",
                        isDisabled: camera.isTimelapseRunning
                    )

                    ControlSlider(
                        title: "Capturas por frame",
                        value: $astroBatchSize,
                        range: 5...30,
                        step: 1,
                        suffix: "",
                        isDisabled: camera.isTimelapseRunning
                    )
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 260)

            Button {
                Task {
                    await camera.toggleAstroBatchCapture(
                        timelapseInterval: timelapseIntervalSeconds,
                        astroInterval: astroIntervalSeconds,
                        batchSize: Int(astroBatchSize),
                        usesAutomaticExposure: usesAutomaticAstroExposure
                    )
                }
            } label: {
                Label(
                    camera.isTimelapseRunning ? "Parar" : "Iniciar lotes astro",
                    systemImage: camera.isTimelapseRunning ? "stop.fill" : "timer"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(camera.isTimelapseRunning ? .red : .blue)
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.top, 8)
    }
}

private struct AstroBatchPreview: View {
    let url: URL?

    var body: some View {
        if let url, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Label("Ultimo frame bom", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ControlSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let suffix: String
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(displayValue)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
            }

            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }

    private var displayValue: String {
        if suffix.isEmpty {
            return String(format: "%.0f", value)
        }

        return String(format: "%.1f%@", value, suffix)
    }
}
