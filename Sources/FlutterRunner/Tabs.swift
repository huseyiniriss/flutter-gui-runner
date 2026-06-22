import SwiftUI

// MARK: - Emulators

struct EmulatorsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabScaffold(title: "Emulators & Simulators", icon: "iphone") {
            Button { model.createEmulator() } label: {
                Label("Create", systemImage: "plus")
            }
            .buttonStyle(.secondary)
            .disabled(model.isBusy)
            if model.isScanning {
                ProgressView().controlSize(.mini)
            } else {
                Button { model.reloadEmulators() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.icon)
            }
        } content: {
            if model.emulators.isEmpty {
                EmptyState(title: "No emulators", symbol: "iphone.slash",
                           hint: "Create one, or install Android/iOS SDKs.")
            } else {
                VStack(spacing: Theme.s1) {
                    ForEach(model.emulators) { emu in
                        HStack(spacing: Theme.s3) {
                            Image(systemName: emu.symbol).foregroundStyle(.tint).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(emu.name)
                                Text("\(emu.platform) · \(emu.id)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { model.launchEmulator(emu) } label: {
                                Label("Launch", systemImage: "play.fill")
                            }
                            .buttonStyle(.secondary)
                            .disabled(model.isBusy)
                        }
                        .padding(Theme.s2)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.radius))
                    }
                }
            }
        }
    }
}

// MARK: - SDK

struct SDKView: View {
    @EnvironmentObject var model: AppModel
    private let channels = ["stable", "beta", "master"]

    var body: some View {
        TabScaffold(title: "Flutter SDK", icon: "shippingbox") {
            Button { Task { await model.refreshVersion() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.icon)
        } content: {
            Card(title: "Installed") {
                Grid(alignment: .leading, horizontalSpacing: Theme.s4, verticalSpacing: Theme.s1) {
                    GridRow { Text("Flutter").foregroundStyle(.secondary); Text(model.flutterVersion).bold() }
                    GridRow { Text("Channel").foregroundStyle(.secondary); Text(model.flutterChannel) }
                    GridRow { Text("Dart").foregroundStyle(.secondary); Text(model.dartVersion) }
                }
            }
            HStack(spacing: Theme.s2) {
                Button { model.upgradeSDK() } label: {
                    Label("Upgrade SDK", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.primary)
                .disabled(model.isBusy || model.isRunning)

                Menu {
                    ForEach(channels, id: \.self) { ch in
                        Button("Switch to \(ch)") { model.setChannel(ch) }
                    }
                } label: { Label("Channel", systemImage: "arrow.triangle.branch") }
                .frame(maxWidth: 130)
                .disabled(model.isBusy || model.isRunning)
            }
        }
    }
}

// MARK: - Commands

struct CommandsView: View {
    @EnvironmentObject var model: AppModel

    private struct Cmd: Identifiable { let id = UUID(); let title: String; let args: [String]; let label: String }
    private struct CmdGroup: Identifiable { let id = UUID(); let name: String; let cmds: [Cmd] }
    private let groups: [CmdGroup] = [
        CmdGroup(name: "Packages", cmds: [
            .init(title: "pub get", args: ["pub", "get"], label: "pub get"),
            .init(title: "pub upgrade", args: ["pub", "upgrade"], label: "pub upgrade"),
            .init(title: "pub upgrade --major", args: ["pub", "upgrade", "--major-versions"], label: "pub upgrade major"),
            .init(title: "pub outdated", args: ["pub", "outdated"], label: "pub outdated"),
        ]),
        CmdGroup(name: "Quality", cmds: [
            .init(title: "analyze", args: ["analyze"], label: "analyze"),
            .init(title: "test", args: ["test"], label: "test"),
            .init(title: "format", args: ["format", "."], label: "format"),
        ]),
        CmdGroup(name: "Codegen / l10n", cmds: [
            .init(title: "build_runner build", args: ["pub", "run", "build_runner", "build", "--delete-conflicting-outputs"], label: "build_runner"),
            .init(title: "gen-l10n", args: ["gen-l10n"], label: "gen-l10n"),
        ]),
        CmdGroup(name: "Maintenance", cmds: [
            .init(title: "clean", args: ["clean"], label: "clean"),
        ]),
    ]
    private let cols = [GridItem(.adaptive(minimum: 150), spacing: Theme.s2)]

    var body: some View {
        TabScaffold(title: "Commands", icon: "terminal") {
            ForEach(groups) { group in
                Card(title: group.name) {
                    LazyVGrid(columns: cols, alignment: .leading, spacing: Theme.s2) {
                        ForEach(group.cmds) { cmd in
                            Button { model.quick(cmd.args, label: cmd.label) } label: {
                                Text(cmd.title).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.secondary)
                            .disabled(model.isBusy || model.isRunning)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Doctor

struct DoctorView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabScaffold(title: "Doctor", icon: "stethoscope") {
            Button { model.doctor() } label: {
                Label("Run flutter doctor", systemImage: "stethoscope")
            }
            .buttonStyle(.primary)
            .disabled(model.isBusy || model.isRunning)
        } content: {
            EmptyView()
        }
    }
}

// MARK: - Shared log pane

/// A compact, auto-scrolling log pane with search + clear, reused everywhere.
struct LogPane: View {
    @EnvironmentObject var model: AppModel

    private var shown: String {
        let q = model.logQuery.trimmed
        guard !q.isEmpty else { return model.log }
        let lines = model.log
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.range(of: q, options: .caseInsensitive) != nil }
        return lines.isEmpty ? "(no matches)" : lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: Theme.s1) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Filter output", text: $model.logQuery)
                    .textFieldStyle(.plain).font(.caption)
                if model.isRunning || model.isBusy { ProgressView().controlSize(.mini) }
                Button { model.clearLog() } label: { Image(systemName: "trash") }
                    .buttonStyle(.icon).help("Clear log")
            }
            LogTextView(text: model.log.isEmpty ? "Output will appear here." : shown,
                        fontSize: model.logFontSize)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(.quaternary))
        }
    }
}

/// LogPane with a draggable divider on top so the terminal can be resized
/// with the mouse. The chosen height is persisted.
struct ResizableLogPane: View {
    @EnvironmentObject var model: AppModel
    var maxHeight: CGFloat = 600
    // Local height drives the frame during a drag so only this subtree
    // re-renders (updating the global model every frame caused flicker).
    @State private var height: CGFloat = 200
    @State private var dragBase: CGFloat?

    private var clampedMax: CGFloat { max(80, maxHeight) }

    var body: some View {
        VStack(spacing: 0) {
            handle
            LogPane().frame(height: min(height, clampedMax))
        }
        .onAppear { height = min(model.logHeight, clampedMax) }
        .onChange(of: model.logHeight) { _, new in
            if dragBase == nil { height = min(new, clampedMax) }   // external change
        }
        .onChange(of: maxHeight) { _, _ in
            height = min(height, clampedMax)      // window shrank → clamp down
        }
    }

    private var handle: some View {
        ZStack {
            Color.clear.frame(height: 12)
            Capsule().fill(.secondary.opacity(0.5)).frame(width: 44, height: 4)
        }
        .contentShape(Rectangle())
        .onHover { $0 ? NSCursor.resizeUpDown.set() : NSCursor.arrow.set() }
        .gesture(
            // Measure in .global space: the handle moves as the pane resizes, so
            // local translation would oscillate (jitter). Global = true cursor delta.
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if dragBase == nil { dragBase = height }
                    height = min(max((dragBase ?? height) - v.translation.height, 80), clampedMax)
                }
                .onEnded { _ in
                    dragBase = nil
                    model.logHeight = height       // commit + persist once
                }
        )
    }
}

extension View {
    var logPane: some View { LogPane() }
}
