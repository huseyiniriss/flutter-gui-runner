import Foundation
import SwiftUI
import AppKit

/// Owns project/device state and the running `flutter` process.
@MainActor
final class AppModel: ObservableObject {
    /// Shared instance so the App, menu bar, and AppDelegate share one model.
    static let shared = AppModel()

    @Published var projects: [URL] = []
    @Published var selectedProject: URL? {
        didSet {
            persist()
            loadProjectSettings()
            loadDependencies()
            readPubspecMeta()
            scanEntryPoints()
            Task {
                isScanning = true
                await refreshDevices()
                await refreshEmulators()
                await refreshVersion()
                await refreshGit()
                isScanning = false
            }
        }
    }
    @Published var devices: [Device] = []
    @Published var selectedDevice: Device? { didSet { scheduleSave() } }
    @Published var mode: RunMode = .debug { didSet { scheduleSave() } }
    @Published var flavor: String = "" { didSet { scheduleSave() } }

    @Published var emulators: [Emulator] = []
    @Published var availableSDKs: [FlutterSDK] = []
    @Published var flutterVersion: String = "—"
    @Published var flutterChannel: String = "—"
    @Published var dartVersion: String = "—"

    // Project metadata (read from pubspec.yaml)
    @Published var appName: String = "—"
    @Published var appVersion: String = "—"

    // Build options (Phase 05) — persisted per project
    @Published var buildName: String = "" { didSet { scheduleSave() } }
    @Published var buildNumber: String = "" { didSet { scheduleSave() } }
    @Published var defines: [DartDefine] = [] { didSet { scheduleSave() } }  // --dart-define KEY=VALUE pairs
    @Published var target: String = "" { didSet { scheduleSave() } }        // e.g. lib/main_dev.dart
    @Published var splitPerAbi = false { didSet { scheduleSave() } }
    @Published var obfuscate = false { didSet { scheduleSave() } }
    @Published var lastArtifactPath: String?       // parsed "Built <path>"

    // Android signing — persisted per project
    @Published var keystorePath: String = "" { didSet { scheduleSave() } }
    @Published var keyAlias: String = "" { didSet { scheduleSave() } }
    @Published var storePassword: String = "" { didSet { scheduleSave() } }
    @Published var keyPassword: String = "" { didSet { scheduleSave() } }

    // Dependencies (Phase 06)
    @Published var dependencies: [Dependency] = []

    // Entry points (lib/main*.dart) + git
    @Published var entryPoints: [String] = ["lib/main.dart"]
    @Published var isGitRepo = false
    @Published var gitBranches: [String] = []
    @Published var currentBranch: String = ""

    /// Codable form of a dart-define pair (kept separate from the UI model so
    /// persisted JSON is stable and doesn't store transient ids).
    struct StoredDefine: Codable { var key: String; var value: String; var enabled: Bool? }

    /// Persisted per-project state (build options, signing, device, mode).
    private struct ProjectSettings: Codable {
        var mode = "debug"
        var deviceId: String?
        var flavor = ""
        var buildName = ""
        var buildNumber = ""
        var dartDefines = ""                 // legacy space-separated form (migration)
        var defines: [StoredDefine]?         // structured key/value pairs
        var target = ""
        var splitPerAbi = false
        var obfuscate = false
        var keystorePath = ""
        var keyAlias = ""
        var storePassword = ""
        var keyPassword = ""
    }
    private var isLoadingSettings = false
    private var saveTask: Task<Void, Never>?
    private var pendingDeviceId: String?

    // Settings (Phase 07 / robustness)
    @Published var flutterPathOverride: String = "" { didSet { defaults.set(flutterPathOverride, forKey: "flutterPathOverride") } }
    @Published var useFvm: Bool = true { didSet { defaults.set(useFvm, forKey: "useFvm") } }
    @Published var scanRootPath: String = "~/Documents/projects" { didSet { defaults.set(scanRootPath, forKey: "scanRootPath") } }

    @Published var flutterAvailable = true

    /// UI size (0…5). Maps to a DynamicTypeSize so text + controls scale and reflow.
    @Published var uiScaleIndex: Int = 2 {
        didSet { defaults.set(uiScaleIndex, forKey: "uiScaleIndex") }
    }
    private let typeSizes: [DynamicTypeSize] = [.xSmall, .small, .large, .xLarge, .xxLarge, .xxxLarge]
    var dynamicType: DynamicTypeSize { typeSizes[min(max(uiScaleIndex, 0), typeSizes.count - 1)] }
    func zoomIn() { uiScaleIndex = min(uiScaleIndex + 1, typeSizes.count - 1) }
    func zoomOut() { uiScaleIndex = max(uiScaleIndex - 1, 0) }

    /// Terminal/log pane height — drag the divider to resize; persisted.
    @Published var logHeight: CGFloat = 200 {
        didSet { defaults.set(Double(logHeight), forKey: "logHeight") }
    }
    /// Monospaced log font size: 12.5pt at the default UI size, scaling around it.
    var logFontSize: CGFloat { max(9, 12.5 + CGFloat(uiScaleIndex - 2) * 1.5) }

    @Published var log: String = ""
    @Published var logQuery: String = ""
    @Published var isRunning = false          // a `flutter run` session is live
    @Published var isBusy = false             // a one-shot command (build/clean) is running
    @Published var isScanning = false         // devices/emulators/version refresh in flight
    @Published var statusLine = "Ready"

    /// DevTools URL parsed from a live `flutter run` session; drives "Open DevTools".
    @Published var devToolsURL: String?

    private var process: Process?
    private var pidFileURL: URL?

    private let defaults = UserDefaults.standard

    /// Root scanned for Flutter projects (dirs containing pubspec.yaml).
    private var scanRoot: URL {
        URL(fileURLWithPath: (scanRootPath as NSString).expandingTildeInPath)
    }

    /// Whether the selected project should use FVM.
    var fvmActive: Bool {
        guard useFvm, let p = selectedProject else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: p.appendingPathComponent(".fvmrc").path)
            || fm.fileExists(atPath: p.appendingPathComponent(".fvm").path)
    }

    // MARK: - Lifecycle

    func bootstrap() {
        flutterPathOverride = defaults.string(forKey: "flutterPathOverride") ?? ""
        useFvm = defaults.object(forKey: "useFvm") as? Bool ?? true
        scanRootPath = defaults.string(forKey: "scanRootPath") ?? "~/Documents/projects"
        uiScaleIndex = defaults.object(forKey: "uiScaleIndex") as? Int ?? 2
        if let h = defaults.object(forKey: "logHeight") as? Double { logHeight = CGFloat(h) }

        discoverProjects()
        discoverSDKs()
        if let saved = defaults.string(forKey: "selectedProject"),
           let url = projects.first(where: { $0.path == saved }) {
            selectedProject = url
        } else {
            selectedProject = projects.first
        }
        Task { await checkFlutter() }
    }

    /// Verify a Flutter SDK is reachable; drives the missing-SDK banner.
    func checkFlutter() async {
        let out = await runCapture(args: ["--version"], project: selectedProject)
        flutterAvailable = out.contains("Flutter")
    }

    func rescan() {
        discoverProjects()
        if selectedProject == nil { selectedProject = projects.first }
    }

    private func persist() {
        defaults.set(selectedProject?.path, forKey: "selectedProject")
    }

    // MARK: - Per-project settings persistence

    private func settingsKey(_ project: URL) -> String { "settings::\(project.path)" }

    private func loadProjectSettings() {
        guard let project = selectedProject else { return }
        isLoadingSettings = true
        defer { isLoadingSettings = false }
        var s = ProjectSettings()
        if let data = defaults.data(forKey: settingsKey(project)),
           let decoded = try? JSONDecoder().decode(ProjectSettings.self, from: data) {
            s = decoded
        }
        mode = RunMode(rawValue: s.mode) ?? .debug
        flavor = s.flavor
        buildName = s.buildName
        buildNumber = s.buildNumber
        if let stored = s.defines {
            defines = stored.map { DartDefine(key: $0.key, value: $0.value, enabled: $0.enabled ?? true) }
        } else {
            defines = AppModel.parseDefines(s.dartDefines)   // migrate legacy string
        }
        target = s.target
        splitPerAbi = s.splitPerAbi
        obfuscate = s.obfuscate
        keystorePath = s.keystorePath
        keyAlias = s.keyAlias
        storePassword = s.storePassword
        keyPassword = s.keyPassword
        pendingDeviceId = s.deviceId        // applied after devices load
    }

    /// Debounced save so rapid typing doesn't thrash UserDefaults.
    func scheduleSave() {
        guard !isLoadingSettings else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.saveProjectSettings()
        }
    }

    private func saveProjectSettings() {
        guard let project = selectedProject else { return }
        let s = ProjectSettings(
            mode: mode.rawValue, deviceId: selectedDevice?.id, flavor: flavor,
            buildName: buildName, buildNumber: buildNumber,
            dartDefines: defines.map { "\($0.key)=\($0.value)" }.joined(separator: " "),
            defines: defines.map { StoredDefine(key: $0.key, value: $0.value, enabled: $0.enabled) },
            target: target, splitPerAbi: splitPerAbi, obfuscate: obfuscate,
            keystorePath: keystorePath, keyAlias: keyAlias,
            storePassword: storePassword, keyPassword: keyPassword)
        if let data = try? JSONEncoder().encode(s) {
            defaults.set(data, forKey: settingsKey(project))
        }
    }

    /// Read app name + version from pubspec; prefill build name/number if empty.
    private func readPubspecMeta() {
        appName = "—"; appVersion = "—"
        guard let project = selectedProject,
              let text = try? String(
                contentsOf: project.appendingPathComponent("pubspec.yaml"), encoding: .utf8)
        else { return }
        for line in text.split(separator: "\n").map(String.init) {
            if line.hasPrefix("name:") {
                appName = line.replacingOccurrences(of: "name:", with: "").trimmed
            }
            if line.hasPrefix("version:") {
                let v = line.replacingOccurrences(of: "version:", with: "").trimmed
                appVersion = v
                // version is "<name>+<number>", e.g. 1.2.0+42
                let parts = v.split(separator: "+", maxSplits: 1).map(String.init)
                if buildName.isEmpty, let n = parts.first { buildName = n }
                if buildNumber.isEmpty, parts.count > 1 { buildNumber = parts[1] }
            }
        }
    }

    // MARK: - Entry points (lib/main*.dart)

    /// Find candidate entry files under lib/ so the user can pick dev/prod mains.
    func scanEntryPoints() {
        var found: Set<String> = ["lib/main.dart"]
        guard let project = selectedProject else { entryPoints = ["lib/main.dart"]; return }
        let lib = project.appendingPathComponent("lib")
        let fm = FileManager.default
        if let en = fm.enumerator(at: lib, includingPropertiesForKeys: nil) {
            for case let url as URL in en {
                let name = url.lastPathComponent
                // main.dart, main_dev.dart, main_prod.dart, app_main.dart, …
                if name.hasSuffix(".dart"), name.contains("main") {
                    let rel = url.path.replacingOccurrences(of: project.path + "/", with: "")
                    found.insert(rel)
                }
            }
        }
        entryPoints = found.sorted()
        // keep the saved target if still valid, else default
        if target.trimmed.isEmpty || !entryPoints.contains(target) {
            if !entryPoints.contains(target.trimmed) { target = "lib/main.dart" }
        }
    }

    // MARK: - Git

    func refreshGit() async {
        guard let project = selectedProject else { isGitRepo = false; return }
        let inside = await shellCapture("git rev-parse --is-inside-work-tree 2>/dev/null",
                                        project: project)
        isGitRepo = (inside.trimmed == "true")
        guard isGitRepo else { gitBranches = []; currentBranch = ""; return }
        currentBranch = (await shellCapture("git branch --show-current",
                                            project: project)).trimmed
        let raw = await shellCapture("git branch --format='%(refname:short)'", project: project)
        gitBranches = raw.split(separator: "\n").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    func reloadGit() { Task { await refreshGit() } }

    func checkoutBranch(_ branch: String) {
        guard !isBusy, !isRunning, branch != currentBranch else { return }
        runShell("git checkout \(shellQuote(branch))", label: "checkout \(branch)") { [weak self] in
            Task { await self?.refreshGit() }
        }
    }

    /// Run a basic git command, refreshing branch state afterwards.
    func git(_ command: String, label: String) {
        guard !isBusy, !isRunning else { return }
        runShell("git \(command)", label: label) { [weak self] in
            Task { await self?.refreshGit() }
        }
    }

    // MARK: - Project discovery

    func discoverProjects() {
        let fm = FileManager.default
        var found: [URL] = []
        if let entries = try? fm.contentsOfDirectory(
            at: scanRoot, includingPropertiesForKeys: [.isDirectoryKey]) {
            for dir in entries {
                let pubspec = dir.appendingPathComponent("pubspec.yaml")
                if fm.fileExists(atPath: pubspec.path) { found.append(dir) }
                // one level deeper (e.g. archive/<app>)
                if let subs = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil) {
                    for sub in subs where fm.fileExists(
                        atPath: sub.appendingPathComponent("pubspec.yaml").path) {
                        found.append(sub)
                    }
                }
            }
        }
        // include any manually added folders
        for path in defaults.stringArray(forKey: "customProjects") ?? [] {
            let url = URL(fileURLWithPath: path)
            if !found.contains(url) { found.append(url) }
        }
        projects = found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func addProject(_ url: URL) {
        var custom = defaults.stringArray(forKey: "customProjects") ?? []
        if !custom.contains(url.path) { custom.append(url.path) }
        defaults.set(custom, forKey: "customProjects")
        discoverProjects()
        selectedProject = url
    }

    /// Add several projects at once, persisting each as a custom entry, then
    /// select the first newly-added one.
    func addProjects(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var custom = defaults.stringArray(forKey: "customProjects") ?? []
        var firstNew: URL?
        for url in urls where !custom.contains(url.path) {
            custom.append(url.path)
            if firstNew == nil { firstNew = url }
        }
        defaults.set(custom, forKey: "customProjects")
        discoverProjects()
        if let sel = firstNew ?? urls.first { selectedProject = sel }
    }

    /// Whether a project was added manually (and can therefore be removed again).
    func isCustomProject(_ url: URL) -> Bool {
        (defaults.stringArray(forKey: "customProjects") ?? []).contains(url.path)
    }

    /// Forget a manually-added project. Projects found under the scan root will
    /// reappear on the next rescan — only custom entries are truly removable.
    func removeProject(_ url: URL) {
        var custom = defaults.stringArray(forKey: "customProjects") ?? []
        custom.removeAll { $0 == url.path }
        defaults.set(custom, forKey: "customProjects")
        discoverProjects()
        if selectedProject == url { selectedProject = projects.first }
    }

    /// Expand a chosen folder into the Flutter projects it represents: the folder
    /// itself if it has a pubspec.yaml, otherwise every child (and grandchild)
    /// that does — so picking one parent folder bulk-imports all apps inside it.
    func flutterProjectDirs(in folder: URL) -> [URL] {
        let fm = FileManager.default
        func hasPubspec(_ dir: URL) -> Bool {
            fm.fileExists(atPath: dir.appendingPathComponent("pubspec.yaml").path)
        }
        if hasPubspec(folder) { return [folder] }
        var found: [URL] = []
        if let children = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey]) {
            for child in children {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue
                else { continue }
                if hasPubspec(child) { found.append(child); continue }
                if let subs = try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil) {
                    for sub in subs where hasPubspec(sub) { found.append(sub) }
                }
            }
        }
        return found
    }

    /// Open a folder picker (multi-select) and add every Flutter project found in
    /// the chosen folders — one folder, several folders, or a parent that holds
    /// many apps all work.
    func chooseProjects() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Select one or more Flutter project folders (or a folder that contains several)."
        guard panel.runModal() == .OK else { return }
        var toAdd: [URL] = []
        for url in panel.urls {
            for dir in flutterProjectDirs(in: url) where !toAdd.contains(dir) { toAdd.append(dir) }
        }
        if toAdd.isEmpty {
            appendLog("⚠️ No pubspec.yaml found in the selected folder(s).\n")
        } else {
            addProjects(toAdd)
            appendLog("✅ Added \(toAdd.count) project(s).\n")
        }
    }

    // MARK: - Devices

    func refreshDevices() async {
        guard let project = selectedProject else { return }
        statusLine = "Scanning devices…"
        let output = await runCapture(
            args: ["devices", "--machine"], project: project)
        guard let data = output.data(using: .utf8),
              let list = try? JSONDecoder().decode([Device].self, from: data) else {
            devices = []; statusLine = "No devices"; return
        }
        devices = list
        // Restore the persisted device for this project, if still present.
        if let saved = pendingDeviceId, let match = list.first(where: { $0.id == saved }) {
            selectedDevice = match
            pendingDeviceId = nil
        }
        if let cur = selectedDevice, !list.contains(cur) { selectedDevice = nil }
        if selectedDevice == nil { selectedDevice = list.first }
        statusLine = "\(list.count) device(s)"
    }

    /// User-triggered refresh that drives the scanning spinner.
    func reloadDevices() {
        Task { isScanning = true; await refreshDevices(); isScanning = false }
    }

    // MARK: - Emulators

    func reloadEmulators() {
        Task { isScanning = true; await refreshEmulators(); isScanning = false }
    }

    func refreshEmulators() async {
        guard let project = selectedProject else { return }
        statusLine = "Scanning emulators…"
        let output = await runCapture(args: ["emulators"], project: project)
        emulators = Emulator.parse(output)
        statusLine = "\(emulators.count) emulator(s)"
    }

    func launchEmulator(_ emu: Emulator) {
        guard let project = selectedProject, !isBusy else { return }
        runOneShot(args: ["emulators", "--launch", emu.id],
                   project: project, label: "Launch \(emu.name)")
        // give it a moment, then refresh the live device list
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            await refreshDevices()
        }
    }

    func createEmulator() {
        guard let project = selectedProject, !isBusy else { return }
        runOneShot(args: ["emulators", "--create"], project: project,
                   label: "Create emulator")
    }

    // MARK: - SDK / version

    func refreshVersion() async {
        guard let project = selectedProject else { return }
        let out = await runCapture(args: ["--version"], project: project)
        // e.g. "Flutter 3.41.5 • channel stable • https://…"
        for line in out.split(separator: "\n").map(String.init) {
            if line.hasPrefix("Flutter") {
                let parts = line.split(separator: "•").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if let v = parts.first?.split(separator: " ").last {
                    flutterVersion = String(v)
                }
                if let ch = parts.first(where: { $0.hasPrefix("channel") }) {
                    flutterChannel = ch.replacingOccurrences(of: "channel ", with: "")
                }
            }
            if line.contains("Dart") {
                if let range = line.range(of: "Dart "),
                   let v = line[range.upperBound...].split(separator: " ").first {
                    dartVersion = String(v)
                }
            }
        }
    }

    func upgradeSDK() {
        guard let project = selectedProject, !isBusy, !isRunning else { return }
        runOneShot(args: ["upgrade"], project: project, label: "flutter upgrade")
    }

    // MARK: - SDK discovery / selection

    /// Find installed Flutter SDKs so the user can pick one instead of typing a
    /// path: the PATH default, every FVM-managed version, and common install dirs.
    func discoverSDKs() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var list: [FlutterSDK] = [FlutterSDK(path: "", label: "System (PATH)")]
        var seen = Set<String>()   // dedup by resolved binary path

        func add(binary: String, label: String) {
            guard fm.isExecutableFile(atPath: binary), !seen.contains(binary) else { return }
            seen.insert(binary)
            list.append(FlutterSDK(path: binary, label: label))
        }

        // FVM-managed versions: each subfolder is an SDK root.
        for base in ["\(home)/fvm/versions", "\(home)/.fvm/versions"] {
            guard let versions = try? fm.contentsOfDirectory(atPath: base) else { continue }
            for v in versions.sorted() {
                add(binary: "\(base)/\(v)/bin/flutter", label: "FVM · \(v)")
            }
        }

        // Common single-SDK install locations.
        for root in ["\(home)/development/flutter", "\(home)/flutter",
                     "\(home)/sdk/flutter", "\(home)/.flutter",
                     "/opt/homebrew/flutter", "/usr/local/flutter"] {
            add(binary: "\(root)/bin/flutter",
                label: (root as NSString).abbreviatingWithTildeInPath)
        }

        // Whatever the user configured, if it isn't already in the list.
        let override = flutterPathOverride.trimmed
        if !override.isEmpty, let bin = Self.resolveFlutterBinary(override) {
            add(binary: bin, label: "Custom · \((bin as NSString).abbreviatingWithTildeInPath)")
        }

        availableSDKs = list
    }

    /// The picker's current selection: the resolved binary of the active override,
    /// or "" for the PATH default.
    var selectedSDKPath: String {
        get {
            let override = flutterPathOverride.trimmed
            guard !override.isEmpty else { return "" }
            return Self.resolveFlutterBinary(override) ?? override
        }
        set {
            flutterPathOverride = newValue
            Task { await checkFlutter(); await refreshVersion() }
        }
    }

    func setChannel(_ channel: String) {
        guard let project = selectedProject, !isBusy, !isRunning else { return }
        runOneShot(args: ["channel", channel], project: project,
                   label: "channel \(channel)")
    }

    func doctor() {
        guard let project = selectedProject, !isBusy, !isRunning else { return }
        runOneShot(args: ["doctor", "-v"], project: project, label: "doctor")
    }

    // MARK: - Run / Stop / Hot reload

    func run() {
        guard !isRunning, let project = selectedProject, let device = selectedDevice
        else { return }
        clearLog()
        var args = ["run", "-d", device.id]
        if let flag = mode.flag { args.append(flag) }
        if !flavor.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append(contentsOf: ["--flavor", flavor])
        }
        if !target.trimmed.isEmpty, target.trimmed != "lib/main.dart" {
            args.append(contentsOf: ["--target", target.trimmed])
        }
        for d in defines where d.enabled && !d.key.trimmed.isEmpty {
            args += ["--dart-define", "\(d.key.trimmed)=\(d.value)"]
        }
        // pid-file lets us signal hot reload/restart reliably (no TTY needed).
        let pidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flutter-runner-\(UUID().uuidString).pid")
        pidFileURL = pidURL
        args.append(contentsOf: ["--pid-file", pidURL.path])

        statusLine = "Running on \(device.name) (\(mode.title))…"
        isRunning = true
        launchStreaming(args: args, project: project) { [weak self] in
            Task { @MainActor in
                self?.isRunning = false
                self?.statusLine = "Stopped"
                self?.process = nil
            }
        }
    }

    func stop() {
        guard let proc = process else { return }
        appendLog("\n⏹  Stopping…\n")
        proc.terminate()                  // SIGTERM → flutter shuts down the app
    }

    /// Terminate any running process; called on app quit to avoid zombies.
    func stopAll() {
        process?.terminate()
        process = nil
    }

    func hotReload() { signalRunner(SIGUSR1, note: "🔥 Hot reload") }
    func hotRestart() { signalRunner(SIGUSR2, note: "♻️  Hot restart") }

    private func signalRunner(_ sig: Int32, note: String) {
        guard isRunning, let pidURL = pidFileURL,
              let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
        appendLog("\n\(note)…\n")
        kill(pid, sig)
    }

    // MARK: - One-shot commands

    func build(_ artifact: String) {
        guard let project = selectedProject, !isBusy, !isRunning else { return }
        lastArtifactPath = nil
        var args = ["build", artifact]
        if artifact == "ios" { args.append("--no-codesign") }
        args.append(mode.flag ?? "--release")     // builds default to release
        if !buildName.trimmed.isEmpty { args += ["--build-name", buildName.trimmed] }
        if !buildNumber.trimmed.isEmpty { args += ["--build-number", buildNumber.trimmed] }
        if !flavor.trimmed.isEmpty { args += ["--flavor", flavor.trimmed] }
        if !target.trimmed.isEmpty { args += ["--target", target.trimmed] }
        if splitPerAbi && artifact == "apk" { args.append("--split-per-abi") }
        if obfuscate {
            args += ["--obfuscate", "--split-debug-info", "build/symbols"]
        }
        for d in defines where d.enabled && !d.key.trimmed.isEmpty {
            args += ["--dart-define", "\(d.key.trimmed)=\(d.value)"]
        }
        runOneShot(args: args, project: project, label: "Build \(artifact)")
    }

    func quick(_ args: [String], label: String) {
        guard let project = selectedProject, !isBusy, !isRunning else { return }
        runOneShot(args: args, project: project, label: label)
    }

    private func runOneShot(
        args: [String], project: URL, label: String,
        onDone: (@Sendable @MainActor () -> Void)? = nil
    ) {
        clearLog()
        isBusy = true
        statusLine = "\(label)…"
        launchStreaming(args: args, project: project) { [weak self] in
            Task { @MainActor in
                self?.isBusy = false
                self?.statusLine = "\(label) done"
                self?.process = nil
                onDone?()
            }
        }
    }

    // MARK: - Dependencies (Phase 06)

    /// Lightweight pubspec parse: collect entries under dependencies / dev_dependencies.
    func loadDependencies() {
        dependencies = []
        guard let project = selectedProject,
              let text = try? String(
                contentsOf: project.appendingPathComponent("pubspec.yaml"),
                encoding: .utf8)
        else { return }

        var section: Dependency.Kind?
        var result: [Dependency] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("dependencies:") { section = .runtime; continue }
            if line.hasPrefix("dev_dependencies:") { section = .dev; continue }
            // a new top-level key ends the current section
            if !line.hasPrefix(" "), !line.isEmpty, line.first != "#" { section = nil }
            guard let kind = section else { continue }
            // entries are indented exactly two spaces: "  name: ^1.2.3"
            guard line.hasPrefix("  "), !line.hasPrefix("    "),
                  let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let ver = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name.isEmpty || name == "flutter" || name == "flutter_test" { continue }
            result.append(Dependency(name: name, version: ver.isEmpty ? "—" : ver, kind: kind))
        }
        dependencies = result.sorted { $0.name < $1.name }
    }

    func addPackage(_ name: String, dev: Bool) {
        let n = name.trimmed
        guard !n.isEmpty, let project = selectedProject, !isBusy, !isRunning else { return }
        let args = dev ? ["pub", "add", "dev:\(n)"] : ["pub", "add", n]
        runOneShot(args: args, project: project, label: "pub add \(n)") { [weak self] in
            self?.loadDependencies()
        }
    }

    func removePackage(_ name: String) {
        guard let project = selectedProject, !isBusy, !isRunning else { return }
        runOneShot(args: ["pub", "remove", name], project: project,
                   label: "pub remove \(name)") { [weak self] in
            self?.loadDependencies()
        }
    }

    func outdated() { quick(["pub", "outdated"], label: "pub outdated") }

    /// Upgrade a single package to its latest allowed version.
    func upgradePackage(_ name: String) {
        guard let project = selectedProject, !isBusy, !isRunning else { return }
        runOneShot(args: ["pub", "upgrade", name], project: project,
                   label: "pub upgrade \(name)") { [weak self] in
            self?.loadDependencies()
        }
    }

    // MARK: - Android signing (Phase 05)

    /// Generate a keystore with keytool, then write android/key.properties.
    func generateKeystore() {
        guard !keystorePath.trimmed.isEmpty, !keyAlias.trimmed.isEmpty,
              !storePassword.isEmpty else {
            appendLog("⚠️ Set keystore path, alias and store password first.\n")
            return
        }
        let dname = "CN=\(appName), O=\(appName)"
        let cmd = "keytool -genkeypair -v "
            + "-keystore \(shellQuote(keystorePath)) "
            + "-storepass \(shellQuote(storePassword)) "
            + "-keypass \(shellQuote(keyPassword.isEmpty ? storePassword : keyPassword)) "
            + "-alias \(shellQuote(keyAlias)) "
            + "-keyalg RSA -keysize 2048 -validity 10000 "
            + "-dname \(shellQuote(dname))"
        runShell(cmd, label: "Generate keystore")
    }

    /// Write android/key.properties pointing at the configured keystore.
    func writeKeyProperties() {
        guard let project = selectedProject else { return }
        let content = """
        storePassword=\(storePassword)
        keyPassword=\(keyPassword.isEmpty ? storePassword : keyPassword)
        keyAlias=\(keyAlias)
        storeFile=\(keystorePath)
        """
        let url = project.appendingPathComponent("android/key.properties")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            appendLog("✅ Wrote \(url.path)\n")
            appendLog("ℹ️ Ensure android/key.properties is in .gitignore.\n")
        } catch {
            appendLog("❌ Failed to write key.properties: \(error.localizedDescription)\n")
        }
    }

    /// Pick a custom entry-point .dart file; stored as a project-relative path.
    func chooseEntryPoint() {
        guard let project = selectedProject else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.directoryURL = project.appendingPathComponent("lib")
        panel.prompt = "Use"
        panel.message = "Select the Dart entry file (e.g. lib/main_prod.dart)"
        if panel.runModal() == .OK, let url = panel.url {
            let prefix = project.path + "/"
            let rel = url.path.hasPrefix(prefix)
                ? String(url.path.dropFirst(prefix.count)) : url.path
            target = rel
            if !entryPoints.contains(rel) { entryPoints.append(rel); entryPoints.sort() }
        }
    }

    /// Pick the Flutter SDK folder (or binary) via a file panel.
    func chooseFlutterPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use"
        panel.message = "Select the Flutter SDK folder, its bin/ folder, or the flutter binary"
        if panel.runModal() == .OK, let url = panel.url {
            flutterPathOverride = url.path
            Task { await checkFlutter() }
        }
    }

    func chooseKeystore() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { keystorePath = url.path }
    }

    // MARK: - Process plumbing

    /// Runs `flutter <args>` in `project` via a login shell, streaming output
    /// into `log`. `onExit` fires when the process terminates.
    private func launchStreaming(
        args: [String], project: URL, onExit: @escaping @Sendable () -> Void
    ) {
        launchStreaming(process: makeProcess(args: args, project: project),
                        header: "▶️  flutter \(args.joined(separator: " "))\n📂 \(project.path)",
                        onExit: onExit)
    }

    private func launchStreaming(
        process proc: Process, header: String, onExit: @escaping @Sendable () -> Void
    ) {
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        let handler: @Sendable (FileHandle) -> Void = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let raw = String(data: data, encoding: .utf8) else { return }
            let s = AppModel.stripAnsi(raw)   // strip on the background queue
            Task { @MainActor in self?.appendLog(s) }
        }
        out.fileHandleForReading.readabilityHandler = handler
        err.fileHandleForReading.readabilityHandler = handler
        proc.terminationHandler = { _ in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            onExit()
        }
        do {
            try proc.run()
            process = proc
            appendLog("\(header)\n────────────────────────\n")
        } catch {
            appendLog("❌ Failed to start: \(error.localizedDescription)\n")
            onExit()
        }
    }

    /// Run an arbitrary shell command in the project dir (e.g. keytool).
    func runShell(_ command: String, label: String,
                  onDone: (@Sendable @MainActor () -> Void)? = nil) {
        guard let project = selectedProject, !isBusy, !isRunning else { return }
        clearLog(); isBusy = true; statusLine = "\(label)…"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "cd \(shellQuote(project.path)) && \(command)"]
        launchStreaming(process: proc, header: "▶️  \(command)") { [weak self] in
            Task { @MainActor in
                self?.isBusy = false
                self?.statusLine = "\(label) done"
                self?.process = nil
                onDone?()
            }
        }
    }

    /// Captures full stdout of a short flutter command (e.g. `devices --machine`).
    private func runCapture(args: [String], project: URL?) async -> String {
        await withCheckedContinuation { cont in
            let proc = makeProcess(args: args, project: project)
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe()
            proc.terminationHandler = { _ in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do { try proc.run() } catch { cont.resume(returning: "") }
        }
    }

    /// Captures stdout of an arbitrary shell command (e.g. git), no flutter prefix.
    private func shellCapture(_ command: String, project: URL) async -> String {
        await withCheckedContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", "cd \(shellQuote(project.path)) && \(command)"]
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe()
            proc.terminationHandler = { _ in
                let data = out.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do { try proc.run() } catch { cont.resume(returning: "") }
        }
    }

    /// The flutter command prefix: explicit override path, `fvm flutter`, or
    /// bare `flutter` resolved via the login shell PATH.
    private var flutterInvocation: String {
        let override = flutterPathOverride.trimmed
        if !override.isEmpty, let bin = Self.resolveFlutterBinary(override) {
            return shellQuote(bin)
        }
        return fvmActive ? "fvm flutter" : "flutter"
    }

    /// Turn whatever the user typed in Settings into a runnable `flutter` binary:
    /// accepts the SDK root, its `bin/` dir, or the binary itself. Falls back to
    /// the raw (tilde-expanded) path so a custom wrapper still works.
    static func resolveFlutterBinary(_ raw: String) -> String? {
        let fm = FileManager.default
        var path = (raw as NSString).expandingTildeInPath
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        guard !path.isEmpty else { return nil }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return path   // doesn't exist yet — let the shell report a clear error
        }
        if isDir.boolValue {
            // SDK root → bin/flutter ; or they pointed at the bin dir → flutter
            for candidate in ["\(path)/bin/flutter", "\(path)/flutter"] {
                if fm.isExecutableFile(atPath: candidate) { return candidate }
            }
            return nil    // a directory with no flutter inside → fall back to PATH
        }
        return path       // a file (the binary or a wrapper script)
    }

    /// Builds a Process that runs flutter inside a login zsh so PATH and the
    /// iOS/Android toolchains resolve exactly like in a terminal.
    private func makeProcess(args: [String], project: URL?) -> Process {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let quoted = args.map(shellQuote).joined(separator: " ")
        let dir = project?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        let cmd = "cd \(shellQuote(dir)) && exec \(flutterInvocation) \(quoted)"
        proc.arguments = ["-lc", cmd]
        return proc
    }

    // ESC char (\u{1B}) is embedded directly; ICU regex doesn't accept \u{..}.
    // nonisolated: used from the read-handler background queue.
    nonisolated private static let ansi = try? NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[A-Za-z]")

    /// Strip ANSI escape codes. Safe to call off the main thread.
    nonisolated static func stripAnsi(_ raw: String) -> String {
        guard let ansi else { return raw }
        return ansi.stringByReplacingMatches(
            in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
    }

    private var pendingLog = ""
    private var flushScheduled = false

    func clearLog() { log = ""; pendingLog = ""; devToolsURL = nil }

    /// Buffer log text and flush at most ~6×/sec, so a chatty `flutter run`
    /// doesn't re-render the whole UI on every byte (was the beachball cause).
    func appendLog(_ s: String) {
        pendingLog += s
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.flushLog()
        }
    }

    private func flushLog() {
        flushScheduled = false
        guard !pendingLog.isEmpty else { return }
        let chunk = pendingLog
        pendingLog = ""
        log += chunk
        // Capture a built-artifact path for "Reveal in Finder".
        if let r = chunk.range(of: #"Built (\S.*?)(?: \([0-9.]+\w+\))?\.?$"#,
                               options: [.regularExpression]) {
            lastArtifactPath = chunk[r].replacingOccurrences(of: "Built ", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " .\n"))
        }
        // Capture the DevTools URL printed by `flutter run` for the browser button.
        if let r = chunk.range(of: #"(?:DevTools[^\n]*available at:|Dart DevTools[^\n]*at:)\s*(https?://\S+)"#,
                               options: [.regularExpression]),
           let u = chunk[r].range(of: #"https?://\S+"#, options: [.regularExpression]) {
            devToolsURL = String(chunk[u]).trimmingCharacters(in: CharacterSet(charactersIn: " .\n"))
        }
        if log.utf16.count > 200_000 { log = String(log.suffix(150_000)) }
    }

    func revealArtifact() {
        guard let path = lastArtifactPath, let project = selectedProject else { return }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
            : project.appendingPathComponent(path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - dart-define pairs

    /// Add (or update) a KEY=VALUE define. Existing keys are overwritten.
    func addDefine(key: String, value: String) {
        let k = key.trimmed
        guard !k.isEmpty else { return }
        if let i = defines.firstIndex(where: { $0.key == k }) {
            defines[i].value = value
        } else {
            defines.append(DartDefine(key: k, value: value))
        }
    }

    func removeDefine(_ d: DartDefine) {
        defines.removeAll { $0.id == d.id }
    }

    /// Enable/disable a define without removing it — excluded from run/build while off.
    func toggleDefine(_ d: DartDefine) {
        guard let i = defines.firstIndex(where: { $0.id == d.id }) else { return }
        defines[i].enabled.toggle()
    }

    /// Count of defines that will actually be passed to flutter.
    var enabledDefineCount: Int { defines.filter { $0.enabled && !$0.key.trimmed.isEmpty }.count }

    /// Parse a legacy space-separated "KEY=VAL KEY2=VAL2" string into pairs.
    static func parseDefines(_ raw: String) -> [DartDefine] {
        raw.split(separator: " ").compactMap { token in
            guard let eq = token.firstIndex(of: "="), eq != token.startIndex else { return nil }
            return DartDefine(key: String(token[token.startIndex..<eq]),
                              value: String(token[token.index(after: eq)...]))
        }
    }

    /// Open Flutter DevTools in the default browser, using the URL parsed from the
    /// live `flutter run` session (it's already wired to the running app).
    func openDevTools() {
        guard let s = devToolsURL, let url = URL(string: s) else {
            appendLog("\n⚠️ DevTools URL not available yet — run the app in debug mode, then try again.\n")
            return
        }
        NSWorkspace.shared.open(url)
        appendLog("\n🔧 Opening DevTools: \(s)\n")
    }
}

/// Single-quote a string for safe shell interpolation.
func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A single `--dart-define KEY=VALUE` pair (UI model).
/// `enabled` lets a pair be kept but excluded from the next run/build.
struct DartDefine: Identifiable, Hashable {
    var id = UUID()
    var key: String
    var value: String
    var enabled: Bool = true
}

/// An installed Flutter SDK the user can select. `path` is the `flutter`
/// binary (empty means "use the system PATH").
struct FlutterSDK: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let label: String
}

/// A pubspec dependency.
struct Dependency: Identifiable, Hashable {
    enum Kind: String { case runtime = "dependency", dev = "dev" }
    var id: String { name }
    let name: String
    let version: String
    let kind: Kind
}
