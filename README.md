# Diffr

<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Diffr App Icon" />
</p>

<p align="center">
  <strong>Native, byte-exact visual diffing and surgical two-way merging for macOS.</strong>
</p>

<p align="center">
  A lightweight, zero-dependency side-by-side text editor built with pure Swift and AppKit. Diffr aligns additions, deletions, and intra-line edits in real time across two fully editable panes—letting you navigate, compare, and merge changes with keyboard shortcuts or one-click hover arrows.
</p>

<p align="center">
  <a href="#quick-start"><img src="https://img.shields.io/badge/platform-macOS%2012.0%2B-blue?style=flat-square" alt="macOS 12.0+" /></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/swift-5.7%2B-orange?style=flat-square" alt="Swift 5.7+" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--2.0-green?style=flat-square" alt="License: GPL-2.0" /></a>
  <a href="#testing--quality"><img src="https://img.shields.io/badge/tests-42%20passed-brightgreen?style=flat-square" alt="42 Tests Passed" /></a>
  <a href="#what-makes-it-different"><img src="https://img.shields.io/badge/dependencies-zero-purple?style=flat-square" alt="Zero Dependencies" /></a>
</p>

---

## Why Diffr?

Most diff tools fall into one of two extremes: heavy IDE plugins wrapped inside bloated runtimes that take seconds to launch, or terminal outputs that display changes but cannot be edited interactively. Worse, standard string tools use Unicode canonical equivalence—silently hiding the exact byte differences (like NFC vs. NFD normalization, mixed line endings, or invisible zero-width spaces) that break parsers, compilers, and builds.

Diffr was created to give macOS developers and writers a dedicated, instantaneous comparison workspace:

* **Both Panes Are Live Editors:** Never switch contexts. Edit original and modified texts directly with syntax-free speed and continuous diff recalculation.
* **Byte-Exact Fidelity:** If the bytes on disk differ, Diffr flags them—making invisible encoding traps immediately visible.
* **Non-Destructive Alignment:** Your document buffer remains pristine. Alignment spacers are rendered entirely through dynamic layout spacing, never by injecting phantom placeholder characters into your text.
* **Frictionless Merging:** Every hunk move, pane replacement, or clear action is fully registered with macOS `NSUndoManager` (`⌘Z`), giving you complete confidence while reconciling files.

---

## Key Capabilities

### Live Bi-Directional Editing
Both panes are standard, fully interactive text editors. Paste text, type directly, or drag and drop files onto either pane. As you type, Diffr recalculates diffs asynchronously off the main thread with a 100ms debounce, keeping your interface smooth and responsive.

### Byte-Exact Comparison & Unicode Traps
Standard Swift and Cocoa text equality collapses canonically equivalent characters (e.g., precomposed `é` vs. decomposed `e\u{301}`). Diffr compares exact UTF-8 byte streams, instantly surfacing normalization mismatches, trailing whitespace variations, and Windows CRLF (`\r\n`) versus Unix LF (`\n`) line endings.

### Surgical Hunk Merging
Hover over any difference block to reveal contextual merge arrows:
* Click **➔** in the left margin to copy changes into the modified file.
* Click **⬅** at the center divider to pull changes back into the original file.
* Use keyboard shortcuts (`⌥⌘→` and `⌥⌘←`) to merge changes directly from your cursor position without touching the mouse.

### Intra-Line Word Diffing
Modified rows don't just tell you that a line changed—Diffr's tokenizer isolates individual alphanumeric tokens, punctuation, and whitespace runs, applying subtle highlight pills over the exact words and values that differ within a line.

### Invisible Characters Inspection
Toggle **¶ Invisibles** (`⇧⌘I`) to reveal hidden characters in a dim, non-distracting layer: spaces (`·`), tabs (`→`), line breaks (`↵`), carriage returns (`␍`), non-breaking spaces (`⍽`), and zero-width joiners or byte order marks (`¦`).

### Frictionless Global Operations & Complete Undo
Need to accept all changes at once? Use **Copy All ➔** or **⬅ Copy All** from the frosted toolbar. Need to reset? Hit **Clear**. Every operation—single hunk merges, wholesale copies, and document clears—is grouped into clean, named undo actions (`⌘Z` / `⇧⌘Z`).

---

## How It Works

```text
1. Load Content     ──►  Drop files onto either pane, use File > Open (⌘O / ⌥⌘O),
                         or paste text directly into the empty editor.

2. Review Changes   ──►  Diffr's bounded Myers diff engine aligns rows and highlights
                         line additions (+), deletions (-), and intra-line word edits.

3. Navigate & Inspect──► Jump through hunks sequentially with ⌘] and ⌘[, or toggle
                         ¶ Invisibles (⇧⌘I) to inspect hidden unicode whitespace.

4. Merge Surgically ──►  Push or pull changes hunk-by-hunk using hover arrows (➔ / ⬅),
                         keyboard shortcuts (⌥⌘→ / ⌥⌘←), or toolbar buttons.

5. Export & Finish  ──►  Copy reconciled content out, or continue editing freely with
                         unrestricted multi-level undo/redo (⌘Z / ⇧⌘Z).
```

---

## What Makes It Different

| Feature | Diffr | Conventional Diff Tools |
| :--- | :--- | :--- |
| **Runtime & Dependencies** | **Pure Swift & AppKit (0 dependencies)** | Electron, Java, or web views (hundreds of MBs) |
| **Buffer Integrity** | **Non-destructive layout spacing** | Modifies text buffer with dummy spacer strings |
| **String Comparison** | **Byte-exact UTF-8 comparison** | Unicode normalization hides NFC vs. NFD differences |
| **Line Ending Handling** | **Preserves & highlights `\r\n` vs. `\n`** | Silently strips carriage returns |
| **Left Action Seam** | **Dedicated 32pt text-free margin** | Merge buttons overlap text or shift layout |
| **Scroll Sync** | **Document-relative lockstep alignment** | Find bars and UI elements desynchronize panes |
| **Safety Limits** | **Refuses binary files & inputs > 32 MB** | Freezes UI on minified one-liners or binary files |

---

## Keyboard Shortcuts

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| `⌘O` | **Open Left Pane…** | Choose file for the original pane |
| `⌥⌘O` | **Open Right Pane…** | Choose file for the modified pane |
| `⌘]` | **Next Change** | Jump to the next hunk and position cursors |
| `⌘[` | **Previous Change** | Jump to the previous hunk and position cursors |
| `⌥⌘→` | **Copy Change to Right** | Merge active hunk from Left to Right |
| `⌥⌘←` | **Copy Change to Left** | Merge active hunk from Right to Left |
| `⇧⌘I` | **Show Invisibles** | Toggle display of spaces, tabs, CR/LF, and zero-width glyphs |
| `⌘F` | **Find…** | Open native macOS find bar |
| `⌥⌘F` | **Find and Replace…** | Open native find and replace interface |
| `⌘G` / `⇧⌘G` | **Find Next / Previous** | Cycle through search matches |
| `⌘Z` / `⇧⌘Z` | **Undo / Redo** | Full undo history for all merges, typing, and clears |

---

## Quick Start

### Prerequisites
* macOS 12.0 (Monterey) or later
* Xcode Command Line Tools (`xcode-select --install`)

### Run Locally

Clone the repository and launch the app in one command:

```bash
git clone https://github.com/unamatasanatarai/diffr.git
cd diffr
make run
```

`make run` compiles the native application bundle (`build/Diffr.app`), terminates any prior running instance, and launches the application immediately.

---

## Build & Development

The included `Makefile` provides an automated workflow for development, testing, and distribution packaging:

```bash
# Build the native .app bundle
make build

# Run the test suite
make test

# Build a styled macOS distribution DMG
make dmg

# Terminate running app instances
make kill

# Clean build artifacts
make clean
```

---

## Testing & Quality

Diffr is verified with an automated Swift test suite covering core diff mathematical correctness, TextKit row alignment invariants, encoding security, and adversarial edge cases:

* **Myers Diff Verification:** Validated across randomized inputs against Swift's native difference calculations.
* **Surrogate Pair Safety:** Confirms multi-byte Unicode characters and emojis (`😀`) are never split during word-level tokenization.
* **Row Alignment Integrity:** Proves that lone `\r` and Unicode paragraph separators (`\u{2028}`) do not disrupt visual vertical alignment.
* **Undo/Redo Verification:** Confirms single hunk copies, global replacements, and full pane clears cleanly restore overwritten text.
* **Performance Bounds:** Bounded execution verifies that diffing two unrelated 10,000-line files completes in under 3.0 seconds without stalling the main thread.

Run the test suite directly from your terminal:

```bash
make test
```

---

## License

Diffr is open-source software licensed under the **GNU General Public License v2.0** (`GPL-2.0`). See the [LICENSE](LICENSE) file for complete terms and conditions.
