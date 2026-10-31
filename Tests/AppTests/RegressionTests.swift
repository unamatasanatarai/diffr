import AppKit

/// Regression tests for defects found in the adversarial review.
public enum RegressionTests {
    private static func makeEditors(inWindow: Bool = false) -> (DiffEditorView, DiffEditorView, DiffCoordinator, NSWindow?) {
        let left = DiffEditorView(side: .left)
        let right = DiffEditorView(side: .right)
        var window: NSWindow?
        if inWindow {
            // A window provides the undo manager NSTextView registers with.
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
            win.isReleasedWhenClosed = false
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
            left.frame = NSRect(x: 0, y: 0, width: 450, height: 600)
            right.frame = NSRect(x: 450, y: 0, width: 450, height: 600)
            container.addSubview(left)
            container.addSubview(right)
            win.contentView = container
            window = win
        } else {
            left.frame = NSRect(x: 0, y: 0, width: 450, height: 600)
            right.frame = NSRect(x: 0, y: 0, width: 450, height: 600)
        }
        let coord = DiffCoordinator(leftEditor: left, rightEditor: right)
        return (left, right, coord, window)
    }

    private static func time(_ block: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        return CFAbsoluteTimeGetCurrent() - start
    }

    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        // MARK: Correctness

        testRunner("Canonically-equivalent but byte-different text is NOT reported identical") {
            let nfc = "café"            // U+00E9
            let nfd = "cafe\u{301}"      // e + combining acute
            let result = DiffEngine.computeDiff(leftText: "x\n" + nfc, rightText: "x\n" + nfd)
            try expect(!result.isIdentical, "NFC vs NFD must be a visible difference")
            try expect(result.hunks.count == 1)
        }

        testRunner("CRLF vs LF line endings are detected as changes") {
            let result = DiffEngine.computeDiff(leftText: "a\r\nb\r\n", rightText: "a\nb\n")
            try expect(!result.isIdentical)
            try expect(result.deletionsCount == 2 && result.additionsCount == 2)
        }

        testRunner("applyHunk with an out-of-range hunk neither crashes nor clobbers either side") {
            let left = "one\ntwo"
            let right = "uno"
            let bogus = DiffHunk(id: 0, leftLineRange: 0..<1, rightLineRange: 0..<5, alignedRowRange: 0..<5,
                                 leftLines: ["one"], rightLines: ["uno", "a", "b", "c", "d"], kind: .modification)
            let outcomeLR = DiffEngine.applyHunk(bogus, leftText: left, rightText: right, direction: .leftToRight)
            try expect(outcomeLR.newLeftText == left && outcomeLR.newRightText == right, "Must be a no-op")
            let outcomeRL = DiffEngine.applyHunk(bogus, leftText: left, rightText: right, direction: .rightToLeft)
            try expect(outcomeRL.newLeftText == left && outcomeRL.newRightText == right, "Must be a no-op")
        }

        testRunner("applyHunk refuses a hunk whose lines no longer match the text") {
            let hunk = DiffEngine.computeDiff(leftText: "a\nb\nc", rightText: "a\nB\nc").hunks[0]
            let outcome = DiffEngine.applyHunk(hunk, leftText: "a\nEDITED\nc", rightText: "a\nB\nc", direction: .leftToRight)
            try expect(outcome.newRightText == "a\nB\nc", "Stale hunk must not overwrite the right pane")
        }

        testRunner("Coordinator ignores a stale hunk after the text changed") {
            let (left, right, coord, _) = makeEditors()
            coord.setInitialTexts(left: "a\nb\nc\n", right: "a\nX\nc\n")
            let staleHunk = coord.diffResult.hunks[0]
            right.text = "a\nY\nc\n"          // user edits; diff not yet recalculated
            coord.copyHunk(staleHunk, direction: .leftToRight)
            try expect(right.text == "a\nY\nc\n", "Stale hunk must not be applied, got \(right.text.debugDescription)")
            try expect(left.text == "a\nb\nc\n")
        }

        testRunner("Hover-arrow click right after typing does not apply a mispositioned change") {
            let (left, right, coord, _) = makeEditors()
            coord.setInitialTexts(left: "a\nb\n", right: "a\nB\n")
            left.textView.insertText("Z", replacementRange: NSRange(location: 0, length: 0))
            try expect(!coord.isDiffCurrent)
            left.onMoveHunk?(0)
            try expect(right.text == "a\nB\n", "Click on stale arrow must be ignored")
            try expect(coord.isDiffCurrent, "Diff must be refreshed instead")
        }

        testRunner("Next Change places the cursor correctly in CRLF and emoji text") {
            let (left, right, coord, _) = makeEditors()
            let leftText = "😀😀\r\nsame\r\nold\r\n"
            let rightText = "😀😀\r\nsame\r\nnew\r\n"
            coord.setInitialTexts(left: leftText, right: rightText)
            coord.jumpToNextHunk()
            let expected = ("😀😀\r\nsame\r\n" as NSString).length
            try expect(left.textView.selectedRange().location == expected, "got \(left.textView.selectedRange().location), want \(expected)")
            try expect(right.textView.selectedRange().location == expected)
        }

        testRunner("Myers diff is minimal and consistent with Swift's difference on random inputs") {
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<300 {
                let a = (0..<Int.random(in: 0...40, using: &rng)).map { _ in Int.random(in: 0...5, using: &rng) }
                let b = (0..<Int.random(in: 0...40, using: &rng)).map { _ in Int.random(in: 0...5, using: &rng) }
                let (deleted, inserted) = MyersDiff.diff(a, b)
                let kept = zip(a, deleted).filter { !$0.1 }.map { $0.0 }
                let keptB = zip(b, inserted).filter { !$0.1 }.map { $0.0 }
                try expect(kept == keptB, "Kept elements must form a common subsequence: \(a) vs \(b)")
                let ours = deleted.filter { $0 }.count + inserted.filter { $0 }.count
                let reference = b.difference(from: a).count
                try expect(ours == reference, "Edit count \(ours) != minimal \(reference) for \(a) vs \(b)")
            }
        }

        testRunner("Word diff never splits a surrogate pair and merges adjacent changes") {
            let tokens = WordDiffEngine.tokenize(line: "a😀b")
            try expect(tokens.contains { $0.text == "😀" && $0.range.length == 2 }, "Emoji must be one 2-unit token: \(tokens)")
            let diff = WordDiffEngine.computeWordDiff(leftLine: "let x = old value;", rightLine: "let x = new thing;")
            try expect(diff.leftHighlights.count == 1, "Adjacent changed words should merge into one span: \(diff.leftHighlights)")
        }

        testRunner("Lone CR and U+2028 inside a line do not break row alignment") {
            let (left, _, coord, _) = makeEditors()
            let leftText = "one\ntwo\rtwo-b\nthree\u{2028}three-b\nfour"
            let rightText = "zero\none\ntwo\rtwo-b\nthree\u{2028}three-b\nfour"
            coord.setInitialTexts(left: leftText, right: rightText)
            let lm = left.layoutManager
            lm.ensureLayout(for: left.textView.textContainer!)
            let ranges = DiffEngine.lineRanges(in: left.textStorage.mutableString)
            // Left line i sits on aligned row i + 1 (one leading spacer row for the added "zero").
            // Measured in view coordinates, i.e. where the user sees it relative to gutter and other pane.
            for (i, range) in ranges.enumerated() {
                let glyph = lm.glyphIndexForCharacter(at: range.location)
                let fragment = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let actualBottom = fragment.maxY + left.textView.textContainerOrigin.y
                let expectedBottom = DiffTheme.editorTextInsetY + CGFloat(i + 2) * DiffTheme.editorLineHeight
                try expect(abs(actualBottom - expectedBottom) < 0.5, "Line \(i) bottom \(actualBottom) != \(expectedBottom)")
            }
            var fragments = 0
            lm.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: lm.numberOfGlyphs)) { _, _, _, _, _ in fragments += 1 }
            try expect(fragments == ranges.count, "Expected \(ranges.count) visual lines, got \(fragments)")
        }

        // MARK: Undo safety

        testRunner("Copying a change is undoable and redoable") {
            let (_, right, coord, window) = makeEditors(inWindow: true)
            coord.setInitialTexts(left: "a\nb\nc\n", right: "a\nX\nc\n")
            window?.undoManager?.removeAllActions()
            coord.copyHunk(coord.diffResult.hunks[0], direction: .leftToRight)
            try expect(right.text == "a\nb\nc\n")
            try expect(coord.diffResult.isIdentical)
            let undo = try unwrap(window?.undoManager)
            try expect(undo.canUndo, "Hunk copy must register undo")
            try expect(undo.undoActionName == "Copy Change to Right", "Action name: \(undo.undoActionName)")
            undo.undo()
            try expect(right.text == "a\nX\nc\n", "Undo must restore the overwritten text, got \(right.text.debugDescription)")
            undo.redo()
            try expect(right.text == "a\nb\nc\n")
            window?.close()
        }

        testRunner("Clear is a single undoable step restoring both panes") {
            let (left, right, coord, window) = makeEditors(inWindow: true)
            coord.setInitialTexts(left: "left text", right: "right text")
            window?.undoManager?.removeAllActions()
            coord.clearAll()
            try expect(left.text.isEmpty && right.text.isEmpty)
            window?.undoManager?.undo()
            try expect(left.text == "left text" && right.text == "right text", "Got \(left.text) / \(right.text)")
            window?.close()
        }

        testRunner("Programmatic replace edits only the differing range and keeps surrogate pairs intact") {
            let (left, _, _, _) = makeEditors()
            left.text = "a😀b\nunchanged tail"
            left.replaceText(with: "a😃b\nunchanged tail", actionName: nil)
            try expect(left.text == "a😃b\nunchanged tail", "Got \(left.text.debugDescription)")
        }

        // MARK: Keyboard / UI behaviour

        testRunner("Copy Change command works from the cursor without hovering and advances") {
            let (left, right, coord, _) = makeEditors()
            coord.setInitialTexts(left: "a\n1\nb\n2\nc", right: "a\nI\nb\nII\nc")
            left.textView.setSelectedRange(NSRange(location: 2, length: 0)) // on line "1"
            coord.copyCurrentHunk(direction: .leftToRight, focusedEditor: left)
            try expect(right.text == "a\n1\nb\nII\nc", "Got \(right.text.debugDescription)")
            try expect(coord.activeHunkIndex == coord.diffResult.hunks.first?.id, "Should advance to the remaining change")
        }

        testRunner("Invisible hunk arrow is hidden so it cannot swallow clicks") {
            let (left, _, coord, _) = makeEditors()
            coord.setInitialTexts(left: "a\nb\n", right: "a\nc\n")
            try expect(left.hunkActionButton.isHidden, "No hover, no active hunk: arrow must be hidden")
            left.onHoverRow?(1)
            try expect(!left.hunkActionButton.isHidden)
            left.onHoverRow?(nil)
            try expect(left.hunkActionButton.isHidden)
        }

        testRunner("Diff is computed in the background after typing and stale results are discarded") {
            let (left, _, coord, _) = makeEditors()
            coord.setInitialTexts(left: "a\nb\n", right: "a\nb\n")
            left.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
            left.textView.insertText("y", replacementRange: NSRange(location: 0, length: 0))
            try expect(!coord.isDiffCurrent)
            let deadline = Date().addingTimeInterval(3)
            while !coord.isDiffCurrent && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }
            try expect(coord.isDiffCurrent, "Background diff never landed")
            try expect(coord.diffResult.hunks.count == 1)
            try expect(coord.diffResult.hunks[0].leftLines == ["yxa"])
        }

        testRunner("Recalculating an unchanged diff does not touch text attributes (no full relayout)") {
            let (left, _, coord, _) = makeEditors()
            coord.setInitialTexts(left: (0..<200).map { "line \($0)" }.joined(separator: "\n"),
                                  right: (0..<200).map { $0 % 10 == 0 ? "changed \($0)" : "line \($0)" }.joined(separator: "\n"))
            let counter = EditCounter()
            left.textStorage.delegate = counter
            coord.recalculateDiff()
            try expect(counter.edits == 0, "Expected no attribute edits, got \(counter.edits)")
            left.textStorage.delegate = nil
        }

        // MARK: Performance

        testRunner("Two unrelated 10k-line files diff quickly with bounded work") {
            let a = (0..<10_000).map { "left side line \($0)" }.joined(separator: "\n")
            let b = (0..<10_000).map { "completely different \($0 * 7919)" }.joined(separator: "\n")
            var result = DiffResult.empty
            let elapsed = time { result = DiffEngine.computeDiff(leftText: a, rightText: b) }
            try expect(elapsed < 3.0, "Took \(elapsed)s")
            try expect(result.deletionsCount == 10_000 && result.additionsCount == 10_000)
        }

        testRunner("A huge single-line change does not stall the word diff") {
            let l = (0..<20_000).map { "w\($0)" }.joined(separator: " ")
            let r = (0..<20_000).map { "x\($0)" }.joined(separator: " ")
            let elapsed = time { _ = DiffEngine.computeDiff(leftText: l, rightText: r) }
            try expect(elapsed < 1.0, "Took \(elapsed)s")
        }

        testRunner("Similar 20k-line files with scattered edits produce an exact, fast diff") {
            let base = (0..<20_000).map { "row \($0) payload" }
            var modified = base
            for i in stride(from: 0, to: base.count, by: 97) { modified[i] = "edited \(i)" }
            var result = DiffResult.empty
            let elapsed = time {
                result = DiffEngine.computeDiff(leftText: base.joined(separator: "\n"), rightText: modified.joined(separator: "\n"))
            }
            try expect(elapsed < 2.0, "Took \(elapsed)s")
            try expect(result.hunks.count == (base.count + 96) / 97, "Got \(result.hunks.count) hunks")
        }

        // MARK: File loading

        testRunner("File loader refuses binary, keeps BOMs, falls back to legacy encodings, enforces size") {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diffr-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let binary = dir.appendingPathComponent("bin")
            try Data([0x7F, 0x45, 0x4C, 0x46, 0x00, 0x01]).write(to: binary)
            var binaryError: TextFileLoadError?
            do { _ = try TextFileLoader.load(url: binary) } catch let e as TextFileLoadError { binaryError = e }
            try expect(binaryError == .binary)

            let bom = dir.appendingPathComponent("bom.txt")
            try Data([0xEF, 0xBB, 0xBF] + Array("hi".utf8)).write(to: bom)
            try expect(try TextFileLoader.load(url: bom).unicodeScalars.first == "\u{FEFF}", "BOM must be preserved")

            let latin1 = dir.appendingPathComponent("latin1.txt")
            try Data([0x63, 0x61, 0x66, 0xE9]).write(to: latin1)
            try expect(try TextFileLoader.load(url: latin1) == "café")

            let utf16 = dir.appendingPathComponent("utf16.txt")
            try "héllo\n".data(using: .utf16)!.write(to: utf16)
            try expect(try TextFileLoader.load(url: utf16) == "héllo\n")

            var sizeError: TextFileLoadError?
            do { _ = try TextFileLoader.load(url: bom, maxSize: 2) } catch let e as TextFileLoadError { sizeError = e }
            if case .tooLarge = sizeError {} else { try expect(false, "Expected tooLarge, got \(String(describing: sizeError))") }

            var dirError: TextFileLoadError?
            do { _ = try TextFileLoader.load(url: dir) } catch let e as TextFileLoadError { dirError = e }
            try expect(dirError == .notARegularFile)
        }
    }

    private static func unwrap<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws -> T {
        guard let value = value else { throw TestFailure(message: "Unexpected nil", location: "\(file):\(line)") }
        return value
    }
}

private final class EditCounter: NSObject, NSTextStorageDelegate {
    var edits = 0
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        edits += 1
    }
}
