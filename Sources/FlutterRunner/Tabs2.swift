import SwiftUI

// MARK: - Build (Phase 05)

struct BuildView: View {
    @EnvironmentObject var model: AppModel

    private struct Artifact: Identifiable { let id: String; let title: String }
    private let artifacts: [Artifact] = [
        .init(id: "apk", title: "APK"),
        .init(id: "appbundle", title: "AAB"),
        .init(id: "ipa", title: "IPA"),
        .init(id: "ios", title: "iOS (no sign)"),
        .init(id: "web", title: "Web"),
        .init(id: "macos", title: "macOS"),
    ]
    private let cols = [GridItem(.adaptive(minimum: 110), spacing: Theme.s2)]

    var body: some View {
        TabScaffold(title: "Build", icon: "hammer.fill") {
            HStack(spacing: Theme.s2) {
                Image(systemName: "app.dashed").foregroundStyle(.secondary)
                Text(model.appName).bold()
                Text("v\(model.appVersion)").foregroundStyle(.secondary)
                Spacer()
            }
            .font(.caption)

            Picker("Mode", selection: $model.mode) {
                ForEach(RunMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Card(title: "Options") {
                Grid(alignment: .leading, horizontalSpacing: Theme.s3, verticalSpacing: Theme.s2) {
                    GridRow { Text("Flavor"); TextField("(optional)", text: $model.flavor) }
                    GridRow { Text("Build name"); TextField("e.g. 1.2.0", text: $model.buildName) }
                    GridRow { Text("Build number"); TextField("e.g. 42", text: $model.buildNumber) }
                    GridRow { Text("Target"); TextField("lib/main.dart", text: $model.target) }
                }
                .textFieldStyle(.roundedBorder)
                DartDefineRow()
                    .padding(.top, Theme.s1)
                HStack(spacing: Theme.s4) {
                    Toggle("split-per-abi (apk)", isOn: $model.splitPerAbi)
                    Toggle("obfuscate", isOn: $model.obfuscate)
                    Spacer()
                }
                .padding(.top, Theme.s1)
            }

            LazyVGrid(columns: cols, alignment: .leading, spacing: Theme.s2) {
                ForEach(artifacts) { a in
                    Button { model.build(a.id) } label: {
                        Text(a.title).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondary)
                    .disabled(model.isBusy || model.isRunning)
                }
            }

            if model.lastArtifactPath != nil {
                Button { model.revealArtifact() } label: {
                    Label("Reveal last build in Finder", systemImage: "folder")
                }
                .buttonStyle(.primary)
            }

            Card(title: "Android Signing") {
                HStack(spacing: Theme.s2) {
                    TextField("keystore path (.jks)", text: $model.keystorePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { model.chooseKeystore() }.buttonStyle(.secondary)
                }
                Grid(alignment: .leading, horizontalSpacing: Theme.s3, verticalSpacing: Theme.s2) {
                    GridRow { Text("Alias"); TextField("upload", text: $model.keyAlias) }
                    GridRow { Text("Store pass"); SecureField("••••••", text: $model.storePassword) }
                    GridRow { Text("Key pass"); SecureField("(= store pass)", text: $model.keyPassword) }
                }
                .textFieldStyle(.roundedBorder)
                HStack(spacing: Theme.s2) {
                    Button { model.generateKeystore() } label: {
                        Label("Generate keystore", systemImage: "key.fill")
                    }
                    .buttonStyle(.secondary).disabled(model.isBusy || model.isRunning)
                    Button { model.writeKeyProperties() } label: {
                        Label("Write key.properties", systemImage: "doc.badge.gearshape")
                    }
                    .buttonStyle(.secondary)
                    Spacer()
                }
                Text("Passwords are stored in the app's local preferences on this Mac.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Dependencies (Phase 06)

struct DependenciesView: View {
    @EnvironmentObject var model: AppModel
    @State private var newPackage = ""
    @State private var asDev = false

    var body: some View {
        TabScaffold(title: "Packages", icon: "cube.box") {
            Button { model.outdated() } label: {
                Label("Outdated", systemImage: "arrow.up.arrow.down")
            }
            .buttonStyle(.secondary)
            .disabled(model.isBusy || model.isRunning)
            Button { model.loadDependencies() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.icon)
        } content: {
            Card {
                HStack(spacing: Theme.s2) {
                    TextField("package name (e.g. dio)", text: $newPackage)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { add() }
                    Toggle("dev", isOn: $asDev)
                    Button("Add") { add() }
                        .buttonStyle(.primary)
                        .disabled(newPackage.trimmed.isEmpty || model.isBusy || model.isRunning)
                }
            }

            if model.dependencies.isEmpty {
                EmptyState(title: "No dependencies parsed", symbol: "shippingbox",
                           hint: "Select a project with a pubspec.yaml.")
            } else {
                VStack(spacing: Theme.s1) {
                    ForEach(model.dependencies) { dep in
                        HStack(spacing: Theme.s3) {
                            Image(systemName: dep.kind == .dev ? "wrench.adjustable" : "cube.box")
                                .foregroundStyle(dep.kind == .dev ? Color.orange : Color.accentColor)
                                .frame(width: 20)
                            Text(dep.name)
                            Spacer()
                            Text(dep.version).font(.caption).foregroundStyle(.secondary)
                            Button { model.upgradePackage(dep.name) } label: {
                                Image(systemName: "arrow.up.circle")
                            }
                            .buttonStyle(.icon).help("Upgrade \(dep.name)")
                            .disabled(model.isBusy || model.isRunning)
                            Button { model.removePackage(dep.name) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.icon).help("Remove \(dep.name)")
                            .disabled(model.isBusy || model.isRunning)
                        }
                        .padding(.horizontal, Theme.s2).padding(.vertical, Theme.s1)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.radius))
                    }
                }
            }
        }
    }

    private func add() {
        model.addPackage(newPackage, dev: asDev)
        newPackage = ""
    }
}

// MARK: - Git

struct GitView: View {
    @EnvironmentObject var model: AppModel
    @State private var commitMessage = ""

    var body: some View {
        TabScaffold(title: "Git", icon: "arrow.triangle.branch") {
            if model.isGitRepo {
                Button { model.reloadGit() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.icon)
            }
        } content: {
            if !model.isGitRepo {
                EmptyState(title: "Not a git repository", symbol: "arrow.triangle.branch",
                           hint: "This project isn't under git, or git isn't installed.")
            } else {
                Card(title: "Branch") {
                    HStack(spacing: Theme.s2) {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(.tint)
                        Picker("", selection: Binding(
                            get: { model.currentBranch },
                            set: { model.checkoutBranch($0) })) {
                            ForEach(model.gitBranches, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .disabled(model.isBusy || model.isRunning)
                    }
                    Text("Current: \(model.currentBranch.isEmpty ? "—" : model.currentBranch)")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Card(title: "Actions") {
                    let cols = [GridItem(.adaptive(minimum: 130), spacing: Theme.s2)]
                    LazyVGrid(columns: cols, alignment: .leading, spacing: Theme.s2) {
                        gitButton("Status", "status")
                        gitButton("Pull", "pull")
                        gitButton("Push", "push")
                        gitButton("Fetch", "fetch --all --prune")
                        gitButton("Log", "log --oneline -20")
                        gitButton("Diff", "diff --stat")
                    }
                }

                Card(title: "Commit") {
                    HStack(spacing: Theme.s2) {
                        TextField("commit message", text: $commitMessage)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commit() }
                        Button("Commit all") { commit() }
                            .buttonStyle(.primary)
                            .disabled(commitMessage.trimmed.isEmpty || model.isBusy || model.isRunning)
                    }
                    Text("Runs git add -A && git commit -m …")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func gitButton(_ title: String, _ cmd: String) -> some View {
        Button { model.git(cmd, label: "git \(title.lowercased())") } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.secondary)
        .disabled(model.isBusy || model.isRunning)
    }

    private func commit() {
        let msg = commitMessage.trimmed
        guard !msg.isEmpty else { return }
        let escaped = msg.replacingOccurrences(of: "'", with: "'\\''")
        model.git("add -A && git commit -m '\(escaped)'", label: "commit")
        commitMessage = ""
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabScaffold(title: "Settings", icon: "gearshape", showsLog: false) {
            Card(title: "Appearance") {
                HStack(spacing: Theme.s3) {
                    Text("UI size")
                    Button { model.zoomOut() } label: { Image(systemName: "minus") }
                        .buttonStyle(.secondary).keyboardShortcut("-", modifiers: .command)
                        .disabled(model.uiScaleIndex == 0)
                    Text("\(model.uiScaleIndex + 1) / 6").monospacedDigit()
                    Button { model.zoomIn() } label: { Image(systemName: "plus") }
                        .buttonStyle(.secondary).keyboardShortcut("=", modifiers: .command)
                        .disabled(model.uiScaleIndex == 5)
                    Spacer()
                    Text("Aa").font(.system(size: 11 + CGFloat(model.uiScaleIndex) * 4))
                        .foregroundStyle(.secondary)
                }
                Text("Or use ⌘+ / ⌘− anywhere. Drag the window edges to resize.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Card(title: "Flutter SDK") {
                SDKPicker()
                HStack(spacing: Theme.s2) {
                    TextField("Flutter path override (blank = use PATH)",
                              text: $model.flutterPathOverride)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { model.chooseFlutterPath() }.buttonStyle(.secondary)
                }
                Text("Point to the Flutter SDK folder, its bin/ folder, or the flutter binary — all work.")
                    .font(.caption2).foregroundStyle(.secondary)
                flutterPathStatus
                Toggle("Use FVM when project has .fvmrc / .fvm", isOn: $model.useFvm)
                if model.fvmActive {
                    Label("FVM active for this project", systemImage: "checkmark.seal")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            Card(title: "Projects") {
                HStack(spacing: Theme.s2) {
                    TextField("Scan root", text: $model.scanRootPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Rescan") { model.rescan() }.buttonStyle(.secondary)
                }
                HStack(spacing: Theme.s2) {
                    Button { model.chooseProjects() } label: {
                        Label("Add project(s)…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.primary)
                    Text("Found \(model.projects.count) project(s).")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                Text("Pick a single project, ⌘-click several, or choose a parent folder to bulk-import every app inside it.")
                    .font(.caption2).foregroundStyle(.secondary)
                if !model.projects.isEmpty {
                    VStack(spacing: Theme.s1) {
                        ForEach(model.projects, id: \.self) { url in
                            HStack(spacing: Theme.s2) {
                                Image(systemName: url == model.selectedProject
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(url == model.selectedProject ? Color.accentColor : .secondary)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(url.lastPathComponent).font(.caption)
                                    Text(url.path).font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                if model.isCustomProject(url) {
                                    Text("added").font(.caption2)
                                        .padding(.horizontal, Theme.s1)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.blue)
                                    Button { model.removeProject(url) } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.icon).help("Remove \(url.lastPathComponent)")
                                }
                            }
                            .padding(.horizontal, Theme.s2).padding(.vertical, Theme.s1)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.radius))
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedProject = url }
                        }
                    }
                }
            }
            Button("Re-check Flutter") { Task { await model.checkFlutter() } }
                .buttonStyle(.secondary)
            Spacer()
        }
    }

    /// Live validation of the SDK override path.
    @ViewBuilder private var flutterPathStatus: some View {
        let raw = model.flutterPathOverride.trimmingCharacters(in: .whitespaces)
        if !raw.isEmpty {
            if let bin = AppModel.resolveFlutterBinary(raw),
               FileManager.default.isExecutableFile(atPath: bin) {
                Label("Using \(bin)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Label("No flutter binary found there — falling back to PATH.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
