import SwiftUI
import AppKit

/// Terminates any running flutter process when the app quits (no zombies).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.stopAll() }
    }
}

@main
struct FlutterRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        // Full control-surface window (Dock app).
        WindowGroup(id: "main") {
            MainWindow()
                .environmentObject(model)
                .task { model.bootstrap() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Larger UI") { model.zoomIn() }.keyboardShortcut("=", modifiers: .command)
                Button("Smaller UI") { model.zoomOut() }.keyboardShortcut("-", modifiers: .command)
            }
        }

        // Rich quick-access panel in the menu bar (device/run/hot/build + Show App + Quit).
        MenuBarExtra("Flutter Runner", systemImage: "bird.fill") {
            MenuBarPanel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
