---
type: design-prd
repos: []
---

# Product Requirements: Visual Diff Editor

## Problem to Solve

Developers and writers frequently need to compare, inspect, and reconcile two text documents or code snippets side-by-side. Existing solutions are either heavy terminal-only diffs that lack visual context and live in-place editing, or cumbersome IDE tools requiring complex project setup. Users need a fast, native macOS desktop application where they can paste or edit text in two synchronized panes, visually inspect aligned additions and deletions using industry-standard color highlights, instantly merge changes left-to-right or right-to-left with gutter action buttons, search with find and replace, and toggle invisible whitespace characters.

## Success

1. **Responsiveness & Fluidity**: Instantaneous live diff recalculation during text editing (<16ms for typical files up to several thousand lines) and 60fps smooth synchronized bidirectional scrolling (vertical and horizontal) with zero jitter or cursor jumping.
2. **Reconciliation Accuracy**: 100% accurate hunk alignment and one-click hunk copying between left and right panes, with immediate visual update to diff highlights and change statistics (showing "files identical" when all differences are resolved).
3. **Usability & Clarity**: Clean visual diff indicators conforming to industry standard light/dark mode tints, dim non-intrusive invisible character rendering, and seamless find & replace integration.

## Proposed Solution

A lightweight, high-performance native macOS desktop application providing a side-by-side visual diff editor. Two editable plaintext panes (Left: Original, Right: Modified) are separated by an interactive middle separator gutter. Changes are calculated via native Myers diffing with 100ms debouncing. Users can merge entire files with top gutter arrows or merge individual hunks via hover-activated arrows, with synchronized bidirectional scrolling, find & replace, change stats, and a dim invisible characters toggle.

See the interactive UI mockup at [mockup-visual-diff.html](file:///Users/citizen/dev/diffr/.agents/artifacts/visual-diff/mockup-visual-diff.html).

## Solution Details

### 1. Dual Plaintext Panes with Debounced Live Diffing (~100ms)
- Both left and right panes are fully editable plaintext editors using monospace typography and line numbers.
- As the user types, pastes, or edits in either pane, diff calculations, syntax highlights, gutter action buttons, and statistics update automatically with a 100ms debounce.
- Editing in one pane preserves cursor position and scroll state in both panes without layout flicker or typing stutters.

### 2. Middle Gutter Provides Both Bulk Copy and Per-Change Hover Copy
- **Bulk Copy (Top of Gutter)**: The header of the middle separator gutter contains two global action buttons:
  - `➔` / `Copy All Right`: Copies the entire left document into the right editor.
  - `⬅` / `Copy All Left`: Copies the entire right document into the left editor.
- **Per-Change Copy (On Hover)**:
  - For each difference hunk, action arrows appear when the user hovers over the changed lines in either pane or over the gutter next to the hunk.
  - Clicking `➔` copies only that specific diff hunk from Left to Right, replacing or inserting the lines at the matching location.
  - Clicking `⬅` copies only that specific diff hunk from Right to Left, replacing or inserting the lines at the matching location.
  - Once merged, the hunk turns neutral/unmodified, the stats update, and when all changes are resolved, the stats badge displays "files identical".

### 3. GitHub-Style Split Diff Alignment with Spacer Rows
- Adopts GitHub's split diff presentation: lines from both sides are grouped into aligned rows.
- When lines are present on one side but absent on the other (pure additions or deletions), the opposite pane displays an empty spacer row with subtle diagonal hash marks or neutral background and no line number.
- Corresponding and unchanged lines stay horizontally aligned across both panes, regardless of how many insertions or deletions occur earlier in the document.

### 4. Bidirectional Synchronous Scrolling
- Scrolling vertically on either the Left pane, Right pane, or Middle Gutter moves all three in synchronized lockstep.
- Scrolling horizontally in either pane mirrors horizontal panning in the other pane.
- Scroll events use a guarded synchronization coordinator to prevent feedback loops and scroll stutter.

### 5. Native Per-Pane Find and Replace Bars
- Each text pane leverages AppKit's native text finder architecture (`NSTextFinder` / `usesFindBar = true`).
- Pressing `Cmd+F` or `Cmd+Option+F` (or using the Edit > Find menu) activates the native search/replace bar attached directly to the currently focused pane.
- Allows targeted text search and replacement specifically within the active editor without interfering with the other pane.

### 6. Middle Separator Change Statistics and Invisibles Toggle
- **Change Statistics Badge**:
  - Displays `"X changes found (+A, -D)"` when differences exist between the documents.
  - Displays `"files identical"` with a green indicator when all differences are reconciled or both panes have identical text.
- **Show Invisibles Checkbox**:
  - Checkbox located directly in the middle separator header.
  - Toggling this option instantly reveals or hides non-printable whitespace characters across both text panes.
  - Space characters render as dim middle dots (`·`).
  - Tab characters render as dim horizontal arrows (`→`).
  - Newlines/line-breaks render as dim carriage-return arrows (`↵`).
  - Rendered at ~25–30% opacity (`NSColor.tertiaryLabelColor`) so they remain visible for inspecting trailing spaces/tabs without hindering code readability.

### 7. Industry-Standard Color Theming Across Light and Dark Modes
- **Additions (Right Pane)**:
  - Light mode: Soft green tint `rgba(46, 160, 67, 0.15)` (#E6FFEC) with green left border.
  - Dark mode: Subtle deep green tint `rgba(46, 160, 67, 0.22)` (#13331C) with green left border.
- **Deletions (Left Pane)**:
  - Light mode: Soft red/pink tint `rgba(248, 81, 73, 0.15)` (#FFEBE9) with red left border.
  - Dark mode: Subtle deep red tint `rgba(248, 81, 73, 0.22)` (#3D1418) with red left border.
- **Identical / Unmodified Lines**:
  - Standard system text background and text colors.

## Alternative Solutions Considered

- **Unified Top Find Bar**: A single shared find bar spanning above both panes. Considered, but rejected in favor of native per-pane find bars (Option B) to preserve standard macOS `NSTextView` search behavior and allow independent, focused searching per pane.
- **Direct 1:1 Coordinate Scrolling Without Spacers**: Scrolling coordinates are mirrored directly without injecting spacer gaps. Rejected because any multiline insertion causes all subsequent unchanged lines to become vertically misaligned, breaking the side-by-side comparison experience.
- **Synchronous Keystroke Diffing**: Calculating diffs synchronously on every raw character input. Rejected in favor of 100ms debounced diffing to prevent typing latency on longer documents.

## Scope

### In Scope
- Conversion of application from accessory menu-bar to regular desktop application with main window.
- Dual-pane editable plaintext editors with line numbers and monospace font.
- GitHub-style split diff row alignment with spacer rows.
- Synchronized bidirectional scrolling (vertical and horizontal).
- Middle separator gutter with change statistics badge ("files identical"), "Show Invisibles" checkbox, global copy-all buttons, and per-change hover copy arrows.
- Native per-pane find & replace bars.
- Dim non-printable character rendering (spaces, tabs, newlines).
- Industry-standard light and dark mode diff color palettes.

### Out of Scope (Deferred to Future Releases)
- Three-way merge resolution.
- Syntax highlighting for programming languages.
- Direct Git repository or branch diff integrations.

## Deferred to TDD

- App activation policy transition (`.regular`) and `MainWindowController` initialization.
- Line diffing algorithm and data structures (`DiffModel`, `DiffHunk`, `DiffLine`) leveraging Swift's `Collection.difference(from:)`.
- AppKit scroll coordination architecture (`ScrollCoordinator` with `postsBoundsChangedNotifications`).
- TextKit layout manager subclass (`InvisibilityLayoutManager`) overriding `drawGlyphs`.
- Spacer row rendering mechanism in `NSTextView` / layout system.
- Middle gutter custom view (`DiffGutterView`) tracking line geometry and hosting action buttons.
