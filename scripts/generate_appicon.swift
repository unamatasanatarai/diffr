import AppKit
import WebKit

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svgURL = projectRoot.appendingPathComponent("Resources/AppIcon.svg")

guard FileManager.default.fileExists(atPath: svgURL.path) else {
    print("Error: Resources/AppIcon.svg not found at \(svgURL.path)")
    exit(1)
}

let svgData = try Data(contentsOf: svgURL)

let html = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; background: transparent; }
html, body { width: 1024px; height: 1024px; overflow: hidden; background: transparent; }
svg { width: 1024px; height: 1024px; display: block; }
</style>
</head>
<body>
\(String(data: svgData, encoding: .utf8)!)
</body>
</html>
"""

let config = WKWebViewConfiguration()
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024), configuration: config)
webView.setValue(false, forKey: "drawsBackground")

let semaphore = DispatchSemaphore(value: 0)
var masterImage: NSImage?

class NavDelegate: NSObject, WKNavigationDelegate {
    let sem: DispatchSemaphore
    init(sem: DispatchSemaphore) { self.sem = sem }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let snapConfig = WKSnapshotConfiguration()
            snapConfig.rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
            snapConfig.snapshotWidth = 1024
            webView.takeSnapshot(with: snapConfig) { image, error in
                masterImage = image
                self.sem.signal()
            }
        }
    }
}

let delegate = NavDelegate(sem: semaphore)
webView.navigationDelegate = delegate
webView.loadHTMLString(html, baseURL: svgURL)

let deadline = Date().addingTimeInterval(5)
while semaphore.wait(timeout: .now()) == .timedOut && Date() < deadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
}

guard let image = masterImage else {
    print("Error: snapshot failed to produce an image")
    exit(1)
}

func renderBitmap(from source: NSImage, width: Int, height: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current = context
    context?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                from: NSRect(origin: .zero, size: source.size),
                operation: .copy,
                fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

// 1. Write Resources/AppIcon.png (1024x1024 master)
let targetPNGURL = projectRoot.appendingPathComponent("Resources/AppIcon.png")
if let png1024 = renderBitmap(from: image, width: 1024, height: 1024) {
    try png1024.write(to: targetPNGURL)
    print("✅ Generated \(targetPNGURL.path)")
} else {
    print("Error: Failed to generate 1024x1024 PNG")
    exit(1)
}

// 2. Build iconset folder for iconutil
let tmpIconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon_\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: tmpIconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmpIconset) }

let iconSizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in iconSizes {
    if let data = renderBitmap(from: image, width: item.px, height: item.px) {
        let fileURL = tmpIconset.appendingPathComponent(item.name)
        try data.write(to: fileURL)
    } else {
        print("Error: Failed to render \(item.name)")
        exit(1)
    }
}

// 3. Compile ICNS with iconutil
let targetICNSURL = projectRoot.appendingPathComponent("Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", tmpIconset.path, "-o", targetICNSURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("✅ Generated \(targetICNSURL.path)")
} else {
    print("Error: iconutil exited with code \(process.terminationStatus)")
    exit(process.terminationStatus)
}
