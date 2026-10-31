import AppKit

public enum DiffTheme {
    /// Helper to produce dynamic colors reacting to light/dark appearance
    public static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        return NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return (match == .darkAqua) ? dark : light
        }
    }

    // MARK: - Editor Line Backgrounds (GitHub Split Diff Style)

    public static let additionBackground: NSColor = dynamicColor(
            light: NSColor(red: 230/255, green: 255/255, blue: 236/255, alpha: 1.0), // #e6ffec
            dark: NSColor(red: 19/255, green: 51/255, blue: 28/255, alpha: 1.0)      // #13331c
        )

    public static let additionBorder: NSColor = dynamicColor(
            light: NSColor(red: 46/255, green: 160/255, blue: 67/255, alpha: 0.9),
            dark: NSColor(red: 63/255, green: 185/255, blue: 80/255, alpha: 0.9)
        )

    public static let additionGutterBackground: NSColor = dynamicColor(
            light: NSColor(red: 204/255, green: 255/255, blue: 216/255, alpha: 1.0), // #ccffd8
            dark: NSColor(red: 22/255, green: 60/255, blue: 34/255, alpha: 1.0)
        )

    public static let additionIndicatorColor: NSColor = dynamicColor(
            light: NSColor(red: 26/255, green: 127/255, blue: 55/255, alpha: 1.0), // #1a7f37
            dark: NSColor(red: 63/255, green: 185/255, blue: 80/255, alpha: 1.0)   // #3fb950
        )

    public static let additionWordHighlight: NSColor = dynamicColor(
            light: NSColor(red: 171/255, green: 242/255, blue: 188/255, alpha: 1.0), // #abf2bc
            dark: NSColor(red: 35/255, green: 134/255, blue: 54/255, alpha: 1.0)
        )

    public static let deletionBackground: NSColor = dynamicColor(
            light: NSColor(red: 255/255, green: 235/255, blue: 233/255, alpha: 1.0), // #ffebe9
            dark: NSColor(red: 61/255, green: 20/255, blue: 24/255, alpha: 1.0)       // #3d1418
        )

    public static let deletionBorder: NSColor = dynamicColor(
            light: NSColor(red: 248/255, green: 81/255, blue: 73/255, alpha: 0.9),
            dark: NSColor(red: 248/255, green: 81/255, blue: 73/255, alpha: 0.9)
        )

    public static let deletionGutterBackground: NSColor = dynamicColor(
            light: NSColor(red: 255/255, green: 220/255, blue: 224/255, alpha: 1.0), // #ffdce0
            dark: NSColor(red: 75/255, green: 26/255, blue: 32/255, alpha: 1.0)
        )

    public static let deletionIndicatorColor: NSColor = dynamicColor(
            light: NSColor(red: 207/255, green: 34/255, blue: 46/255, alpha: 1.0), // #cf222e
            dark: NSColor(red: 255/255, green: 123/255, blue: 114/255, alpha: 1.0) // #ff7b72
        )

    public static let deletionWordHighlight: NSColor = dynamicColor(
            light: NSColor(red: 255/255, green: 193/255, blue: 193/255, alpha: 1.0), // #ffc1c1
            dark: NSColor(red: 136/255, green: 38/255, blue: 45/255, alpha: 1.0)
        )

    // MARK: - Gutter & Spacers

    public static let gutterBackground: NSColor = dynamicColor(
            light: NSColor(calibratedWhite: 0.96, alpha: 1.0), // #f6f8fa
            dark: NSColor(calibratedWhite: 0.13, alpha: 1.0)   // #161b22
        )

    public static let gutterBorder: NSColor = dynamicColor(
            light: NSColor(calibratedWhite: 0.86, alpha: 1.0), // #d0d7de
            dark: NSColor(calibratedWhite: 0.22, alpha: 1.0)   // #30363d
        )

    public static let spacerBackground: NSColor = dynamicColor(
            light: NSColor(calibratedWhite: 0.94, alpha: 1.0),
            dark: NSColor(calibratedWhite: 0.11, alpha: 1.0)
        )

    public static let spacerStripeColor: NSColor = dynamicColor(
            light: NSColor(calibratedWhite: 0.82, alpha: 0.35),
            dark: NSColor(calibratedWhite: 0.30, alpha: 0.35)
        )

    public static let hoverArrowColor: NSColor = dynamicColor(
            light: NSColor(red: 9/255, green: 105/255, blue: 218/255, alpha: 1.0), // #0969da
            dark: NSColor(red: 88/255, green: 166/255, blue: 255/255, alpha: 1.0)  // #58a6ff
        )

    public static let invisibleCharacterColor: NSColor = dynamicColor(
            light: NSColor(calibratedWhite: 0.0, alpha: 0.28),
            dark: NSColor(calibratedWhite: 1.0, alpha: 0.28)
        )

    /// Resolves a (dynamic) color to a CGColor for the given view's appearance.
    /// `NSColor.cgColor` alone resolves against `NSAppearance.current`, which is often the
    /// default light appearance outside of drawing — producing wrong layer colors in Dark Mode.
    public static func cgColor(_ color: NSColor, for view: NSView) -> CGColor {
        var resolved = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    /// Hatched filler for spacer rows (lines that exist only on the other side).
    public static func drawSpacer(in rowRect: NSRect, dirtyRect: NSRect) {
        let visible = rowRect.intersection(dirtyRect)
        guard !visible.isEmpty else { return }

        spacerBackground.setFill()
        visible.fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: visible).addClip()
        spacerStripeColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.0
        let stripeSpacing: CGFloat = 20.0
        // Align stripes to a global grid so neighbouring dirty rects join seamlessly.
        var x = floor((visible.minX - rowRect.height) / stripeSpacing) * stripeSpacing
        while x < visible.maxX + rowRect.height {
            path.move(to: NSPoint(x: x, y: rowRect.origin.y))
            path.line(to: NSPoint(x: x + rowRect.height, y: rowRect.origin.y + rowRect.height))
            x += stripeSpacing
        }
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    public static let editorFont: NSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    public static let editorLineHeight: CGFloat = 22.0

    public static let editorTextInsetY: CGFloat = 4.0
}
