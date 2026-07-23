import SwiftUI

struct EntryHomeView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @Binding var path: NavigationPath

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                EntryBackground()

                CameraeBrandLockup()
                    .frame(width: 260, height: 182, alignment: .top)
                    .position(
                        x: proxy.size.width / 2,
                        y: brandTop(for: proxy) + 91
                    )

                VStack(spacing: 12) {
                    HStack(spacing: 40) {
                        workflowButton(.repeatable, size: .standard)
                        workflowButton(.astrophotography, size: .standard)
                    }

                    workflowButton(.edit, size: .compact)
                }
                .frame(width: 280, height: 212, alignment: .top)
                .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height - actionsBottom(for: proxy) - 106
                )
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            AppOrientationLock.shared.restorePortrait()
            projectStore.reload()
        }
    }

    private func brandTop(for proxy: GeometryProxy) -> CGFloat {
        max(proxy.safeAreaInsets.top + 72, proxy.size.height * 0.168)
    }

    private func actionsBottom(for proxy: GeometryProxy) -> CGFloat {
        max(20, proxy.safeAreaInsets.bottom + 2)
    }

    private func workflowButton(_ module: CameraModule, size: WorkflowCardSize) -> some View {
        Button {
            path.append(module)
        } label: {
            WorkflowCard(
                module: module,
                size: size,
                projectCount: projectStore.projects(for: module).count
            )
        }
        .buttonStyle(EntryCardButtonStyle())
        .accessibilityLabel(CameraeL10n.openModule(module.title))
        .accessibilityValue(CameraeL10n.projectCount(projectStore.projects(for: module).count))
        .accessibilityIdentifier(CameraeAccessibility.openModule(module))
    }
}

private struct EntryBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Image("HomeBackgroundPortrait")
                .resizable()
                .scaledToFill()
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .center
                )
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: CameraeColor.canvas.opacity(0.078), location: 0),
                            .init(color: CameraeColor.canvas.opacity(0.052), location: 0.20),
                            .init(color: CameraeColor.canvas.opacity(0.286), location: 0.52),
                            .init(color: CameraeColor.canvas.opacity(0.484), location: 0.73),
                            .init(color: CameraeColor.canvas.opacity(0.52), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .ignoresSafeArea()
    }
}

private struct CameraeBrandLockup: View {
    var body: some View {
        VStack(spacing: 11) {
            Image("CameraeBrandSymbol")
                .resizable()
                .scaledToFill()
                .frame(width: 95, height: 95)
                .clipped()

            Image("CameraeBrandWordmark")
                .resizable()
                .scaledToFill()
                .frame(width: 336, height: 67)
                .clipped()
        }
        .frame(width: 260, height: 182, alignment: .top)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camerae")
    }
}

private enum WorkflowCardSize: Equatable {
    case standard
    case compact

    var cardSize: CGSize {
        switch self {
        case .standard: CGSize(width: 120, height: 121)
        case .compact: CGSize(width: 111, height: 79)
        }
    }

    var iconTile: CGFloat { self == .standard ? 52 : 32 }
    var iconSize: CGFloat { self == .standard ? 22 : 14 }
    var labelSize: CGFloat { self == .standard ? 14 : 10 }
    var topPadding: CGFloat { self == .standard ? 19 : 13 }
    var spacing: CGFloat { self == .standard ? 12 : 8 }
}

private struct WorkflowCard: View {
    let module: CameraModule
    let size: WorkflowCardSize
    let projectCount: Int

    private var theme: CameraeWorkflowTheme { module.designTheme }

    var body: some View {
        VStack(spacing: size.spacing) {
            ZStack {
                RoundedRectangle(cornerRadius: CameraeRadius.medium, style: .continuous)
                    .fill(theme.accent.opacity(0.18))

                Image(systemName: symbolName)
                    .font(.system(size: size.iconSize, weight: .regular))
                    .foregroundStyle(theme.accent)
            }
            .frame(width: size.iconTile, height: size.iconTile)

            Text(label)
                .font(.custom("Outfit-Regular", size: size.labelSize, relativeTo: .caption))
                .foregroundStyle(CameraeColor.textPrimary.opacity(0.70))
                .lineLimit(1)
        }
        .padding(.top, size.topPadding)
        .frame(width: size.cardSize.width, height: size.cardSize.height, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: CameraeRadius.large, style: .continuous))
    }

    private var label: String {
        switch module {
        case .repeatable: "Repeatable"
        case .astrophotography: "Astro"
        case .edit: "Editor"
        }
    }

    private var symbolName: String {
        switch module {
        case .repeatable: "sun.max"
        case .astrophotography: "star"
        case .edit: "film"
        }
    }
}

private struct EntryCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
