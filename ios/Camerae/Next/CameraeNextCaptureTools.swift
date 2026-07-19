import SwiftUI

enum CameraeNextCaptureHUDDefaults {
    static let showsRepeatablePosition = false
    static let repeatableSelectedGroup: CameraeNextCaptureToolGroupID? = nil
}

enum CameraeNextCaptureHUDLayout {
    // The capture GeometryReader is already constrained to the safe area.
    static let topInset: CGFloat = 6
}

enum CameraeNextCaptureToolGroupID: String, CaseIterable, Identifiable, Sendable {
    case trace
    case guides
    case blink
    case sensors
    case information

    var id: Self { self }

    var title: String {
        switch self {
        case .trace: "Traço"
        case .guides: "Guias"
        case .blink: "Comparação"
        case .sensors: "Sensores"
        case .information: "Informações"
        }
    }

    var systemImage: String {
        switch self {
        case .trace: "scribble"
        case .guides: "viewfinder"
        case .blink: "eye"
        case .sensors: "location.north.line"
        case .information: "info.circle"
        }
    }

    var assetName: String {
        switch self {
        case .trace: "CameraeCaptureGlyphTrace"
        case .guides: "CameraeCaptureGlyphGuides"
        case .blink: "CameraeCaptureGlyphBlink"
        case .sensors: "CameraeCaptureGlyphSensors"
        case .information: "CameraeCaptureGlyphInfo"
        }
    }
}

enum CameraeNextCaptureToolID: String, Identifiable, Sendable {
    case referenceEdges
    case edgeColor
    case edgeStroke
    case grid
    case visualMatch
    case scale
    case magnifier
    case referenceBlink
    case blinkInterval
    case referenceOpacity
    case position
    case motion
    case captureInformation

    var id: Self { self }
}

struct CameraeNextCaptureTool: Identifiable, Equatable, Sendable {
    let id: CameraeNextCaptureToolID
}

struct CameraeNextCaptureToolGroup: Identifiable, Equatable, Sendable {
    let id: CameraeNextCaptureToolGroupID
    let tools: [CameraeNextCaptureTool]
}

struct CameraeNextCaptureToolCatalog: Equatable, Sendable {
    let module: CameraModule
    let groups: [CameraeNextCaptureToolGroup]

    init(module: CameraModule) {
        self.module = module

        let guides = CameraeNextCaptureToolGroup(
            id: .guides,
            tools: module == .repeatable
                ? [.grid, .visualMatch, .scale, .magnifier].map { CameraeNextCaptureTool(id: $0) }
                : [CameraeNextCaptureTool(id: .grid)]
        )
        let sensors = CameraeNextCaptureToolGroup(
            id: .sensors,
            tools: [CameraeNextCaptureTool(id: .position), CameraeNextCaptureTool(id: .motion)]
        )
        let information = CameraeNextCaptureToolGroup(
            id: .information,
            tools: [CameraeNextCaptureTool(id: .captureInformation)]
        )

        if module == .repeatable {
            groups = [
                CameraeNextCaptureToolGroup(
                    id: .trace,
                    tools: [.referenceEdges, .edgeColor, .edgeStroke].map { CameraeNextCaptureTool(id: $0) }
                ),
                guides,
                CameraeNextCaptureToolGroup(
                    id: .blink,
                    tools: [.referenceBlink, .blinkInterval, .referenceOpacity].map { CameraeNextCaptureTool(id: $0) }
                ),
                sensors,
                information
            ]
        } else if module == .astrophotography {
            groups = [
                guides,
                CameraeNextCaptureToolGroup(
                    id: .sensors,
                    tools: [CameraeNextCaptureTool(id: .position), CameraeNextCaptureTool(id: .motion)]
                ),
                information
            ]
        } else {
            groups = []
        }
    }
}

struct CameraeNextCaptureToolStripPresentation: Equatable, Sendable {
    let axis: Axis
    let groups: [CameraeNextCaptureToolGroup]

    init(module: CameraModule, orientation: CameraeCapturePanelOrientation) {
        axis = .horizontal
        groups = CameraeNextCaptureToolCatalog(module: module).groups
    }
}

struct CameraeNextCaptureToolTrayPresentation: Equatable, Sendable {
    let title: String
    let theme: CameraeWorkflowTheme
    let tools: [CameraeNextCaptureTool]

    init?(module: CameraModule, selection: CameraeNextCaptureToolGroupID?) {
        guard let selection,
              let group = CameraeNextCaptureToolCatalog(module: module)
                .groups
                .first(where: { $0.id == selection }) else {
            return nil
        }

        title = selection.title.uppercased()
        theme = module.designTheme
        tools = group.tools
    }
}

struct CameraeNextCaptureToolStrip: View {
    let presentation: CameraeNextCaptureToolStripPresentation
    let selection: CameraeNextCaptureToolGroupID?
    var theme = CameraeWorkflowTheme.repeatable
    let onSelect: (CameraeNextCaptureToolGroupID) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presentation.groups) { group in
                Button {
                    onSelect(group.id)
                } label: {
                    Image(group.id.assetName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(selection == group.id ? theme.accent : CameraeColor.captureForeground)
                        .frame(width: 24, height: 24)
                        .frame(width: 48, height: 48)
                        .background(CameraeColor.captureScrim.opacity(0.9), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(
                                    selection == group.id ? theme.accent : CameraeColor.captureHairline,
                                    lineWidth: selection == group.id ? 2 : 1
                                )
                        }
                        .overlay(alignment: .bottom) {
                            if selection == group.id {
                                Circle()
                                    .fill(theme.accent)
                                    .frame(width: 6, height: 6)
                                    .offset(y: 3)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(group.id.title)
                .accessibilityValue(selection == group.id ? "Aberto" : "Fechado")
            }
        }
    }
}

struct CameraeNextCaptureToolTray<Content: View>: View {
    let presentation: CameraeNextCaptureToolTrayPresentation
    private let content: Content

    init(
        presentation: CameraeNextCaptureToolTrayPresentation,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(.custom("Outfit-SemiBold", size: 10, relativeTo: .caption2))
                .foregroundStyle(presentation.theme.accent)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .frame(maxWidth: 360, minHeight: 104, alignment: .topLeading)
        .background(
            CameraeColor.captureScrim.opacity(0.9),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(CameraeColor.captureHairline, lineWidth: 1)
        }
    }
}
