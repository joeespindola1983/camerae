import SwiftUI

enum CameraeWorkflowTheme: String, CaseIterable, Sendable {
    case repeatable
    case astro
    case editor

    var accent: Color {
        switch self {
        case .repeatable: CameraeColor.accentRepeatable
        case .astro: CameraeColor.accentAstro
        case .editor: CameraeColor.accentEditor
        }
    }

    var assetName: String {
        switch self {
        case .repeatable: "CameraeAccentRepeatable"
        case .astro: "CameraeAccentAstro"
        case .editor: "CameraeAccentEditor"
        }
    }
}

private struct CameraeWorkflowThemeKey: EnvironmentKey {
    static let defaultValue = CameraeWorkflowTheme.repeatable
}

extension EnvironmentValues {
    var cameraeWorkflowTheme: CameraeWorkflowTheme {
        get { self[CameraeWorkflowThemeKey.self] }
        set { self[CameraeWorkflowThemeKey.self] = newValue }
    }
}

extension View {
    func cameraeTheme(_ theme: CameraeWorkflowTheme) -> some View {
        environment(\.cameraeWorkflowTheme, theme)
            .tint(theme.accent)
    }
}

extension CameraModule {
    var designTheme: CameraeWorkflowTheme {
        switch self {
        case .repeatable: .repeatable
        case .astrophotography: .astro
        case .edit: .editor
        }
    }
}
