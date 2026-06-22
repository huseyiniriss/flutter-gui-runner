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
                    GridRow { Text("dart-define"); TextField("KEY=VAL KEY2=VAL2", text: $model.dartDefines) }
                }
                .textFieldStyle(.roundedBorder)
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
                TextField("Flutter path override (blank = use PATH)",
                          text: $model.flutterPathOverride)
                    .textFieldStyle(.roundedBorder)
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
                Text("Found \(model.projects.count) project(s).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Re-check Flutter") { Task { await model.checkFlutter() } }
                .buttonStyle(.secondary)
            Spacer()
        }
    }
}
