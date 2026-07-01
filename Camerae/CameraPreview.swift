import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.updatePreviewOrientation()
    }
}

final class PreviewView: UIView {
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

    func updatePreviewOrientation() {
        guard let connection = previewLayer.connection,
              let angle = window?.windowScene?.interfaceOrientation.videoRotationAngle,
              connection.isVideoRotationAngleSupported(angle) else {
            return
        }

        connection.videoRotationAngle = angle
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
