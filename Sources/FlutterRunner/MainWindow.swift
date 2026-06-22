import SwiftUI

/// The full control-surface window (Dock app). Tabs share one AppModel.
struct MainWindow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !model.flutterAvailable { missingFlutterBanner }
            Divider()
            TabView {
                RunView().tabItem { Label("Run", systemImage: "play.fill") }
                EmulatorsView().tabItem { Label("Emulators", systemImage: "iphone") }
                BuildView().tabItem { Label("Build", systemImage: "hammer.fill") }
                DependenciesView().tabItem { Label("Packages", systemImage: "cube.box") }
                CommandsView().tabItem { Label("Commands", systemImage: "terminal") }
                SDKView().tabItem { Label("SDK", systemImage: "shippingbox") }
                DoctorView().tabItem { Label("Doctor", systemImage: "stethoscope") }
                SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
            }
        }
        .frame(minWidth: Theme.windowMinW, minHeight: Theme.windowMinH)
        .dynamicTypeSize(model.dynamicType)
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
            Image(systemName: "bird.fill").foregroundStyle(.tint)
            Picker("", selection: $model.selectedProject) {
                ForEach(model.projects, id: \.self) { url in
                    Text(url.lastPathComponent).tag(Optional(url))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)

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
