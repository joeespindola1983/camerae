import AVFoundation
import CoreGraphics
import Foundation

enum WorkflowVideoResolution: String, CaseIterable, Identifiable, Codable, Hashable {
    case full
    case fourK
    case preview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full:
            return "Full"
        case .fourK:
            return "4K"
        case .preview:
            return CameraeL10n.preview
        }
    }

    var maxPixelSize: CGSize? {
        switch self {
        case .full:
            return nil
        case .fourK:
            return CGSize(width: 3840, height: 2160)
        case .preview:
            return CGSize(width: 1920, height: 1080)
        }
    }
}

enum WorkflowVideoQuality: String, CaseIterable, Identifiable, Codable, Hashable {
    case standard
    case high
    case max

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:
            return CameraeL10n.qualityStandard
        case .high:
            return CameraeL10n.qualityHigh
        case .max:
            return CameraeL10n.qualityMaximum
        }
    }

    var bitRateMultiplier: Double {
        switch self {
        case .standard:
            return 0.75
        case .high:
            return 1.0
        case .max:
            return 1.45
        }
    }
}

struct WorkflowVideoSettings: Codable, Equatable, Hashable {
    var resolution: WorkflowVideoResolution
    var fps: Int
    var quality: WorkflowVideoQuality

    static let repeatableDefault = WorkflowVideoSettings(resolution: .fourK, fps: 60, quality: .high)
    static let astroDefault = WorkflowVideoSettings(resolution: .fourK, fps: 30, quality: .standard)

    var summary: String {
        "\(resolution.label) • \(fps) fps • \(quality.label)"
    }
}
