import AppKit

// Renders a 1024×1024 app icon: blue gradient rounded square + white bolt.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let clip = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
clip.addClip()
let grad = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.56, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.20, blue: 0.55, alpha: 1),
])!
grad.draw(in: rect, angle: -90)

if let sym = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil) {
    let conf = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .heavy)
    let s = sym.withSymbolConfiguration(conf) ?? sym
    let tinted = NSImage(size: s.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: s.size)
    s.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()
    let x = (size - s.size.width) / 2
    let y = (size - s.size.height) / 2
    tinted.draw(in: NSRect(x: x, y: y, width: s.size.width, height: s.size.height))
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("icon render failed\n".data(using: .utf8)!)
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
