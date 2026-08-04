import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onTapToFocus: ((CGPoint) -> Void)?

    init(
        session: AVCaptureSession,
        onTapToFocus: ((CGPoint) -> Void)? = nil
    ) {
        self.session = session
        self.onTapToFocus = onTapToFocus
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapToFocus: onTapToFocus)
    }

    func makeUIView(context: Context) -> PreviewView {
        CameraeCaptureDiagnostics.event(
            "P01 preview.makeUIView",
            "sessionRunning=\(session.isRunning) inputs=\(session.inputs.count) outputs=\(session.outputs.count)"
        )
        let view = PreviewView()
        context.coordinator.previewView = view
        view.addGestureRecognizer(
            UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleFocusTap(_:))
            )
        )
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        CameraeCaptureDiagnostics.event(
            "P02 preview.layer.attached",
            "connection=\(view.previewLayer.connection != nil)"
        )
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            CameraeCaptureDiagnostics.event("P03 preview.session.replaced")
        }
        uiView.previewLayer.session = session
        uiView.updatePreviewOrientation()
        context.coordinator.onTapToFocus = onTapToFocus
    }

    final class Coordinator: NSObject {
        var onTapToFocus: ((CGPoint) -> Void)?
        weak var previewView: PreviewView?

        init(onTapToFocus: ((CGPoint) -> Void)?) {
            self.onTapToFocus = onTapToFocus
        }

        @objc func handleFocusTap(_ recognizer: UITapGestureRecognizer) {
            guard let previewView, let onTapToFocus else { return }
            let layerPoint = recognizer.location(in: previewView)
            onTapToFocus(
                previewView.previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            )
        }
    }
}

final class PreviewView: UIView {
    private var lastLoggedWindowState: Bool?
    private var lastLoggedAngle: CGFloat?
    private var lastLoggedStabilizationMode: AVCaptureVideoStabilizationMode?
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewOrientation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        let isAttached = window != nil
        if lastLoggedWindowState != isAttached {
            CameraeCaptureDiagnostics.event(
                isAttached ? "P04 preview.attachedToWindow" : "P80 preview.detachedFromWindow",
                "bounds=\(bounds.debugDescription) connection=\(previewLayer.connection != nil)"
            )
            lastLoggedWindowState = isAttached
        }
        updatePreviewOrientation()
    }

    func updatePreviewOrientation() {
        guard let connection = previewLayer.connection else {
            if window != nil, previewLayer.connection == nil {
                CameraeCaptureDiagnostics.error("P90 preview.noConnection", "sessionRunning=\(previewLayer.session?.isRunning ?? false)")
            }
            return
        }
        updatePreviewStabilization(connection: connection)
        guard let angle = window?.windowScene?.interfaceOrientation.videoRotationAngle,
              connection.isVideoRotationAngleSupported(angle) else {
            return
        }

        guard lastLoggedAngle != angle else { return }
        connection.videoRotationAngle = angle
        CameraeCaptureDiagnostics.event("P05 preview.orientation", "angle=\(angle)")
        lastLoggedAngle = angle
    }

    private func updatePreviewStabilization(connection: AVCaptureConnection) {
        guard connection.isVideoStabilizationSupported,
              let deviceInput = previewLayer.session?.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) }) else {
            return
        }
        let mode = CameraeVideoStabilizationPolicy.preferredMode(
            for: deviceInput.device.activeFormat
        )
        connection.preferredVideoStabilizationMode = mode
        guard lastLoggedStabilizationMode != mode else { return }
        CameraeCaptureDiagnostics.event(
            "P06 preview.stabilization",
            "preferred=\(mode.rawValue) active=\(connection.activeVideoStabilizationMode.rawValue)"
        )
        lastLoggedStabilizationMode = mode
    }
}

private extension UIInterfaceOrientation {
    var videoRotationAngle: CGFloat? {
        switch self {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            return 180
        case .landscapeRight:
            return 0
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
}
