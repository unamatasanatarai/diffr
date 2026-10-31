---
date: 2026-10-31T09:51:00+01:00
repos: []
flow: prd
topic: "Visual Diff"
type: research
tags: [research, visual-diff, appkit, swift, diff-algorithm, scrolling]
status: complete
---

# Research: Visual Diff

## Research Question

1. In `Sources/App/AppDelegate.swift` and `scripts/config.sh`, how is the current application lifecycle and activation policy configured (e.g., menu-bar accessory vs. regular desktop window app), and what window management or document structures exist today?
2. In `Package.swift`, what external dependencies and target platform versions are defined (macOS 12.0+), and what diffing algorithms (e.g., Myers diff, LCS) or text difference libraries are currently available or viable?
3. In AppKit (`NSScrollView`, `NSClipView`, `NSTextView`), what is the established pattern for bidirectional synchronized scrolling (both vertical and horizontal) between two scroll views while avoiding scroll event feedback loops or rubber-banding jitter?
4. In AppKit text architecture (`NSTextView`, `NSLayoutManager`, `NSTextLayoutManager`), how are non-printable/invisible characters (spaces, tabs, newlines) rendered with editable plaintext support and customizable dim opacity?
5. How does AppKit's native text search system (`NSTextFinder`, `performTextFinderAction`, find bar) integrate across a dual-pane side-by-side editing layout?
6. What are the industry-standard color conventions for diff representations (additions, deletions, line highlights, gutter markers) across macOS light and dark modes?
7. How can a middle separator view in AppKit observe and track line layout and scroll positions from both text panes to position interactive controls (per-chunk copy arrows) and layout widgets (invisible characters toggle)?

## Research Methodology

This document describes the current codebase and AppKit runtime environment using facts from live code, tests, build scripts, and AppKit framework contracts. Concrete command executions (`make test`, Swift CLI evaluations) verify the testing baseline and runtime capabilities.

## Summary

The repository currently provides a minimal boilerplate macOS application configured as a headless menu-bar accessory (`NSApp.setActivationPolicy(.accessory)` and `LSUIElement=true`). It has no windows, document controllers, or text editing interfaces. The build system (`scripts/build.sh`) compiles all Swift source files directly using `swiftc` without external packages or CocoaPods, and targets macOS 12.0+.

Implementing the visual diff editor specified in `spec.md` requires transitioning the app to a standard windowed desktop application (`.regular` activation policy) and building a three-column AppKit user interface: Left `NSTextView` editor, Middle Gutter/Separator view with chunk action controls and stats, and Right `NSTextView` editor.

Swift's standard library provides native Myers diff computation via `Collection.difference(from:)`, enabling high-performance line diffing without external dependencies. AppKit's `NSClipView` bounds observation mechanism (`NSView.boundsDidChangeNotification`) supports bidirectional synchronized scrolling when protected by a re-entrancy flag. Invisible whitespace rendering can be achieved without disrupting text storage or editing by subclassing `NSLayoutManager` to draw custom glyphs for spaces, tabs, and newlines at dim opacity.

## Detailed Findings

### 1. The Application Currently Runs Exclusively as an Accessory Menu Bar Agent Without Window Support

In [Sources/App/AppDelegate.swift](file:///Users/citizen/dev/diffr/Sources/App/AppDelegate.swift#L6-L10), the application configures an accessory activation policy upon launch:

```swift
// Sources/App/AppDelegate.swift:6-10
public func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    statusBarController = StatusBarController()
    NSLog("%@ started successfully.", AppConfig.appName)
}
```

In [scripts/config.sh](file:///Users/citizen/dev/diffr/scripts/config.sh#L11), `export LS_UI_ELEMENT="${LS_UI_ELEMENT:-true}"` injects `<key>LSUIElement</key><true/>` into the generated `Info.plist` during `scripts/build.sh`. This prevents the application from appearing in the macOS Dock or presenting an application menu bar.

Furthermore:
- In [Sources/App/AppDelegate.swift](file:///Users/citizen/dev/diffr/Sources/App/AppDelegate.swift#L12-L14), `applicationShouldTerminateAfterLastWindowClosed` returns `false`.
- The only UI controller in the codebase is [Sources/App/StatusBarController.swift](file:///Users/citizen/dev/diffr/Sources/App/StatusBarController.swift), which registers an `NSStatusItem` in the system menu bar.
- There are currently no instances of `NSWindow`, `NSWindowController`, `NSViewController`, or `NSDocument`.

```text
Current Application Lifecycle:
AppMain.main()
  └── NSApplication.run()
        └── AppDelegate.applicationDidFinishLaunching()
              ├── NSApp.setActivationPolicy(.accessory)
              └── StatusBarController.init()
                    ├── NSStatusBar.system.statusItem(...)
                    └── NSMenu (Quit action only)
```

To support a dual-pane visual diff editor window, the activation policy will need to be changed to `NSApplication.ActivationPolicy.regular`, `LSUIElement` configured to `false` in `scripts/config.sh`, and a dedicated window controller instantiated.

#### Testing Patterns
In [Tests/AppTests/AppTests.swift](file:///Users/citizen/dev/diffr/Tests/AppTests/AppTests.swift#L22-L26), tests verify that `StatusBarController` initializes and contains a menu with a Quit item. No window or document tests exist.

---

### 2. The Build Pipeline Compiles Sources Directly Without External Dependencies, While Swift Standard Library Provides Native CollectionDifference

In [Package.swift](file:///Users/citizen/dev/diffr/Package.swift#L15), `dependencies: []` is empty. The macOS platform deployment target is macOS 12.0:

```swift
// Package.swift:6-8
platforms: [
    .macOS(.v12)
]
```

In [scripts/build.sh](file:///Users/citizen/dev/diffr/scripts/build.sh#L57-L69), compilation is performed directly using `swiftc`:

```bash
# scripts/build.sh:63-68
swiftc -sdk "$sdk_path" \
    -O \
    -whole-module-optimization \
    -Xlinker -dead_strip \
    "${sources[@]}" \
    -o "${macos_dir}/${app_name}"
```

Similarly, [scripts/test.sh](file:///Users/citizen/dev/diffr/scripts/test.sh#L48-L52) compiles all non-`@main` source files alongside `Tests/AppTests/*.swift`.

#### Diff Computation via Swift Standard Library
Swift 5.1+ includes `Collection.difference(from:)` based on the Myers diff algorithm directly in the standard library. When applied to string arrays (`[String]`), it computes inserts and removals with exact element offsets:

```swift
let leftLines: [String] = leftText.components(separatedBy: "\n")
let rightLines: [String] = rightText.components(separatedBy: "\n")
let diff = rightLines.difference(from: leftLines)
```

To display side-by-side aligned diffs, raw differences can be grouped into contiguous `DiffHunk` blocks:
- **Equal (`.equal`)**: Lines present in both left and right at matching positions.
- **Insert (`.insert`)**: Lines present only on the right; the left pane has placeholder alignment padding.
- **Delete (`.delete`)**: Lines present only on the left; the right pane has placeholder alignment padding.
- **Modify (`.modify`)**: Replacement of a contiguous line block with differing lines.

This provides diff calculation with $O(ND)$ time complexity and zero external third-party package dependencies.

#### Testing Patterns
Tests in [Tests/AppTests/AppTests.swift](file:///Users/citizen/dev/diffr/Tests/AppTests/AppTests.swift) currently cover configuration strings (`AppConfig`). No diff algorithm tests exist yet.

---

### 3. Bidirectional Synchronous Scrolling in AppKit Requires Guarded Bounds Observation on NSClipView

In AppKit, an `NSTextView` is embedded inside an `NSScrollView` with an `NSClipView` as its `contentView`. When the user scrolls via trackpad, mouse wheel, or scrollbars, the `NSClipView` posts `NSView.boundsDidChangeNotification` (when `postsBoundsChangedNotifications = true`).

#### Feedback Loop Prevention
If View A's scroll notification updates View B's bounds, View B will post a scroll notification that would otherwise update View A, causing infinite recursion or erratic jitter.

The standard AppKit pattern uses a mutual synchronization coordinator with a re-entrancy guard:

```text
User Scrolls Left Pane
       │
       ▼
Left ClipView posts boundsDidChangeNotification
       │
       ▼
ScrollCoordinator:
  if isSynchronizing { return }
  isSynchronizing = true
  defer { isSynchronizing = false }
  
  targetOrigin = NSPoint(x: leftClipView.bounds.origin.x,
                         y: leftClipView.bounds.origin.y)
  rightClipView.scroll(to: targetOrigin)
  rightScrollView.reflectScrolledClipView(rightClipView)
  gutterView.scroll(to: targetOrigin.y)
```

#### Dual-Axis Synchronization
`spec.md` requirement #6 states:
> "synchronized scroling. If I scroll donw or up on either one, the other moves accordingly. If i scroll left or right, the otherone scrolls sideways accordingly."

To achieve this:
1. Both `NSScrollView` instances have `hasVerticalScroller = true` and `hasHorizontalScroller = true`.
2. Both text views are configured with `isHorizontallyResizable = true` and `textContainer.widthTracksTextView = false` so long lines scroll horizontally instead of soft-wrapping.
3. Coordinate translation synchronizes both `bounds.origin.x` and `bounds.origin.y`.
4. Gutter view observes vertical scroll offset to align copy action buttons with corresponding line chunks.

#### Testing Patterns
No scroll view components or tests currently exist.

---

### 4. Non-Printable Characters Can Be Rendered at Custom Opacity by Subclassing NSLayoutManager

In AppKit's text system (TextKit 1), glyph layout and drawing are managed by `NSLayoutManager`. Subclassing `NSLayoutManager` and overriding `drawGlyphs(forGlyphRange:at:)` allows drawing invisible character symbols without modifying the backing `NSTextStorage` or breaking user editing:

```swift
public class InvisibilityLayoutManager: NSLayoutManager {
    public var showsInvisibles: Bool = false {
        didSet {
            guard showsInvisibles != oldValue else { return }
            // Invalidate display across all text containers
            firstTextView?.needsDisplay = true
        }
    }
    
    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        
        guard showsInvisibles, let textStorage = self.textStorage else { return }
        
        let characterRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let string = textStorage.string as NSString
        let dimAttributes: [NSAttributedString.Key: Any] = [
            .font: self.firstTextView?.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.35)
        ]
        
        // Scan string and draw symbols:
        // Space ' ' -> '·' (U+00B7 Middle Dot)
        // Tab '\t'  -> '→' (U+2192 Rightwards Arrow)
        // Newline '\n' -> '↵' (U+21B5 Carriage Return Arrow)
    }
}
```

#### Key Characteristics:
- **Plaintext and editable**: Text editing, typing, copy/paste, and undo/redo remain untouched because glyph substitution happens purely during visual rendering.
- **Dim opacity**: Drawing with `.withAlphaComponent(0.25 - 0.35)` or `NSColor.tertiaryLabelColor` satisfies `spec.md` requirement #8 ("must be very dim, but still visible").
- **Middle pane toggle**: The middle separator contains an `NSButton` checkbox that toggles `showsInvisibles` on both left and right layout managers simultaneously.

#### Testing Patterns
No layout manager or invisible rendering code exists in the codebase today.

---

### 5. Native Find and Replace Integrates via NSTextFinder and Shared Find Action Targets

In AppKit, `NSTextView` provides built-in integration with `NSTextFinder`. Setting:
```swift
textView.isIncrementalSearchingEnabled = true
textView.usesFindBar = true
```
gives each editor native find and replace functionality (Command-F for Find, Command-Option-F for Replace), standard regular expression / ignore-case options, and high-performance highlight matching.

For a side-by-side dual-pane visual diff app:
1. Standard macOS Edit menu items (`performFindPanelAction:`, `performTextFinderAction:`) automatically route through the responder chain to whichever `NSTextView` currently has first responder focus.
2. A unified find bar or per-pane find bar can be displayed above the editor views.
3. Because both panes are editable plaintext (`spec.md` #4), `NSTextFinder` supports both finding occurrences and replacing text in either pane.

#### Testing Patterns
No find and replace code or tests currently exist.

---

### 6. Visual Diff Standards Employ Semantically Tinted Backgrounds and Borders Across Light and Dark Appearances

Visual diff tools (Git diff, GitHub, VS Code, Kaleidoscope, FileMerge) adhere to industry-standard color conventions for additions, deletions, and modifications:

| Diff Type | Pane Location | Light Mode Tint | Dark Mode Tint | Gutter Indicator |
|---|---|---|---|---|
| **Addition** | Right Pane | `rgba(46, 160, 67, 0.15)` (#E6FFEC) | `rgba(46, 160, 67, 0.22)` (#13331C) | Green bar / `+` |
| **Deletion** | Left Pane | `rgba(248, 81, 73, 0.15)` (#FFEBE9) | `rgba(248, 81, 73, 0.22)` (#3D1418) | Red bar / `-` |
| **Modification** | Left & Right | Left: Red tint, Right: Green tint | Left: Dark red, Right: Dark green | Amber / Yellow marker |
| **Intra-line Word Diff** | Highlighted Range | Stronger saturation (0.35 alpha) | Stronger saturation (0.45 alpha) | None |
| **Identical / Unchanged** | Both Panes | Transparent / `NSColor.textBackgroundColor` | Transparent / `NSColor.textBackgroundColor` | None |

Using dynamic `NSColor(name:dynamicProvider:)` allows these background tints to adjust automatically when macOS switches between Light and Dark mode appearances.

#### Testing Patterns
Currently, [Sources/App/StatusBarController.swift](file:///Users/citizen/dev/diffr/Sources/App/StatusBarController.swift#L31-L47) implements appearance observation (`effectiveAppearance` and `AppleInterfaceThemeChangedNotification`), demonstrating the existing convention for theme responsiveness.

---

### 7. A Synchronized Middle Gutter Connects Aligned Blocks and Hosts Action Controls

`spec.md` specifies three distinct responsibilities for the middle area:
1. **Change copy arrows** (#3): "separator in the middle must have: arrow to copy changes to the left, to the right."
2. **Change statistics** (#7): "show stats of how many changes found. if no changes found, say 'files identical'".
3. **Invisibles toggle** (#8): "show invisible characters as an option (pane in the middle checkbox). must be very dim, but stil visible".

#### Middle Separator Architecture
The middle separator view consists of two regions:
1. **Header / Toolbar Area (Fixed Top)**:
   - Stats Label: Displays "Files identical" when diff count is zero, or "X changes found (+A, -D)" when differences exist.
   - Invisibles Checkbox: `NSButton(checkboxWithTitle: "Show Invisibles", target: ..., action: ...)`.
2. **Gutter Canvas (Scrollable Body)**:
   - A custom `NSView` whose height matches the text content and vertical scroll position of the text views.
   - For each diff hunk:
     - When left has a deletion/modification, an arrow button (`➔`) copies the left hunk content over to the right pane at the corresponding position.
     - When right has an addition/modification, an arrow button (`⬅`) copies the right hunk content over to the left pane at the corresponding position.
   - Interactive buttons can be lightweight custom button layers or `NSButton` subviews positioned at the vertical midpoint of each hunk.

```mermaid
graph TD
    Window[MainWindowController]
    Window --> Split[Main Split View / HStack]
    Split --> LeftScroll[Left NSScrollView]
    Split --> Gutter[Middle Separator Gutter]
    Split --> RightScroll[Right NSScrollView]
    
    LeftScroll --> LeftTextView[Left NSTextView (Editable)]
    RightScroll --> RightTextView[Right NSTextView (Editable)]
    
    Gutter --> GutterHeader[Top: Stats & Invisibles Checkbox]
    Gutter --> GutterBody[Body: Chunk Copy Buttons (Left <-> Right)]
    
    LeftTextView -.-> DiffCoordinator[DiffCoordinator]
    RightTextView -.-> DiffCoordinator
    DiffCoordinator --> Gutter
```

## Testing Patterns

| Test Suite | Location | Types of Tests | Current Status |
|---|---|---|---|
| Application Configuration | [Tests/AppTests/AppTests.swift](file:///Users/citizen/dev/diffr/Tests/AppTests/AppTests.swift#L5-L20) | App name, bundle ID, version, build number | 4 passing |
| Status Bar Controller | [Tests/AppTests/AppTests.swift](file:///Users/citizen/dev/diffr/Tests/AppTests/AppTests.swift#L22-L26) | Status item initialization and menu items | 1 passing |
| Diff Algorithm | *None* | Myers diff, hunk alignment, identical file detection | Not yet implemented |
| Synchronized Scrolling | *None* | Coordinate sync, recursion prevention | Not yet implemented |
| Middle Gutter Actions | *None* | Copy hunk left/right, statistics formatting | Not yet implemented |

### Executed Baseline Checks
Command run: `make test`
Observed result:
```text
Compiling unit test suite...
==================================================
         Running Swift Native Test Suite          
==================================================

--- Application Configuration & State Suite ---
  ✔ PASS: AppConfig returns valid non-empty application name (0.31ms)
  ✔ PASS: AppConfig returns valid bundle identifier (0.06ms)
  ✔ PASS: AppConfig provides version string (0.03ms)
  ✔ PASS: AppConfig provides build number (0.01ms)
  ✔ PASS: StatusBarController initializes menu correctly (33.04ms)

--------------------------------------------------
  Summary: 5 Passed | 0 Failed (Total: 34.00ms)
==================================================
```

## Code References

### Application Entry & Lifecycle
- [Sources/App/Main.swift](file:///Users/citizen/dev/diffr/Sources/App/Main.swift): Application entry point (`@main`).
- [Sources/App/AppDelegate.swift](file:///Users/citizen/dev/diffr/Sources/App/AppDelegate.swift): Application delegate; currently sets accessory policy and starts menu bar controller.
- [Sources/App/AppConfig.swift](file:///Users/citizen/dev/diffr/Sources/App/AppConfig.swift): Bundle and build metadata accessors.
- [Sources/App/StatusBarController.swift](file:///Users/citizen/dev/diffr/Sources/App/StatusBarController.swift): Existing menu bar status item and theme appearance observer.

### Build and Test Scripts
- [Makefile](file:///Users/citizen/dev/diffr/Makefile): Targets for `setup`, `build`, `run`, `test`, and `dmg`.
- [scripts/config.sh](file:///Users/citizen/dev/diffr/scripts/config.sh): Configuration variables, including `LS_UI_ELEMENT`.
- [scripts/build.sh](file:///Users/citizen/dev/diffr/scripts/build.sh): Direct `swiftc` compilation and `Info.plist` creation.
- [scripts/test.sh](file:///Users/citizen/dev/diffr/scripts/test.sh): Test runner compiling app sources and test cases.
- [Package.swift](file:///Users/citizen/dev/diffr/Package.swift): SPM manifest with zero dependencies targeting macOS 12.0+.

### Test Suite
- [Tests/AppTests/TestMain.swift](file:///Users/citizen/dev/diffr/Tests/AppTests/TestMain.swift): Test runner entry point.
- [Tests/AppTests/AppTests.swift](file:///Users/citizen/dev/diffr/Tests/AppTests/AppTests.swift): Current unit assertions.

## Architecture Documentation

### Target Component Architecture

```text
Sources/App/
├── Main.swift                    # Entry point
├── AppDelegate.swift             # Configures regular app policy & Main Window
├── Controllers/
│   ├── MainWindowController.swift# Manages window, toolbar, and layout
│   └── DiffCoordinator.swift    # Computes diffs, synchronizes scrolling & actions
├── Views/
│   ├── DiffSplitView.swift       # Left Pane, Gutter, Right Pane container
│   ├── DiffEditorView.swift      # NSScrollView + NSTextView wrapper
│   ├── DiffGutterView.swift      # Middle separator, hunk copy arrows, stats
│   └── InvisibilityLayoutManager.swift # Custom glyph rendering for invisibles
└── Models/
    ├── DiffModel.swift           # Line diff engine using CollectionDifference
    └── DiffHunk.swift            # Grouped diff chunks (equal, insert, delete, modify)
```

### Data Flow for Live Editing and Diffing

```text
User edits in Left or Right NSTextView
           │
           ▼ (NSTextStorageDelegate / textDidChange)
     DiffCoordinator
           │
           ├── 1. Recalculate line difference via DiffModel
           ├── 2. Update line highlight attributes in Left & Right textViews
           ├── 3. Update stats header ("X changes found" or "files identical")
           └── 4. Re-render middle gutter copy buttons
```

## Open Questions

None. The existing codebase and macOS AppKit APIs provide all necessary primitives to implement the visual diff editor.
