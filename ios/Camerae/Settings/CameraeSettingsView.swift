import CameraeCore
import SwiftUI

struct CameraeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: CameraeSettingsStore

    var body: some View {
        NavigationStack {
            ZStack {
                CameraeColor.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(CameraeL10n.settingsOverviewHelper)
                            .cameraeSettingsHelper()

                        NavigationLink {
                            CameraePrivacySettingsView()
                        } label: {
                            CameraeSettingsSummaryCard(
                                icon: "shield.lefthalf.filled",
                                title: CameraeL10n.settingsDiagnosticsUsage,
                                helper: CameraeL10n.settingsCrashlyticsAnalytics,
                                value: settings.diagnosticsEnabled ? CameraeL10n.settingsActive : CameraeL10n.settingsDisabled
                            )
                        }
                        .accessibilityIdentifier("settings.privacy.open")

                        NavigationLink {
                            CameraeCaptureSettingsView()
                        } label: {
                            CameraeSettingsSummaryCard(
                                icon: "gauge.with.dots.needle.67percent",
                                title: CameraeL10n.settingsPerformance,
                                helper: CameraeL10n.settingsPerformanceHelper,
                                value: settings.performanceMode == .automatic ? CameraeL10n.settingsAutomaticShort : settings.performanceMode.title.uppercased()
                            )
                        }
                        .accessibilityIdentifier("settings.capture.open")

                        NavigationLink {
                            CameraeStorageSettingsView()
                        } label: {
                            CameraeSettingsSummaryCard(
                                icon: "externaldrive.fill",
                                title: CameraeL10n.settingsStorage,
                                helper: CameraeL10n.settingsStorageHelper,
                                value: availableStorage
                            )
                        }
                        .accessibilityIdentifier("settings.storage.open")

                        Text(CameraeL10n.settingsAppliedToNewProjects)
                            .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                            .foregroundStyle(CameraeColor.textMuted)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 34)
                }
            }
            .navigationTitle(CameraeL10n.settingsTitle)
            .navigationBarTitleDisplayMode(.large)
            .accessibilityIdentifier("settings.overview")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(CameraeL10n.settingsClose)
                }
            }
        }
        .tint(CameraeColor.accentEditor)
        .preferredColorScheme(.dark)
    }

    private var availableStorage: String {
        let values = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let bytes = values?[.systemFreeSize] as? Int64 ?? 0
        return CameraeL10n.settingsFreeStorage(
            ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file).uppercased()
        )
    }
}

private struct CameraePrivacySettingsView: View {
    @EnvironmentObject private var settings: CameraeSettingsStore

    var body: some View {
        CameraeSettingsPage(
            title: CameraeL10n.settingsPrivacyTitle,
            helper: CameraeL10n.settingsPrivacyHelper
        ) {
            CameraeSettingsSection(icon: "shield.fill", title: CameraeL10n.settingsDiagnostics) {
                Toggle(CameraeL10n.settingsShareCrashReports, isOn: $settings.diagnosticsEnabled)
                    .cameraeSettingsRow()
            }
            CameraeSettingsSection(icon: "chart.xyaxis.line", title: CameraeL10n.settingsAnalytics) {
                Toggle(CameraeL10n.settingsShareAnalytics, isOn: $settings.analyticsEnabled)
                    .cameraeSettingsRow()
                    .disabled(!settings.diagnosticsEnabled)
                    .opacity(settings.diagnosticsEnabled ? 1 : 0.5)
            }
        }
        .accessibilityIdentifier("settings.privacy")
    }
}

private struct CameraeCaptureSettingsView: View {
    @EnvironmentObject private var settings: CameraeSettingsStore

    var body: some View {
        CameraeSettingsPage(
            title: CameraeL10n.settingsCaptureTitle,
            helper: CameraeL10n.settingsCaptureHelper
        ) {
            CameraeSettingsSection(icon: "sun.max.fill", title: "Repeatable", accent: CameraeColor.accentRepeatable) {
                Text(CameraeL10n.settingsTimelapseFormat).cameraeSettingsHelper()
                Picker("Formato Repeatable", selection: $settings.repeatableFormat) {
                    Text("HEIC").tag(CaptureSourceFormat.heic)
                    Text("JPEG").tag(CaptureSourceFormat.jpeg)
                }
                .cameraeSettingsPicker()
            }

            CameraeSettingsSection(icon: "star.fill", title: "Astro", accent: CameraeColor.accentAstro) {
                Text(CameraeL10n.settingsAstroFormat).cameraeSettingsHelper()
                Picker("Formato Astro", selection: $settings.astroFormat) {
                    Text("DNG").tag(CaptureSourceFormat.dng)
                    Text("HEIC").tag(CaptureSourceFormat.heic)
                }
                .cameraeSettingsPicker(dark: true)
            }

            CameraeSettingsSection(icon: "gauge.with.dots.needle.67percent", title: CameraeL10n.settingsPerformance) {
                Text(CameraeL10n.settingsPerformanceHelper).cameraeSettingsHelper()
                Picker(CameraeL10n.settingsPerformance, selection: $settings.performanceMode) {
                    ForEach(CameraePerformanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .cameraeSettingsPicker()
            }
        }
        .accessibilityIdentifier("settings.capture")
    }
}

private struct CameraeStorageSettingsView: View {
    @EnvironmentObject private var settings: CameraeSettingsStore

    var body: some View {
        CameraeSettingsPage(
            title: CameraeL10n.settingsStorageTitle,
            helper: CameraeL10n.settingsStoragePageHelper
        ) {
            CameraeSettingsSection(icon: "externaldrive.fill", title: CameraeL10n.settingsOriginals) {
                Toggle(CameraeL10n.settingsPreserveOriginals, isOn: $settings.preserveOriginals)
                    .cameraeSettingsRow()
            }
            CameraeSettingsSection(icon: "internaldrive.fill", title: CameraeL10n.settingsFreeSpace) {
                Toggle(CameraeL10n.settingsLowStorageWarning, isOn: $settings.lowStorageWarningEnabled)
                    .cameraeSettingsRow()
            }
        }
        .accessibilityIdentifier("settings.storage")
    }
}

private struct CameraeSettingsPage<Content: View>: View {
    let title: String
    let helper: String
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            CameraeColor.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text(helper).cameraeSettingsHelper()
                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CameraeSettingsSummaryCard: View {
    let icon: String
    let title: String
    let helper: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            CameraeSettingsIcon(symbol: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .body))
                    .foregroundStyle(CameraeColor.textPrimary)
                Text(helper)
                    .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                    .foregroundStyle(CameraeColor.textMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                .foregroundStyle(CameraeColor.accentEditor)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(CameraeColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CameraeColor.borderStrong.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct CameraeSettingsSection<Content: View>: View {
    let icon: String
    let title: String
    var accent = CameraeColor.accentEditor
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CameraeSettingsIcon(symbol: icon, accent: accent, size: 36)
                Text(title)
                    .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .body))
                    .foregroundStyle(CameraeColor.textPrimary)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CameraeColor.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CameraeColor.borderStrong.opacity(0.45), lineWidth: 1)
        }
    }
}

private struct CameraeSettingsIcon: View {
    let symbol: String
    var accent = CameraeColor.accentEditor
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.black.opacity(0.85))
            .frame(width: size, height: size)
            .background(accent, in: RoundedRectangle(cornerRadius: size > 40 ? 14 : 12, style: .continuous))
    }
}

private extension View {
    func cameraeSettingsHelper() -> some View {
        font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
            .foregroundStyle(CameraeColor.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    func cameraeSettingsRow() -> some View {
        font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
            .foregroundStyle(CameraeColor.textPrimary)
            .tint(CameraeColor.accentEditor)
            .frame(minHeight: 44)
    }

    func cameraeSettingsPicker(dark: Bool = false) -> some View {
        pickerStyle(.menu)
            .tint(dark ? CameraeColor.astroDarkText : CameraeColor.repeatableLightText)
            .padding(.horizontal, 14)
            .frame(width: 220, height: 44)
            .background(
                dark ? CameraeColor.astroDarkCard : CameraeColor.repeatableLightCard,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(dark ? CameraeColor.astroDarkBorder : CameraeColor.repeatableLightBorder, lineWidth: 1)
            }
    }
}
