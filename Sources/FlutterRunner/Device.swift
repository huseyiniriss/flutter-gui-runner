import Foundation

/// A target reported by `flutter devices --machine`.
struct Device: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let targetPlatform: String
    let emulator: Bool
    let sdk: String?

    /// Human label for the picker, e.g. "iPhone Huse — ios".
    var label: String {
        "\(name) — \(targetPlatform)\(emulator ? " (emulator)" : "")"
    }

    /// SF Symbol that roughly matches the platform.
    var symbol: String {
        switch true {
        case targetPlatform.contains("ios"): return "iphone"
        case targetPlatform.contains("android"): return "smartphone"
        case targetPlatform.contains("darwin"): return "macbook"
        case targetPlatform.contains("web"): return "globe"
        case targetPlatform.contains("windows"): return "pc"
        case targetPlatform.contains("linux"): return "desktopcomputer"
        default: return "display"
        }
    }
}

/// Build / run mode.
enum RunMode: String, CaseIterable, Identifiable {
    case debug, profile, release
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Extra flag for `flutter run`; debug has none.
    var flag: String? {
        switch self {
        case .debug: return nil
        case .profile: return "--profile"
        case .release: return "--release"
        }
    }
}
