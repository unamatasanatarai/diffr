# Diffr — Product & Architecture Specification

**Version:** 1.0  
**Target Platform:** macOS 12.0+ (Monterey, Ventura, Sonoma, Sequoia)  
**Implementation Language:** Swift 5.7+ (Native AppKit / Cocoa)  
**Dependencies:** Zero external dependencies (Pure system frameworks: `AppKit`, `Foundation`, `UniformTypeIdentifiers`)  
**Repository Architecture:** Standard Swift Package Manager (SPM) with Makefile driver

---

## 1. Executive Summary & Product Vision

**Diffr** is a high-performance, native macOS side-by-side visual difference and merge tool designed with an exquisite, minimalist aesthetic. It provides instant, real-time, bi-directional diffing and merging of plaintext documents, source code, and arbitrary textual data.

### Core Product Principles:
1. **Zero External Dependencies:** Built entirely with native Apple frameworks (`AppKit`, `Cocoa`, `TextKit 1`). No third-party packages, web wrappers, or bloated runtimes.
2. **Byte-Exact Fidelity:** Swift's default string equality uses Unicode canonical equivalence (`"é" == "e\u{301}"`), which masks invisible encoding differences. Diffr compares exact UTF-8 byte streams so that Unicode normalization, trailing whitespace, line endings (CRLF vs. LF), and zero-width characters are faithfully highlighted.
3. **Non-Destructive Visual Row Alignment:** The underlying text buffer (`NSTextStorage`) is never modified to insert phantom lines or dummy placeholder strings. Visual row alignment across asymmetric diffs is achieved entirely through layout-level paragraph spacing (`NSParagraphStyle.paragraphSpacingBefore`) and text container insets.
4. **Exquisite Modern macOS Aesthetics:** A clean, borderless window with an integrated `NSVisualEffectView` header, refined typography (`monospacedSystemFont`), custom-drawn pill controls, dynamic light/dark mode adaptation, and a distinct lack of visual clutter.
5. **Rock-Solid Undo & State Integrity:** Every merge action (individual hunk move, copy all, pane clear, file drop) registers transparently with the macOS `NSUndoManager` as a named action, preserving cursor positions and enabling frictionless undo/redo cycles.

---

## 2. System Architecture & Component Hierarchy

```
┌────────────────────────────────────────────────────────────────────────┐
│                        MainWindowController                            │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │       Frosted Vibrancy Header Bar (NSVisualEffectView, 48pt)     │  │
│  │ [Traffic Lights] [-N] [➔]                  [↑] [↓] [⇄] [¶]       │  │
│  │                                     [⬅] [+N]                     │  │
│  │ 1px Hairline Bottom Border (SeparatorLineView)                   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                 DiffContainerView (Split View)                   │  │
│  │  ┌───────────────────────────────┐│ ┌───────────────────────────┐ │  │
│  │  │       Left DiffEditorView     ││ │    Right DiffEditorView   │ │  │
│  │  │ ┌───────┬──────────────┬────┐ ││ │ ┌────────┬──────────────┐ │ │  │
│  │  │ │Gutter │Text Scroll   │Seam│ ││ │ │ Gutter │Text Scroll   │ │ │  │
│  │  │ │(80pt) │View (NSClip) │(32)│ ││ │ │ (80pt) │View (NSClip) │ │ │  │
│  │  │ │       │              │➔   │ ││ │ │ ⬅      │              │ │ │  │
│  │  │ └───────┴──────────────┴────┘ ││ │ └────────┴──────────────┘ │ │  │
│  │  └───────────────────────────────┘│ └───────────────────────────┘ │  │
│  │                        1px Center Divider                         │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
          │                                     │
          ▼                                     ▼
 ┌───────────────────────┐            ┌───────────────────────┐
 │    DiffCoordinator    │◄──────────►│ DiffScrollCoordinator │
 │ (Diff Engine, Hunks,  │            │ (Bi-directional lock- │
 │  Layout Spacings, UI) │            │  step scroll sync)    │
 └───────────────────────┘            └───────────────────────┘
```

### Component Responsibility Matrix

| Component | Class | Primary Responsibility |
| :--- | :--- | :--- |
| **Window Controller** | `MainWindowController` | Full-size content window setup, toolbar header layout, menu validation, high-level action routing, open panel coordination. |
| **Split Container** | `DiffContainerView` | Holds Left and Right editors separated by a 1px vertical hairline divider; enforces 50/50 equal width constraints. |
| **Editor View** | `DiffEditorView` | Subviews: line number ruler, text scroll view, trailing seam margin (left only), floating action button, placeholder label. Manages geometry and text replacement. |
| **Diff Coordinator** | `DiffCoordinator` | Coordinates debounced background diffing, row alignment styling, hunk navigation, mouse hover tracking, and hunk/document merging. |
| **Scroll Coordinator** | `DiffScrollCoordinator` | Synchronizes vertical and horizontal scrolling across both panes in lockstep; accounts for find-bar geometry changes. |
| **Text View** | `DiffTextView` | Custom `NSTextView` subclass; intercepts background drawing to paint line addition/deletion tints and spacers under glyphs. Handles file drag-and-drop. |
| **Layout Manager** | `InvisibilityLayoutManager` | Custom `NSLayoutManager` subclass; draws intra-line word highlight pills, renders invisible control characters, and suppresses line-breaking for exotic whitespace. |
| **Gutter Ruler** | `LineNumberRulerView` | Displays line numbers, addition `+` and deletion `-` indicators, spacer hatches, and hosts the Right pane `⬅` merge button. |
| **Seam Margin** | `DiffActionMarginView` | 32pt text-free zone on the trailing edge of the Left pane; hosts the Left pane `➔` merge button and enforces an arrow cursor. |
| **Action Button** | `HunkActionButton` | Borderless, background-free floating button displaying `➔` or `⬅`; enlarges with glow on hover; triggers hunk copy. |
| **Status Capsule** | `ModernStatusCapsuleView` | Displays live diff state (`Ready for input`, `Files identical`, or `● N changes +A -D`). |

---

## 3. Data Models & Type Specifications

### 3.1. Enums and Basic Types

```swift
public enum DiffLineKind: Equatable {
    case unchanged  // Line identical on both sides
    case addition   // Line added on the right side
    case deletion   // Line deleted from the left side
    case spacer     // Visual blank filler row to maintain vertical alignment
}

public enum HunkKind: Equatable {
    case addition       // Only lines added on the right (left has spacers)
    case deletion       // Only lines removed from the left (right has spacers)
    case modification   // Both left and right lines altered in this block
}

public enum EditorSide: Equatable {
    case left   // Original / Base pane
    case right  // Modified / Target pane
}

public enum MergeDirection: Equatable {
    case leftToRight  // Copy from Left to Right (➔)
    case rightToLeft  // Copy from Right to Left (⬅)
}
```

### 3.2. Structs

#### `WordHighlightSpan`
Defines an intra-line character range to receive word-level highlight tinting:
```swift
public struct WordHighlightSpan: Equatable {
    public let range: NSRange          // UTF-16 character range within the line
    public let isEmphasized: Bool      // True if modified word
}
```

#### `AlignedDiffRow`
Represents one horizontal visual row in the side-by-side diff display:
```swift
public struct AlignedDiffRow: Equatable {
    public let leftLineNumber: Int?                  // 1-based line number or nil for spacer
    public let leftText: String?                     // Line text or nil for spacer
    public let leftKind: DiffLineKind                // .unchanged, .deletion, or .spacer
    public let leftWordHighlights: [WordHighlightSpan]

    public let rightLineNumber: Int?                 // 1-based line number or nil for spacer
    public let rightText: String?                    // Line text or nil for spacer
    public let rightKind: DiffLineKind               // .unchanged, .addition, or .spacer
    public let rightWordHighlights: [WordHighlightSpan]

    public let hunkIndex: Int?                       // Index into hunks array, or nil if unchanged
}
```

#### `DiffHunk`
Represents a contiguous block of differences:
```swift
public struct DiffHunk: Equatable {
    public let id: Int                               // Unique 0-based hunk identifier
    public let leftLineRange: Range<Int>             // 0-based line index range in left text
    public let rightLineRange: Range<Int>            // 0-based line index range in right text
    public let alignedRowRange: Range<Int>           // 0-based row range in alignedRows
    public let leftLines: [String]                   // Exact original lines in left pane
    public let rightLines: [String]                  // Exact original lines in right pane
    public let kind: HunkKind                        // .addition, .deletion, or .modification
}
```

#### `DiffResult`
The output of a complete diff computation:
```swift
public struct DiffResult: Equatable {
    public let hunks: [DiffHunk]
    public let alignedRows: [AlignedDiffRow]
    public let additionsCount: Int                   // Total added lines
    public let deletionsCount: Int                   // Total deleted lines
    public var isIdentical: Bool { hunks.isEmpty }
    public static var empty: DiffResult { ... }
}
```

#### `RulerRowInfo`
Metadata passed to gutter and margin views for rendering:
```swift
public struct RulerRowInfo: Equatable {
    public let lineNumber: Int?
    public let kind: DiffLineKind
    public let hunkIndex: Int?
}
```

---

## 4. Diff Engine & Algorithm Details

### 4.1. Text Ingestion & Exact Line Splitting
1. **Line Delimiter Invariant:** Text is split strictly on newline `\n` (ASCII `0x0A`).
2. **CRLF Preservation:** Carriage return `\r` (ASCII `0x0D`) is kept as part of the line substring. This guarantees that files with Windows `\r\n` line endings compared against Unix `\n` line endings are flagged as different.
3. **Trailing Empty Lines:** If a text ends with `\n`, `split(separator: 0x0A, omittingEmptySubsequences: false)` produces a trailing empty line string `""`. This guarantees that adding a final newline to a file is detected as a valid diff.
4. **UTF-16 Line Ranges:** `DiffEngine.lineRanges(in: NSString)` scans for `0x0A` unichars using raw buffers to construct `NSRange` entries encompassing line content and its terminating `\n`.

### 4.2. Byte-Exact String Equality & Interning
- **`LiteralText`:** A custom hashable struct wrapping `Substring`. Equality is evaluated via `lhs.value.utf8.elementsEqual(rhs.value.utf8)`. This avoids Swift's default Unicode canonical normalization (where `"e\u{301}"` equals `"é"`).
- **`TextInterner`:** Maps unique `LiteralText` instances to dense 0-indexed integers (`Int`). Diffing compares integers instead of strings, drastically reducing cache misses and allocation overhead.

### 4.3. Linear-Space Myers Diff Algorithm
- Implements Eugene Myers' 1986 linear-space bisection algorithm (middle snake).
- Evaluates optimal edit scripts in $O(ND)$ time and $O(N)$ space.
- **Pathological Guard (`costBudget = 60_000_000`):** When comparing two completely unrelated large files (e.g., 10,000 completely different lines), calculating the exact minimal edit graph could require up to $10,000 \times 10,000 = 10^8$ operations. If `(aHi - aLo) + (bHi - bLo)` exceeds the available budget limit `max(64, costBudget / size)`, the sub-problem terminates immediately, treating the entire region as a full replacement (deletion on left, addition on right).

### 4.4. Intra-Line Word Diff Engine
Word-level diffing is performed exclusively on `AlignedDiffRow` entries where `hunkKind == .modification`.
1. **Scalar Classification:** Characters are categorized into three classes:
   - `.word`: Alphanumerics and underscore `_`.
   - `.whitespace`: Space `' '` and Tab `'\t'`.
   - `.other`: All punctuation, operators, and symbols.
2. **Tokenization:** Runs of `.word` and `.whitespace` are grouped into single tokens. `.other` characters form individual 1-character tokens. Tokens maintain their UTF-16 character ranges without splitting surrogate pairs.
3. **Safety Limits:**
   - `maxLineLength = 20_000` UTF-16 units. Lines exceeding this skip word diffing to prevent minified JS one-liners from stalling the UI.
   - `maxTokenCount = 6_000` combined tokens per line pair.
   - `costBudget = 2_000_000` comparison operations.
4. **Span Merging:** Modified tokens separated solely by unchanged whitespace are merged into a single contiguous `WordHighlightSpan` so that phrases are highlighted smoothly rather than fragmented word-by-word.

---

## 5. Non-Destructive Vertical Row Alignment Mechanism

A critical architectural distinction of Diffr is that **no dummy spacer lines are ever injected into the text storage**. Both `NSTextStorage` instances contain only the user's authentic characters.

### 5.1. Paragraph Spacing Formula
Visual row alignment across deletions, additions, and modifications is achieved using `NSParagraphStyle.paragraphSpacingBefore`:
```
lineHeight = 22.0 pt
textInsetY = 4.0 pt

For any line fragment at 0-based line index i:
spacersCount = number of .spacer rows immediately preceding this line
paragraphSpacingBefore = CGFloat(spacersCount) * lineHeight
```

### 5.2. First Line Offset via Container Inset
`NSParagraphStyle.paragraphSpacingBefore` is ignored by Apple's `NSLayoutManager` on the very first paragraph of a document. Therefore:
```swift
if leadingSpacerRows > 0 {
    textView.textContainerInset = NSSize(
        width: 4.0,
        height: textInsetY + CGFloat(leadingSpacerRows) * lineHeight
    )
} else {
    textView.textContainerInset = NSSize(width: 4.0, height: textInsetY)
}
```

### 5.3. Control Character Suppression
To prevent lone carriage returns `\r`, vertical tabs `\u{000B}`, form feeds `\u{000C}`, next-lines `\u{0085}`, or Unicode line separators `\u{2028}` / paragraph separators `\u{2029}` from triggering unintended line wrapping in TextKit, `InvisibilityLayoutManager` overrides:
```swift
func layoutManager(_ layoutManager: NSLayoutManager,
                   shouldUse action: NSLayoutManager.ControlCharacterAction,
                   forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
    switch storage.character(at: charIndex) {
    case 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
        return .zeroAdvancement
    default:
        return action
    }
}
```

---

## 6. Visual Design System & UI Specifications

### 6.1. Design Tokens & Color Palette
Dynamic colors automatically respond to macOS Light and Dark appearance transitions:

| Token Name | Light Mode Value | Dark Mode Value | Usage |
| :--- | :--- | :--- | :--- |
| `additionBackground` | `#e6ffec` (230, 255, 236) | `#13331c` (19, 51, 28) | Editor added row background |
| `additionBorder` | `rgba(46, 160, 67, 0.9)` | `rgba(63, 185, 80, 0.9)` | 3px left edge accent bar |
| `additionGutterBackground` | `#ccffd8` (204, 255, 216) | `#163c22` (22, 60, 34) | Right gutter row background |
| `additionIndicatorColor` | `#1a7f37` (26, 127, 55) | `#3fb950` (63, 185, 80) | `+` glyph & stat chip text |
| `additionWordHighlight` | `#abf2bc` (171, 242, 188) | `#238636` (35, 134, 54) | Intra-line modified word pill |
| `deletionBackground` | `#ffebe9` (255, 235, 233) | `#3d1418` (61, 20, 24) | Editor deleted row background |
| `deletionBorder` | `rgba(248, 81, 73, 0.9)` | `rgba(248, 81, 73, 0.9)` | 3px left edge accent bar |
| `deletionGutterBackground` | `#ffdce0` (255, 220, 224) | `#4b1a20` (75, 26, 32) | Left gutter row background |
| `deletionIndicatorColor` | `#cf222e` (207, 34, 46) | `#ff7b72` (255, 123, 114) | `-` glyph & stat chip text |
| `deletionWordHighlight` | `#ffc1c1` (255, 193, 193) | `#88262d` (136, 38, 45) | Intra-line modified word pill |
| `gutterBackground` | `#f6f8fa` (White 0.96) | `#161b22` (White 0.13) | Base gutter background |
| `gutterBorder` | `#d0d7de` (White 0.86) | `#30363d` (White 0.22) | 1px vertical gutter border |
| `spacerBackground` | White 0.94 | White 0.11 | Empty spacer row fill |
| `spacerStripeColor` | White 0.82 @ 0.35 alpha | White 0.30 @ 0.35 alpha | 45° diagonal hatch lines |
| `hoverArrowColor` | `#0969da` (9, 105, 218) | `#58a6ff` (88, 166, 255) | Action button glyph & active dot |
| `invisibleCharacterColor` | White 0.0 @ 0.28 alpha | White 1.0 @ 0.28 alpha | Dim invisible character symbols |

### 6.2. Spacer Hatch Drawing Algorithm
When a row is a `.spacer`, both the editor background and the gutter paint an uninterrupted 45-degree diagonal hatched pattern:
```swift
let stripeSpacing: CGFloat = 20.0
let path = NSBezierPath()
path.lineWidth = 1.0
// Align stripes to a global grid so adjacent dirty rects join seamlessly:
var x = floor((visibleRect.minX - rowRect.height) / stripeSpacing) * stripeSpacing
while x < visibleRect.maxX + rowRect.height {
    path.move(to: NSPoint(x: x, y: rowRect.origin.y))
    path.line(to: NSPoint(x: x + rowRect.height, y: rowRect.origin.y + rowRect.height))
    x += stripeSpacing
}
path.stroke()
```

### 6.3. Typography
- **Editor Font:** `NSFont.monospacedSystemFont(ofSize: 13.0, weight: .regular)`
- **Line Height:** Exactly `22.0 pt` (`minimumLineHeight = 22.0`, `maximumLineHeight = 22.0`).
- **Gutter Line Numbers:** `NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .regular)`
- **Gutter Indicators (+/-):** `NSFont.monospacedSystemFont(ofSize: 12.0, weight: .bold)`
- **Toolbar & Buttons:** `NSFont.systemFont(ofSize: 11.5, weight: .medium)`
- **Pane Tags:** `NSFont.systemFont(ofSize: 10.5, weight: .bold)`

---

## 7. Layout Geometry & Hit-Testing

### 7.1. Window & Header Constraints
- **Window Size:** Default `1150 x 750 pt`, minimum `980 x 480 pt`.
- **Window Properties:** `styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`, `titleVisibility = .hidden`, `titlebarAppearsTransparent = true`.
- **Header Bar:** Height `48 pt`, `NSVisualEffectView` with `.headerView` material.
- **Traffic Light Offset:** Left header controls are insets `84 pt` from leading edge to leave clearance for macOS close/minimize/zoom buttons.
- **Bottom Header Border:** 1px hairline view (`SeparatorLineView`).

### 7.2. Split Container & Center Divider
- `leftEditor` leading anchor = `containerView.leadingAnchor`.
- `leftEditor` trailing anchor = `dividerView.leadingAnchor`.
- `dividerView.widthAnchor` = `1 pt`.
- `rightEditor` leading anchor = `dividerView.trailingAnchor`.
- `rightEditor` trailing anchor = `containerView.trailingAnchor`.
- `leftEditor.widthAnchor` = `rightEditor.widthAnchor` (equal 50/50 split).

### 7.3. Left Editor Internal Geometry
```
┌──────────────┬────────────────────────────────────────────┬─────────────┐
│ Gutter View  │ ScrollView (DiffTextView)                  │ Seam Margin │
│ Width: 80 pt │ Width: Flexible                            │ Width: 32 pt│
│              │                                            │             │
│ Line No:     │ Text Container Inset:                      │ Action Btn: │
│ x = 40 (max) │   x = 4 pt, y = 4 pt                       │ x = 4.0 pt  │
│ Del "-":     │ Line Fragment Padding: 5 pt                │ (bounds.w   │
│ x = 46       │ Line break mode: .byClipping (no wrap)     │  - 28.0 pt) │
│ Border: x=79 │                                            │ Arrow: ➔    │
└──────────────┴────────────────────────────────────────────┴─────────────┘
```
1. **Gutter View (`LineNumberRulerView`):** Width `80 pt`.
   - Line number text: aligned right to `x = 40.0 pt` (min `x = 4.0 pt`).
   - Deletion `-` glyph: positioned at `x = 46.0 pt`.
   - Trailing vertical border: `x = 79.0 pt`, width `1.0 pt`.
2. **ScrollView:** Leading anchor = `gutterView.trailingAnchor`, trailing anchor = `actionMarginView.leadingAnchor`.
3. **Seam Margin (`DiffActionMarginView`):** Width `32 pt`, trailing anchor = `leftEditor.trailingAnchor`.
   - **Text-Free Invariant:** Text can never flow into this 32pt strip, eliminating any overlap between text glyphs and the action arrow.
   - **Cursor Invariant:** Installs a tracking area with `.cursorUpdate` and `.mouseMoved` options that unconditionally call `NSCursor.arrow.set()`, guaranteeing the pointer never reverts to an `iBeam`.
4. **Action Button (`HunkActionButton`):** Width `24 pt`, height `24 pt`. Positioned at `x = bounds.width - 28.0 pt` (centered in the 32pt margin with a 4pt trailing margin from the center divider).

### 7.4. Right Editor Internal Geometry
```
┌───────────────────────────────────────────────────────────┬─────────────┐
│ Gutter View                                               │ ScrollView  │
│ Width: 80 pt                                              │ Width: Flex │
│                                                           │             │
│ Action Btn: x = 4.0 pt, Arrow: ⬅                          │ Text Inset: │
│ Line No:    x = 58.0 pt (max), x = 28.0 pt (min)          │   x = 4 pt  │
│ Add "+":    x = 64.0 pt                                   │   y = 4 pt  │
│ Border:     x = 79.0 pt                                   │             │
└───────────────────────────────────────────────────────────┴─────────────┘
```
1. **Gutter View (`LineNumberRulerView`):** Width `80 pt`.
   - Action Button (`HunkActionButton`): Width `24 pt`, height `24 pt`, positioned at `x = 4.0 pt` (adjacent to the center divider).
   - Line number text: aligned right to `x = 58.0 pt` (min `x = 28.0 pt`).
   - Addition `+` glyph: positioned at `x = 64.0 pt`.
   - Trailing vertical border: `x = 79.0 pt`, width `1.0 pt`.
2. **ScrollView:** Leading anchor = `gutterView.trailingAnchor`, trailing anchor = `rightEditor.trailingAnchor`.

---

## 8. Action Buttons & Mouse Interactions

### 8.1. Action Button Aesthetics
- **Zero Background / Zero Border:** `isBordered = false`, `layer?.backgroundColor = NSColor.clear.cgColor`. The button renders purely as a crisp unicode arrow glyph (`➔` or `⬅`).
- **Resting State:**
  - Font: `NSFont.systemFont(ofSize: 14.0, weight: .black)`
  - Color: `DiffTheme.hoverArrowColor`
- **Hovered State:**
  - Font: `NSFont.systemFont(ofSize: 16.5, weight: .black)`
  - Color: `NSColor.white` (Dark Mode) or `#034ca1` (Light Mode)
  - Glow Shadow: Blur radius `5.0 pt`, shadow color `DiffTheme.hoverArrowColor` at `0.95` alpha (Dark Mode) or `0.65` alpha (Light Mode).
- **Hit-Testing:** The entire `24 x 24 pt` bounding box responds to clicks, even though only the glyph is visible.

### 8.2. Button Vertical Clamping Algorithm
When a hunk spans dozens of lines and extends offscreen, the button must remain accessible rather than resting invisible in the offscreen center of the hunk:
```swift
let totalHunkHeight = CGFloat(hunk.alignedRowRange.count) * DiffTheme.editorLineHeight
let yInDoc = textInsetY + CGFloat(hunk.alignedRowRange.lowerBound) * DiffTheme.editorLineHeight
let yInView = yInDoc - documentOffsetY

let btnHeight: CGFloat = 24.0
let visibleTop: CGFloat = 0.0
let visibleBottom = bounds.height - btnHeight

let hunkTop = yInView
let hunkBottom = yInView + totalHunkHeight - btnHeight
var buttonY = yInView + (totalHunkHeight - btnHeight) / 2.0

// Clamp to visible viewport if hunk intersects the screen
if hunkBottom >= visibleTop && hunkTop <= visibleBottom {
    buttonY = min(max(buttonY, max(hunkTop, visibleTop)), min(hunkBottom, visibleBottom))
}
```

### 8.3. Cursor & Hover State Invariants
1. **Editor Text Areas:** Displays `NSCursor.iBeam`.
2. **Gutters & Seam Margin:** Unconditionally displays `NSCursor.arrow`.
3. **Action Button:** Installs tracking area with `.cursorUpdate`, `.mouseEnteredAndExited`, and calls `addCursorRect(bounds, cursor: .arrow)`.
4. **Hiding Rules:** If texts are identical or no hunk is hovered/active, `hunkActionButton.alphaValue = 0.0` and `hunkActionButton.isHidden = true` (an invisible button must never swallow clicks).

---

## 9. Bi-Directional Synchronized Scrolling

`DiffScrollCoordinator` synchronizes vertical and horizontal offsets between both editors in lockstep.

### 9.1. Document Offset Invariant
Scrolling is synchronized using the editor-local document offset rather than the raw clip view bounds:
```swift
var documentOffsetY: CGFloat {
    return -convert(NSPoint.zero, from: textView).y
}
```
*Rationale:* When the user invokes Find & Replace (`⌘F`), AppKit's find bar inserts itself above the text view inside `NSScrollView`, altering the clip view frame. Calculating offsets via `documentOffsetY` ensures the left and right panes maintain pixel-perfect row alignment even if one pane has a find bar open and the other does not.

### 9.2. Symmetric Document Sizing
In `DiffCoordinator.syncDocumentSizes()`:
```swift
let rows = diffResult.alignedRows.count
let leftSize = leftEditor.naturalDocumentSize(rowCount: rows)
let rightSize = rightEditor.naturalDocumentSize(rowCount: rows)
let commonSize = NSSize(
    width: max(leftSize.width, rightSize.width),
    height: max(leftSize.height, rightSize.height)
)
leftEditor.setDocumentSize(commonSize)
rightEditor.setDocumentSize(commonSize)
```
This guarantees that both panes have identical scroll ranges, preventing elastic bounce desynchronization.

---

## 10. Invisible Characters Engine

When the `¶ Invisibles` toggle is active (`showsInvisibles == true`), `InvisibilityLayoutManager.drawGlyphs` renders custom symbols directly over whitespace and control characters:

| Character | Code Point | Rendered Symbol | Visual Meaning |
| :--- | :--- | :---: | :--- |
| Space | `0x20` | `·` | Regular ASCII space |
| Tab | `0x09` | `→` | Tab character |
| Line Feed (LF) | `0x0A` | `↵` | Standard Unix newline |
| Carriage Return (CR) | `0x0D` | `␍` | Classic Mac / Windows newline component |
| Non-Breaking Spaces | `0x00A0`, `0x202F`, `0x2007` | `⍽` | Non-breaking space |
| Zero-Width / Bidi Marks | `0x200B`–`0x200D`, `0x2060`, `0xFEFF` | `¦` | Zero-width space, joiners, byte order mark |
| Exotic Line Breaks | `0x000B`, `0x000C`, `0x0085`, `0x2028`, `0x2029` | `¦` | Vertical tab, form feed, paragraph separator |

- **Color:** `DiffTheme.invisibleCharacterColor` (`rgba(0,0,0,0.28)` in Light Mode, `rgba(255,255,255,0.28)` in Dark Mode).
- **CRLF Nudging:** When `0x0A` is preceded by `0x0D`, the `↵` glyph is nudged horizontally by `+12 pt` so that `␍` and `↵` render legibly side-by-side without overlapping.

---

## 11. Hunk Merging, Programmatic Editing & Undo

### 11.1. Minimal-Range Text Replacement
When modifying text programmatically (e.g., copying a hunk or clearing panes), `replaceText(with:actionName:)` detects the longest common prefix and suffix:
```swift
// Determine common prefix and suffix to isolate minimal edit range
while prefix < minLength && oldBuf[prefix] == newBuf[prefix] { prefix += 1 }
while suffix < minLength - prefix && oldBuf[oldLength - 1 - suffix] == newBuf[newLength - 1 - suffix] { suffix += 1 }

// Safeguard: Never split a UTF-16 surrogate pair
if prefix > 0 && UTF16.isLeadSurrogate(oldBuf[prefix - 1]) { prefix -= 1 }
if suffix > 0 && UTF16.isTrailSurrogate(oldBuf[oldLength - suffix]) { suffix -= 1 }

let range = NSRange(location: prefix, length: oldLength - prefix - suffix)
let replacement = new.substring(with: NSRange(location: prefix, length: newLength - prefix - suffix))

if textView.shouldChangeText(in: range, replacementString: replacement) {
    textStorage.replaceCharacters(in: range, with: attributed)
    textView.didChangeText()
    textView.undoManager?.setActionName(actionName)
}
```
*Benefits:*
1. Preserves the user's undo stack integrity without resetting undo history.
2. Avoids full document re-layout on localized edits.
3. Does not corrupt multi-byte emojis or complex scripts.

### 11.2. Hunk Copying Validation
Before applying any hunk copy, `DiffEngine.applyHunk` validates that the target and source ranges still match the hunk's cached lines. If the user edited text concurrently while hovering, the click is rejected as stale, `NSSound.beep()` fires, and the diff is synchronously recomputed.

### 11.3. Undo Action Names
- Copying left to right: `"Copy Change to Right"`
- Copying right to left: `"Copy Change to Left"`
- Copy All left to right: `"Copy All to Right"`
- Copy All right to left: `"Copy All to Left"`
- Clearing both panes: `"Clear"`
- File drop / open: `"Open File"`

---

## 12. File Loading & Security Model

`TextFileLoader` validates external inputs before ingesting data into the editor:
1. **Size Limit:** Maximum file size `32 MB` (`33,554,432 bytes`). Files exceeding this throw `TextFileLoadError.tooLarge`.
2. **Regular File Verification:** Must be a regular file (`isRegularFile == true`). Directories or sockets throw `TextFileLoadError.notARegularFile`.
3. **Binary Detection:**
   - UTF-16 and UTF-32 files with valid BOM (`FF FE` or `FE FF`) are permitted.
   - For all other files, the first `64 KB` is scanned for NUL bytes (`0x00`). If found, the file is rejected with `TextFileLoadError.binary`.
4. **Encoding Fallback Chain:**
   1. UTF-8 (BOM preserved).
   2. Windows-1252 (`.windowsCP1252`).
   3. ISO-Latin-1 (`.isoLatin1`).
   4. macOS Roman (`.macOSRoman`).
   5. If all fail, throws `TextFileLoadError.undecodable`.

---

## 13. Keyboard Shortcuts & Menu Commands

| Menu Category | Action Item | Shortcut | Selector |
| :--- | :--- | :--- | :--- |
| **Diffr** | Quit Diffr | `Double ⌘Q` | `quitRequested(_:)` (Double-press within 1.75s to quit; single press shows floating HUD) |
| **File** | Open in Left Pane… | `⌘O` | `openInLeftPane(_:)` |
| **File** | Open in Right Pane… | `⌥⌘O` | `openInRightPane(_:)` |
| **File** | Clear Both Panes | — | `clearAllClicked` |
| **Edit** | Undo | `⌘Z` | `undo:` |
| **Edit** | Redo | `⇧⌘Z` | `redo:` |
| **Edit** | Find… | `⌘F` | `performTextFinderAction:` |
| **Edit** | Find and Replace… | `⌥⌘F` | `performTextFinderAction:` |
| **Edit** | Find Next | `⌘G` | `performTextFinderAction:` |
| **Edit** | Find Previous | `⇧⌘G` | `performTextFinderAction:` |
| **View** | Show Invisibles | `⇧⌘I` | `toggleInvisiblesFromMenu(_:)` |
| **Changes** | Next Change | `⌘]` | `nextChangeClicked` |
| **Changes** | Previous Change | `⌘[` | `prevChangeClicked` |
| **Changes** | Copy Change to Right | `⌥⌘→` | `copyChangeToRight(_:)` |
| **Changes** | Copy Change to Left | `⌥⌘←` | `copyChangeToLeft(_:)` |
| **Changes** | Copy All to Right | — | `copyAllRightClicked` |
| **Changes** | Copy All to Left | — | `copyAllLeftClicked` |


---

## 14. Complete Verification & Test Suite Matrix

The application must pass the following 22 test specifications in `Tests/AppTests/`:

```
================================================================================
Test Suite Results: 22 passed, 0 failed, 22 total
================================================================================
```

### Test Case Specifications:
1. **Unicode Canonical Equivalence:** Verify that `"café"` (precomposed NFC) and `"cafe\u{301}"` (decomposed NFD) are recognized as distinct and yield 1 difference hunk.
2. **Line Ending Detection:** Verify that `"a\r\nb\r\n"` vs `"a\nb\n"` yields 2 deletions and 2 additions.
3. **Out-of-Bounds Hunk Protection:** `applyHunk` with invalid or out-of-range line boundaries must safely no-op without crashing or clobbering text.
4. **Stale Hunk Content Rejection:** `applyHunk` must refuse to modify text if line contents at the range have diverged from the hunk's cached lines.
5. **Coordinator Stale Hunk Guard:** User typing immediately followed by a hunk merge must reject the stale hunk and recalculate the diff.
6. **Hover Arrow Race Guard:** Clicks on a repositioning action button during active edits must be rejected.
7. **Cursor Placement Navigation:** Invoking `jumpToNextHunk()` on CRLF and emoji text (`"😀😀\r\nsame\r\nold\r\n"`) places the cursor precisely at the character offset of the difference.
8. **Myers Diff Mathematical Correctness:** Verified against 300 randomized inputs comparing results against Swift's `Collection.difference(from:)`.
9. **Word Diff Surrogate Pair Integrity:** Intra-line diffing never splits a multi-byte emoji surrogate pair and merges contiguous modifications.
10. **Exotic Whitespace Row Invariant:** Lone CR `\r` and Unicode line separator `\u{2028}` do not create unaligned visual line wraps in TextKit.
11. **Hunk Copy Undo/Redo:** Merging a hunk registers `"Copy Change to Right"` with `NSUndoManager`, and undo restores the overwritten text.
12. **Clear Both Panes Undo:** Clearing both panes registers `"Clear"` as a single compound undo action, restoring both left and right strings.
13. **Minimal Range Replacement:** Programmatic edits only replace the differing subrange, leaving surrounding text intact.
14. **Keyboard Copy Command Advance:** `copyCurrentHunk(direction:)` executes from caret location without requiring mouse hover and advances to the next change.
15. **Invisible Button Click Swallowing:** Verify `hunkActionButton.isHidden == true` when inactive so it cannot swallow clicks destined for text or gutter.
16. **Background Diff Debounce:** Multiple keystrokes debounce diff calculation to 100ms on a background queue; stale thread completions are discarded.
17. **No Full Relayout on Identical Diff:** Recalculating an unchanged diff performs zero text storage attribute mutations (`counter.edits == 0`).
18. **Unrelated 10,000-Line Performance:** Diffing two completely different 10,000-line files completes in under 3.0 seconds via `costBudget` capping.
19. **Massive Single-Line Word Diff:** Word diffing a 20,000-token single line completes in under 1.0 second.
20. **Scattered Edits 20,000-Line Performance:** 20,000 lines with periodic modifications diff in under 2.0 seconds.
21. **File Loader Security & Encodings:** Confirms binary rejection, BOM preservation, Latin-1 fallback, and size limit enforcement.
22. **Empty Initial State:** Application launches with empty text, `Ready for input` status capsule, and clean undo stack.

---

## 15. Reproduction Guide for Implementing AI

To reproduce this system from scratch:
1. **Initialize Package:** Create a macOS 12+ Swift package targeting an executable `Diffr`.
2. **Build Theme Tokens:** Implement `DiffTheme.swift` with exact light/dark dynamic colors, `22.0pt` line height, and hatched spacer drawer.
3. **Implement Diff Engine:** Build `LiteralText`, `TextInterner`, `MyersDiff` bisection with `costBudget`, and `WordDiffEngine`.
4. **Implement Text Layout:** Subclass `NSLayoutManager` as `InvisibilityLayoutManager` to draw word highlight pills, suppress control characters, and draw invisible symbols. Subclass `NSTextView` as `DiffTextView` to paint row background fills.
5. **Construct Editors:** Build `DiffEditorView` with `LineNumberRulerView` (gutter), `DiffActionMarginView` (32pt seam margin), and `HunkActionButton`. Set `isAutomaticQuoteSubstitutionEnabled = false` and all smart substitutions off.
6. **Implement Coordinators:**
   - `DiffCoordinator`: Manages paragraph spacing calculations, debounced background diffing, and hunk copy operations.
   - `DiffScrollCoordinator`: Synchronizes scroll views using `documentOffsetY`.
7. **Assemble UI:** Create `MainWindowController` with frosted 48pt `NSVisualEffectView`, `ModernPillButton` controls, and `ModernStatusCapsuleView`.
8. **Verify:** Run the full 22-test suite via `swift test`.
