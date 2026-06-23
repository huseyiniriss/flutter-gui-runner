import SwiftUI

/// Sidebar tabs. A list scales far better than a top tab bar once there are
/// many sections (the old TabView overflowed at larger UI sizes).
enum Tab: String, CaseIterable, Identifiable {
    case run, emulators, build, packages, commands, git, sdk, doctor, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .run: "Run"; case .emulators: "Emulators"; case .build: "Build"
        case .packages: "Packages"; case .commands: "Commands"; case .git: "Git"
        case .sdk: "SDK"; case .doctor: "Doctor"; case .settings: "Settings"
        }
    }
    var icon: String {
        switch self {
        case .run: "play.fill"; case .emulators: "iphone"; case .build: "hammer.fill"
        case .packages: "cube.box"; case .commands: "terminal"; case .git: "arrow.triangle.branch"
        case .sdk: "shippingbox"; case .doctor: "stethoscope"; case .settings: "gearshape"
        }
    }
}

/// The full control-surface window (Dock app). Tabs share one AppModel.
struct MainWindow: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: Tab = .run

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                topBar
                if !model.flutterAvailable { missingFlutterBanner }
                Divider()
                detail
            }
            .frame(minWidth: 460)
        }
        .frame(minWidth: Theme.windowMinW, minHeight: Theme.windowMinH)
        .dynamicTypeSize(model.dynamicType)
    }

    private var sidebar: some View {
        List(Tab.allCases, selection: $selection) { tab in
            Label(tab.title, systemImage: tab.icon).tag(tab)
        }
        .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        .safeAreaInset(edge: .top) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "bird.fill").foregroundStyle(.tint)
                Text("Flutter Runner").font(.headline)
                Spacer()
            }
            .padding(.horizontal, Theme.s3).padding(.vertical, Theme.s2)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .run: RunView()
        case .emulators: EmulatorsView()
        case .build: BuildView()
        case .packages: DependenciesView()
        case .commands: CommandsView()
        case .git: GitView()
        case .sdk: SDKView()
        case .doctor: DoctorView()
        case .settings: SettingsView()
        }
    }

    private var missingFlutterBanner: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Flutter SDK not found. Set its path in Settings, or install Flutter.")
                .font(.caption)
            Spacer()
            Button("Re-check") { Task { await model.checkFlutter() } }
                .buttonStyle(.secondary).font(.caption)
        }
        .padding(.horizontal, Theme.s4).padding(.vertical, Theme.s2)
        .background(.orange.opacity(0.12))
    }

    private var topBar: some View {
        HStack(spacing: Theme.s2) {
            Picker("", selection: $model.selectedProject) {
                ForEach(model.projects, id: \.self) { url in
                    Text(url.lastPathComponent).tag(Optional(url))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)

            if model.isGitRepo && !model.currentBranch.isEmpty {
                Label(model.currentBranch, systemImage: "arrow.triangle.branch")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Label("\(model.flutterVersion) · \(model.flutterChannel)", systemImage: "shippingbox")
                .font(.caption).foregroundStyle(.secondary)
            if model.fvmActive {
                Text("FVM").font(.caption2.bold()).padding(.horizontal, Theme.s1)
                    .background(.green.opacity(0.2), in: Capsule()).foregroundStyle(.green)
            }
            if model.isRunning {
                Label("live", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(.green)
            } else if model.isBusy || model.isScanning {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.s4).padding(.vertical, Theme.s2)
    }
}
