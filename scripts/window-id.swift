import AppKit

// Print the CGWindowID of the largest on-screen window owned by FlutterRunner,
// so `screencapture -l<id>` can grab just the app window.
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let infos = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
var best: (id: Int, area: CGFloat) = (0, 0)
for w in infos {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "FlutterRunner",
          let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat],
          let id = w[kCGWindowNumber as String] as? Int else { continue }
    let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
    if area > best.area { best = (id, area) }
}
if best.id != 0 { print(best.id) } else { exit(2) }
