---
type: research-questions
repos: []
flow: prd
---

# Research Questions: Visual Diff

## Key Context Pointers

- `spec.md`
- `Sources/App/Main.swift`
- `Sources/App/AppDelegate.swift`
- `Sources/App/StatusBarController.swift`
- `scripts/config.sh`
- `Package.swift`
- `Tests/AppTests/AppTests.swift`

## Questions

1. In `Sources/App/AppDelegate.swift` and `scripts/config.sh`, how is the current application lifecycle and activation policy configured (e.g., menu-bar accessory vs. regular desktop window app), and what window management or document structures exist today?
2. In `Package.swift`, what external dependencies and target platform versions are defined (macOS 12.0+), and what diffing algorithms (e.g., Myers diff, LCS) or text difference libraries are currently available or viable?
3. In AppKit (`NSScrollView`, `NSClipView`, `NSTextView`), what is the established pattern for bidirectional synchronized scrolling (both vertical and horizontal) between two scroll views while avoiding scroll event feedback loops or rubber-banding jitter?
4. In AppKit text architecture (`NSTextView`, `NSLayoutManager`, `NSTextLayoutManager`), how are non-printable/invisible characters (spaces, tabs, newlines) rendered with editable plaintext support and customizable dim opacity?
5. How does AppKit's native text search system (`NSTextFinder`, `performTextFinderAction`, find bar) integrate across a dual-pane side-by-side editing layout?
6. What are the industry-standard color conventions for diff representations (additions, deletions, line highlights, gutter markers) across macOS light and dark modes?
7. How can a middle separator view in AppKit observe and track line layout and scroll positions from both text panes to position interactive controls (per-chunk copy arrows) and layout widgets (invisible characters toggle)?
