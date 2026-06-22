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
            Task {
                isScanning = true
                await refreshDevices()
                await refreshEmulators()
                await refreshVersion()
                isScanning = false
            }
        }
    }
    @Published var devices: [Device] = []
    @Published var selectedDevice: Device? { didSet { scheduleSave() } }
    @Published var mode: RunMode = .debug { didSet { scheduleSave() } }
    @Published var flavor: String = "" { didSet { scheduleSave() } }

    @Published var emulators: [Emulator] = []
    @Published var flutterVersion: String = "—"
    @Published var flutterChannel: String = "—"
    @Published var dartVersion: String = "—"

    // Project metadata (read from pubspec.yaml)
    @Published var appName: String = "—"
    @Published var appVersion: String = "—"

    // Build options (Phase 05) — persisted per project
    @Published var buildName: String = "" { didSet { scheduleSave() } }
    @Published var buildNumber: String = "" { didSet { scheduleSave() } }
    @Published var dartDefines: String = "" { didSet { scheduleSave() } }   // space-separated KEY=VALUE
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

    /// Persisted per-project state (build options, signing, device, mode).
    private struct ProjectSettings: Codable {
        var mode = "debug"
        var deviceId: String?
        var flavor = ""
        var buildName = ""
        var buildNumber = ""
        var dartDefines = ""
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
        dartDefines = s.dartDefines
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
            buildName: buildName, buildNumber: buildNumber, dartDefines: dartDefines,
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
        for d in dartDefines.split(separator: " ") where d.contains("=") {
            args += ["--dart-define", String(d)]
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
    func runShell(_ command: String, label: String) {
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
            }
        }
    }

    /// Captures full stdout of a short command (used for `devices --machine`).
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

    /// The flutter command prefix: explicit override path, `fvm flutter`, or
    /// bare `flutter` resolved via the login shell PATH.
    private var flutterInvocation: String {
        if !flutterPathOverride.trimmingCharacters(in: .whitespaces).isEmpty {
            return shellQuote(flutterPathOverride)
        }
        return fvmActive ? "fvm flutter" : "flutter"
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

    func clearLog() { log = ""; pendingLog = "" }

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
        if log.utf16.count > 200_000 { log = String(log.suffix(150_000)) }
    }

    func revealArtifact() {
        guard let path = lastArtifactPath, let project = selectedProject else { return }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path)
            : project.appendingPathComponent(path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Single-quote a string for safe shell interpolation.
func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A pubspec dependency.
struct Dependency: Identifiable, Hashable {
    enum Kind: String { case runtime = "dependency", dev = "dev" }
    var id: String { name }
    let name: String
    let version: String
    let kind: Kind
}
