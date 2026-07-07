import SwiftUI
import AppKit

// MARK: - Shared run controls (used by both the Run tab and the menu-bar panel)

private struct DeviceRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: model.selectedDevice?.symbol ?? "display")
                .foregroundStyle(.tint).frame(width: 18)
            Picker("", selection: $model.selectedDevice) {
                if model.devices.isEmpty { Text("No devices").tag(Optional<Device>.none) }
                ForEach(model.devices) { Text($0.label).tag(Optional($0)) }
            }
            .labelsHidden()
            if model.isScanning {
                ProgressView().controlSize(.mini)
            } else {
                Button { model.reloadDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.icon).help("Refresh devices")
            }
        }
    }
}

private struct ModeRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Picker("Mode", selection: $model.mode) {
            ForEach(RunMode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// Entry-point (target) selector — shows the current file + a file picker so any
/// .dart entry (lib/main_prod.dart, etc.) can be chosen, not just scanned ones.
struct EntryRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "doc.text").foregroundStyle(.secondary).font(.caption)
            Text("Dart entrypoint").font(.caption).foregroundStyle(.secondary)
            // Current file chip + Choose, kept together so the relationship is clear.
            Button { model.chooseEntryPoint() } label: {
                HStack(spacing: Theme.s1) {
                    Text(model.target.isEmpty ? "lib/main.dart" : model.target)
                        .lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.caption2).opacity(0.6)
                }
            }
            .buttonStyle(.secondary)
            .help("Choose entry .dart file")
            if !model.target.isEmpty && model.target != "lib/main.dart" {
                Button { model.target = "lib/main.dart" } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.icon).help("Reset to lib/main.dart")
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RunControls: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Group {
            if model.isRunning {
                Button(role: .destructive) { model.stop() } label: {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button { model.run() } label: {
                    Label("Run", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.selectedDevice == nil || model.selectedProject == nil || model.isBusy)
            }
        }
    }
}

private struct HotControls: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: Theme.s2) {
            Button { model.hotReload() } label: {
                Label("Hot reload", systemImage: "flame.fill").frame(maxWidth: .infinity)
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(model.mode != .debug)
            Button { model.hotRestart() } label: {
                Label("Hot restart", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
            }
            .disabled(model.mode != .debug)
        }
        .buttonStyle(.secondary)
        .help(model.mode == .debug ? "" : "Hot reload only works in debug mode")
    }
}

/// Compact dart-define editor — applied to both `flutter run` and builds.
struct DartDefineRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "curlybraces").foregroundStyle(.secondary).font(.caption)
            Text("dart-define").font(.caption).foregroundStyle(.secondary)
            TextField("KEY=VAL KEY2=VAL2", text: $model.dartDefines)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
        .help("Space-separated KEY=VALUE pairs, passed as --dart-define on run and build")
    }
}

/// Opens Flutter DevTools in the browser using the live run session's URL.
struct DevToolsButton: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Button { model.openDevTools() } label: {
            Label("DevTools", systemImage: "ladybug.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.secondary)
        .disabled(model.devToolsURL == nil)
        .help(model.devToolsURL == nil
              ? "Available once a debug run is up"
              : "Open Flutter DevTools in your browser")
    }
}

/// Compact branch switcher for the Run tab / menu-bar panel.
struct BranchRow: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary).font(.caption)
            Text("Branch").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { model.currentBranch },
                set: { model.checkoutBranch($0) })) {
                ForEach(model.gitBranches, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .disabled(model.isBusy || model.isRunning)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Run tab (full window)

struct RunView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TabScaffold(title: "Run", icon: "play.fill") {
            DeviceRow().frame(maxWidth: 280)
        } content: {
            EntryRow()
            DartDefineRow()
            if model.isGitRepo { BranchRow() }
            ModeRow()
            RunControls()
            if model.isRunning { HotControls(); DevToolsButton() }
        }
    }
}

// MARK: - Menu-bar quick-access panel (covers everything while coding)

struct MenuBarPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            // Header: title + Show App + Quit
            HStack(spacing: Theme.s2) {
                Image(systemName: "bird.fill").foregroundStyle(.tint)
                Text("Flutter Runner").font(.headline)
                Spacer()
                if model.isRunning {
                    Label("live", systemImage: "dot.radiowaves.left.and.right")
                        .labelStyle(.iconOnly).foregroundStyle(.green)
                } else if model.isBusy || model.isScanning {
                    ProgressView().controlSize(.small)
                }
                Button { showMainWindow() } label: {
                    Image(systemName: "macwindow")
                }.buttonStyle(.icon).help("Show app window")
                Button { NSApplication.shared.terminate(nil) } label: {
                    Image(systemName: "power")
                }.buttonStyle(.icon).help("Quit")
            }
            Divider()

            // Project + device + mode
            HStack(spacing: Theme.s2) {
                Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 16)
                Picker("", selection: $model.selectedProject) {
                    ForEach(model.projects, id: \.self) { Text($0.lastPathComponent).tag(Optional($0)) }
                }.labelsHidden()
            }
            DeviceRow()
            EntryRow()
            DartDefineRow()
            if model.isGitRepo { BranchRow() }
            ModeRow()

            // Run / Stop + hot controls + DevTools
            RunControls()
            if model.isRunning { HotControls(); DevToolsButton() }

            // Quick build + tools so the panel covers everyday needs
            HStack(spacing: Theme.s2) {
                Menu {
                    Button("APK") { model.build("apk") }
                    Button("App Bundle (.aab)") { model.build("appbundle") }
                    Button("IPA") { model.build("ipa") }
                    Button("Web") { model.build("web") }
                } label: { Label("Build", systemImage: "hammer.fill") }
                .disabled(model.isRunning || model.isBusy)
                Menu {
                    Button("pub get") { model.quick(["pub", "get"], label: "pub get") }
                    Button("pub upgrade") { model.quick(["pub", "upgrade"], label: "pub upgrade") }
                    Button("clean") { model.quick(["clean"], label: "clean") }
                    Button("analyze") { model.quick(["analyze"], label: "analyze") }
                    Button("test") { model.quick(["test"], label: "test") }
                } label: { Label("Tools", systemImage: "wrench.and.screwdriver.fill") }
                .disabled(model.isRunning || model.isBusy)
            }

            LogPane().frame(height: Theme.logHeight)

            Text(model.statusLine).font(.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.s4)
        .frame(width: Theme.menuWidth)
        .dynamicTypeSize(model.dynamicType)
    }

    /// Bring the main window to the front, recreating it if it was closed.
    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = NSApp.windows.first(where: { $0.canBecomeMain && $0.contentView != nil }) {
            win.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
