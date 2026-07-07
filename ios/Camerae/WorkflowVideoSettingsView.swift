import SwiftUI

struct WorkflowVideoSettingsView: View {
    @Binding var settings: WorkflowVideoSettings
    var isDisabled = false

    var body: some View {
        Picker("Resolucao", selection: $settings.resolution) {
            ForEach(WorkflowVideoResolution.allCases) { resolution in
                Text(resolution.label).tag(resolution)
            }
        }
        .disabled(isDisabled)

        Picker("FPS", selection: $settings.fps) {
            ForEach([24, 30, 60], id: \.self) { fps in
                Text("\(fps) fps").tag(fps)
            }
        }
        .disabled(isDisabled)

        Picker("Qualidade", selection: $settings.quality) {
            ForEach(WorkflowVideoQuality.allCases) { quality in
                Text(quality.label).tag(quality)
            }
        }
        .disabled(isDisabled)
    }
}
