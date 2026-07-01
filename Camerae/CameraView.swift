import SwiftUI

struct CameraView: View {
    @StateObject private var camera: CameraController
    private let project: CameraProject
    private let onDeleteProject: () throws -> Void

    @State private var intervalSeconds = 5.0
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
                controls
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
        VStack(spacing: 12) {
            HStack {
                MetricPill(title: "Frames", value: "\(camera.frameCount)")
                MetricPill(title: "Base", value: camera.baseExposureLabel)
                MetricPill(title: "Tipo", value: camera.stackProgressLabel)
            }

            HStack {
                MetricPill(title: "Ultima", value: camera.lastCapturedExposureLabel)
                MetricPill(title: "Inicio", value: camera.countdownLabel)
            }

            ControlSlider(
                title: "Intervalometro",
                value: $intervalSeconds,
                range: 2...10,
                step: 1,
                suffix: "s",
                isDisabled: camera.isTimelapseRunning
            )

            Button {
                Task {
                    await camera.toggleTimelapse(interval: intervalSeconds)
                }
            } label: {
                Label(camera.isTimelapseRunning ? "Parar" : "Iniciar timelapse", systemImage: camera.isTimelapseRunning ? "stop.fill" : "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(camera.isTimelapseRunning ? .red : .blue)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.top, 10)
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
                Text(String(format: "%.1f%@", value, suffix))
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
}
