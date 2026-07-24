import CameraeCore
import CameraeMedia
import Foundation

enum CameraeNextAlignmentMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case position
    case automatic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Desligado"
        case .position: "Só posição"
        case .automatic: "Automático"
        }
    }
}

enum CameraeNextAlignmentStatus: Equatable, Sendable {
    case off
    case ready
    case analyzing
    case applied
    case review
    case rejected
    case failed
    case stale
}

struct CameraeNextAlignmentSnapshot: Equatable, Sendable {
    var status: CameraeNextAlignmentStatus
    var itemCount: Int
    var cropPercentage: Int?
    var confidence: Double?
    var message: String?

    static let off = Self(
        status: .off,
        itemCount: 0,
        cropPercentage: nil,
        confidence: nil,
        message: nil
    )
}

protocol CameraeNextAlignmentAnalyzing: Sendable {
    func analyze(
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset]
    ) async throws -> EditSpatialAlignmentPlan

    func analyze(
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        projectReferenceURL: URL
    ) async throws -> EditSpatialAlignmentPlan
}

extension CameraeNextAlignmentAnalyzing {
    func analyze(
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        projectReferenceURL: URL
    ) async throws -> EditSpatialAlignmentPlan {
        try await analyze(document: document, assets: assets)
    }
}

extension VideoClipAlignmentAnalyzer: CameraeNextAlignmentAnalyzing {}

@MainActor
final class CameraeNextAlignmentViewModel: ObservableObject {
    @Published private(set) var snapshot = CameraeNextAlignmentSnapshot.off
    @Published private(set) var mode = CameraeNextAlignmentMode.automatic

    private let analyzer: any CameraeNextAlignmentAnalyzing
    private var document: EditProjectDocument?
    private var assets: [MediaAssetID: ResolvedMediaAsset] = [:]
    private var projectReferenceURL: URL?
    private var analyzedPlan: EditSpatialAlignmentPlan?
    private var analyzedSignature: String?
    private var analysisTask: Task<Void, Never>?

    init(analyzer: any CameraeNextAlignmentAnalyzing = VideoClipAlignmentAnalyzer.live()) {
        self.analyzer = analyzer
    }

    var exportPlan: EditSpatialAlignmentPlan? {
        guard snapshot.status == .applied, let analyzedPlan else { return nil }
        switch mode {
        case .off:
            return nil
        case .position:
            return analyzedPlan.translationOnly
        case .automatic:
            return analyzedPlan
        }
    }

    func prepare(
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        projectReferenceURL: URL? = nil
    ) {
        let nextSignature = Self.signature(
            document: document,
            assets: assets,
            projectReferenceURL: projectReferenceURL
        )
        let timelineChanged = analyzedSignature != nil && analyzedSignature != nextSignature
        self.document = document
        self.assets = assets
        self.projectReferenceURL = projectReferenceURL

        if timelineChanged {
            analyzedPlan = nil
            if mode == .off {
                snapshot = Self.snapshot(status: .off, document: document)
            } else {
                snapshot = Self.snapshot(
                    status: .stale,
                    document: document,
                    message: "A sequência mudou desde a última análise."
                )
            }
        } else if mode == .off {
            snapshot = Self.snapshot(status: .off, document: document)
        } else if analyzedPlan == nil, snapshot.status != .analyzing {
            snapshot = Self.snapshot(status: .ready, document: document)
        }
    }

    func setMode(_ mode: CameraeNextAlignmentMode) {
        guard self.mode != mode else { return }
        self.mode = mode
        guard let document else {
            snapshot = mode == .off ? .off : snapshot
            return
        }
        if mode == .off {
            cancel()
            snapshot = Self.snapshot(status: .off, document: document)
        } else if let analyzedPlan {
            snapshot = Self.resultSnapshot(plan: analyzedPlan, document: document)
        } else {
            snapshot = Self.snapshot(status: .ready, document: document)
        }
    }

    func analyze() async {
        guard mode != .off, let document else { return }
        if projectReferenceURL == nil {
            guard document.items.count > 1 else { return }
        } else {
            guard !document.items.isEmpty else { return }
        }
        analysisTask?.cancel()
        snapshot = Self.snapshot(status: .analyzing, document: document)
        let analyzer = self.analyzer
        let assets = self.assets
        let projectReferenceURL = self.projectReferenceURL
        let signature = Self.signature(
            document: document,
            assets: assets,
            projectReferenceURL: projectReferenceURL
        )

        analysisTask = Task { [weak self] in
            do {
                let plan: EditSpatialAlignmentPlan
                if let projectReferenceURL {
                    plan = try await analyzer.analyze(
                        document: document,
                        assets: assets,
                        projectReferenceURL: projectReferenceURL
                    )
                } else {
                    plan = try await analyzer.analyze(document: document, assets: assets)
                }
                try Task.checkCancellation()
                guard let self else { return }
                self.analyzedPlan = plan
                self.analyzedSignature = signature
                self.snapshot = Self.resultSnapshot(plan: plan, document: document)
            } catch is CancellationError {
                guard let self, !Task.isCancelled else { return }
                self.snapshot = Self.snapshot(status: .ready, document: document)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.analyzedPlan = nil
                self.snapshot = Self.snapshot(
                    status: .failed,
                    document: document,
                    message: error.localizedDescription
                )
            }
        }
        await analysisTask?.value
    }

    func cancel() {
        analysisTask?.cancel()
        analysisTask = nil
        if let document, mode != .off {
            snapshot = Self.snapshot(status: .ready, document: document)
        }
    }

    func removeAlignment() {
        analysisTask?.cancel()
        analyzedPlan = nil
        analyzedSignature = nil
        if let document {
            snapshot = Self.snapshot(status: mode == .off ? .off : .ready, document: document)
        }
    }

    private static func signature(
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        projectReferenceURL: URL?
    ) -> String {
        let itemSignature = document.items.map { item in
            let asset = assets[item.asset.id]
            return [
                item.id.uuidString,
                item.asset.id.rawValue,
                asset?.url.standardizedFileURL.path ?? "missing",
                String(asset?.descriptor.duration ?? -1),
                String(asset?.descriptor.fileSize ?? 0)
            ].joined(separator: "|")
        }.joined(separator: ";")
        guard let projectReferenceURL else { return itemSignature }
        let values = try? projectReferenceURL.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        return [
            itemSignature,
            projectReferenceURL.standardizedFileURL.path,
            String(values?.fileSize ?? -1),
            String(values?.contentModificationDate?.timeIntervalSince1970 ?? -1)
        ].joined(separator: ";")
    }

    private static func resultSnapshot(
        plan: EditSpatialAlignmentPlan,
        document: EditProjectDocument
    ) -> CameraeNextAlignmentSnapshot {
        let status: CameraeNextAlignmentStatus
        switch plan.decision {
        case .apply: status = .applied
        case .review: status = .review
        case .reject: status = .rejected
        }
        let scores = plan.corrections.values.map(\.quality.score)
        return CameraeNextAlignmentSnapshot(
            status: status,
            itemCount: document.items.count,
            cropPercentage: Int(((1 - plan.commonCrop.area) * 100).rounded()),
            confidence: scores.min(),
            message: plan.reasonCodes.first
        )
    }

    private static func snapshot(
        status: CameraeNextAlignmentStatus,
        document: EditProjectDocument,
        message: String? = nil
    ) -> CameraeNextAlignmentSnapshot {
        CameraeNextAlignmentSnapshot(
            status: status,
            itemCount: document.items.count,
            cropPercentage: nil,
            confidence: nil,
            message: message
        )
    }
}

private extension EditSpatialAlignmentPlan {
    var translationOnly: EditSpatialAlignmentPlan {
        let projected = corrections.mapValues { candidate in
            ClipAlignmentCandidate(
                itemID: candidate.itemID,
                model: candidate.model == .identity ? .identity : .translation,
                transform: candidate.model == .identity
                    ? .identity
                    : ClipAlignmentTransform(
                        a: 1,
                        b: 0,
                        c: 0,
                        d: 1,
                        tx: candidate.transform.tx,
                        ty: candidate.transform.ty
                    ),
                validRegion: candidate.validRegion,
                quality: candidate.quality
            )
        }
        return EditSpatialAlignmentPlan(
            referenceItemID: referenceItemID,
            corrections: projected,
            commonCrop: commonCrop,
            decision: decision,
            reasonCodes: reasonCodes
        )
    }
}
