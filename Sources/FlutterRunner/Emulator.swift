import Foundation

/// An emulator/simulator from `flutter emulators`.
struct Emulator: Identifiable, Hashable {
    let id: String
    let name: String
    let manufacturer: String
    let platform: String

    var isIOS: Bool { platform.lowercased().contains("ios") }
    var symbol: String { isIOS ? "iphone" : "smartphone" }

    /// Parse the plain-text table emitted by `flutter emulators`
    /// (the `--machine` flag is empty in current Flutter releases).
    ///
    /// Rows look like: `Pixel_9  • Pixel 9  • Google  • android`
    static func parse(_ text: String) -> [Emulator] {
        text
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("•") }
            .compactMap { line in
                let cols = line.split(separator: "•").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard cols.count >= 4, cols[0].lowercased() != "id" else { return nil }
                return Emulator(
                    id: cols[0], name: cols[1],
                    manufacturer: cols[2], platform: cols[3])
            }
    }
}
