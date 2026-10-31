import Foundation

/// Hashable wrapper comparing text by its exact UTF-8 bytes.
///
/// Swift's `String ==` uses Unicode canonical equivalence ("é" == "e\u{301}"),
/// which would hide exactly the kind of invisible difference a diff tool must reveal.
struct LiteralText: Hashable {
    let value: Substring

    static func == (lhs: LiteralText, rhs: LiteralText) -> Bool {
        return lhs.value.utf8.elementsEqual(rhs.value.utf8)
    }

    func hash(into hasher: inout Hasher) {
        let hashed: Void? = value.utf8.withContiguousStorageIfAvailable { buffer in
            hasher.combine(bytes: UnsafeRawBufferPointer(buffer))
        }
        if hashed == nil {
            Array(value.utf8).withUnsafeBytes { hasher.combine(bytes: $0) }
        }
    }
}

/// Maps texts to dense integer ids so the diff compares ints instead of strings.
struct TextInterner {
    private var table: [LiteralText: Int] = [:]

    init(capacity: Int) {
        table.reserveCapacity(capacity)
    }

    mutating func id(for text: Substring) -> Int {
        let key = LiteralText(value: text)
        if let existing = table[key] { return existing }
        let newId = table.count
        table[key] = newId
        return newId
    }
}

/// Linear-space Myers diff (bisection / middle snake) with a per-step cost cap.
///
/// When a sub-problem would cost more than `costBudget` comparisons, it is reported as a
/// full replacement instead of searching further. This bounds time and memory for
/// pathological inputs (e.g. two unrelated large files) where the exact answer is
/// "everything changed" anyway.
enum MyersDiff {
    static func diff(_ a: [Int], _ b: [Int], costBudget: Int = 60_000_000) -> (deleted: [Bool], inserted: [Bool]) {
        var deleted = [Bool](repeating: false, count: a.count)
        var inserted = [Bool](repeating: false, count: b.count)

        let vSize = 2 * ((a.count + b.count + 1) / 2) + 4
        var v1 = [Int](repeating: -1, count: vSize)
        var v2 = [Int](repeating: -1, count: vSize)

        a.withUnsafeBufferPointer { aBuf in
            b.withUnsafeBufferPointer { bBuf in
                var stack: [(Int, Int, Int, Int)] = [(0, a.count, 0, b.count)]
                while let (aLo0, aHi0, bLo0, bHi0) = stack.popLast() {
                    var aLo = aLo0, aHi = aHi0, bLo = bLo0, bHi = bHi0

                    while aLo < aHi && bLo < bHi && aBuf[aLo] == bBuf[bLo] { aLo += 1; bLo += 1 }
                    while aLo < aHi && bLo < bHi && aBuf[aHi - 1] == bBuf[bHi - 1] { aHi -= 1; bHi -= 1 }

                    if aLo == aHi {
                        for j in bLo..<bHi { inserted[j] = true }
                        continue
                    }
                    if bLo == bHi {
                        for i in aLo..<aHi { deleted[i] = true }
                        continue
                    }

                    let size = (aHi - aLo) + (bHi - bLo)
                    let dLimit = max(64, costBudget / size)
                    if let (x, y) = bisect(aBuf, aLo, aHi, bBuf, bLo, bHi, &v1, &v2, dLimit),
                       !(x == aLo && y == bLo), !(x == aHi && y == bHi) {
                        stack.append((x, aHi, y, bHi))
                        stack.append((aLo, x, bLo, y))
                    } else {
                        for i in aLo..<aHi { deleted[i] = true }
                        for j in bLo..<bHi { inserted[j] = true }
                    }
                }
            }
        }
        return (deleted, inserted)
    }

    /// Finds a split point on an optimal edit path (after Myers 1986 / diff-match-patch bisect).
    private static func bisect(
        _ a: UnsafeBufferPointer<Int>, _ aLo: Int, _ aHi: Int,
        _ b: UnsafeBufferPointer<Int>, _ bLo: Int, _ bHi: Int,
        _ v1: inout [Int], _ v2: inout [Int],
        _ dLimit: Int
    ) -> (Int, Int)? {
        let n = aHi - aLo
        let m = bHi - bLo
        let maxD = (n + m + 1) / 2
        let vOffset = maxD
        let vLength = 2 * maxD + 2
        for i in 0..<vLength {
            v1[i] = -1
            v2[i] = -1
        }
        v1[vOffset + 1] = 0
        v2[vOffset + 1] = 0

        let delta = n - m
        let front = (delta & 1) != 0
        var k1start = 0, k1end = 0, k2start = 0, k2end = 0

        for d in 0..<maxD {
            if d > dLimit { return nil }

            var k1 = -d + k1start
            while k1 <= d - k1end {
                let k1o = vOffset + k1
                var x1 = (k1 == -d || (k1 != d && v1[k1o - 1] < v1[k1o + 1])) ? v1[k1o + 1] : v1[k1o - 1] + 1
                var y1 = x1 - k1
                while x1 < n && y1 < m && a[aLo + x1] == b[bLo + y1] {
                    x1 += 1
                    y1 += 1
                }
                v1[k1o] = x1
                if x1 > n {
                    k1end += 2
                } else if y1 > m {
                    k1start += 2
                } else if front {
                    let k2o = vOffset + delta - k1
                    if k2o >= 0 && k2o < vLength && v2[k2o] != -1 && x1 >= n - v2[k2o] {
                        return (aLo + x1, bLo + y1)
                    }
                }
                k1 += 2
            }

            var k2 = -d + k2start
            while k2 <= d - k2end {
                let k2o = vOffset + k2
                var x2 = (k2 == -d || (k2 != d && v2[k2o - 1] < v2[k2o + 1])) ? v2[k2o + 1] : v2[k2o - 1] + 1
                var y2 = x2 - k2
                while x2 < n && y2 < m && a[aLo + n - x2 - 1] == b[bLo + m - y2 - 1] {
                    x2 += 1
                    y2 += 1
                }
                v2[k2o] = x2
                if x2 > n {
                    k2end += 2
                } else if y2 > m {
                    k2start += 2
                } else if !front {
                    let k1o = vOffset + delta - k2
                    if k1o >= 0 && k1o < vLength && v1[k1o] != -1 {
                        let x1 = v1[k1o]
                        let y1 = vOffset + x1 - k1o
                        if x1 >= n - x2 {
                            return (aLo + x1, bLo + y1)
                        }
                    }
                }
                k2 += 2
            }
        }
        return nil
    }
}

public final class DiffEngine {
    /// Splits text into lines on "\n" only, keeping a trailing empty line when the text ends with "\n".
    /// "\r" stays part of the line so CRLF vs LF differences are detected.
    public static func splitLines(_ text: String) -> [String] {
        return splitLineSubstrings(text).map { String($0) }
    }

    static func splitLineSubstrings(_ text: String) -> [Substring] {
        if text.isEmpty { return [] }
        var native = text
        native.makeContiguousUTF8()
        return native.utf8
            .split(separator: 0x0A, omittingEmptySubsequences: false)
            .map { Substring($0) }
    }

    /// Reconstructs text from lines
    public static func joinLines(_ lines: [String]) -> String {
        return lines.joined(separator: "\n")
    }

    /// UTF-16 ranges of each line (including its trailing "\n"), using exactly the same
    /// line semantics as `splitLines`, so model rows and editor text always agree.
    public static func lineRanges(in string: NSString) -> [NSRange] {
        let length = string.length
        if length == 0 { return [] }

        var ranges: [NSRange] = []
        let buffer = UnsafeMutablePointer<unichar>.allocate(capacity: length)
        defer { buffer.deallocate() }
        string.getCharacters(buffer, range: NSRange(location: 0, length: length))

        var start = 0
        for i in 0..<length where buffer[i] == 0x0A {
            ranges.append(NSRange(location: start, length: i + 1 - start))
            start = i + 1
        }
        ranges.append(NSRange(location: start, length: length - start))
        return ranges
    }

    /// Byte-exact comparison of two line arrays (no Unicode normalization).
    static func literallyEqual<S: StringProtocol>(_ lhs: [S], _ rhs: [S]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (l, r) in zip(lhs, rhs) where !l.utf8.elementsEqual(r.utf8) {
            return false
        }
        return true
    }

    /// Computes full two-pass diff between left and right texts
    public static func computeDiff(
        leftText: String,
        rightText: String,
        includeWordDiff: Bool = true
    ) -> DiffResult {
        let leftSubs = splitLineSubstrings(leftText)
        let rightSubs = splitLineSubstrings(rightText)

        if leftText.utf8.elementsEqual(rightText.utf8) {
            var alignedRows: [AlignedDiffRow] = []
            alignedRows.reserveCapacity(leftSubs.count)
            for (idx, sub) in leftSubs.enumerated() {
                let line = String(sub)
                alignedRows.append(
                    AlignedDiffRow(
                        leftLineNumber: idx + 1,
                        leftText: line,
                        leftKind: .unchanged,
                        rightLineNumber: idx + 1,
                        rightText: line,
                        rightKind: .unchanged,
                        hunkIndex: nil
                    )
                )
            }
            return DiffResult(hunks: [], alignedRows: alignedRows, additionsCount: 0, deletionsCount: 0)
        }

        var interner = TextInterner(capacity: leftSubs.count + rightSubs.count)
        let leftIds = leftSubs.map { interner.id(for: $0) }
        let rightIds = rightSubs.map { interner.id(for: $0) }
        let (removed, inserted) = MyersDiff.diff(leftIds, rightIds)

        let leftLines = leftSubs.map { String($0) }
        let rightLines = rightSubs.map { String($0) }

        let leftCommon = (0..<leftLines.count).filter { !removed[$0] }
        let rightCommon = (0..<rightLines.count).filter { !inserted[$0] }

        var hunks: [DiffHunk] = []
        var alignedRows: [AlignedDiffRow] = []
        alignedRows.reserveCapacity(max(leftLines.count, rightLines.count))

        var currentLeft = 0
        var currentRight = 0
        var additionsCount = 0
        var deletionsCount = 0
        var hunkId = 0

        let commonCount = leftCommon.count
        for k in 0...commonCount {
            let nextLeftCommon = (k < commonCount) ? leftCommon[k] : leftLines.count
            let nextRightCommon = (k < commonCount) ? rightCommon[k] : rightLines.count

            let leftDiffCount = nextLeftCommon - currentLeft
            let rightDiffCount = nextRightCommon - currentRight

            if leftDiffCount > 0 || rightDiffCount > 0 {
                let leftRange = currentLeft..<nextLeftCommon
                let rightRange = currentRight..<nextRightCommon

                let hunkKind: HunkKind
                if leftDiffCount > 0 && rightDiffCount > 0 {
                    hunkKind = .modification
                } else if leftDiffCount > 0 {
                    hunkKind = .deletion
                } else {
                    hunkKind = .addition
                }

                deletionsCount += leftDiffCount
                additionsCount += rightDiffCount

                let startRow = alignedRows.count
                let maxDiffRows = max(leftDiffCount, rightDiffCount)
                for i in 0..<maxDiffRows {
                    let hasLeft = i < leftDiffCount
                    let hasRight = i < rightDiffCount

                    let leftText: String? = hasLeft ? leftLines[currentLeft + i] : nil
                    let rightText: String? = hasRight ? rightLines[currentRight + i] : nil

                    var leftWords: [WordHighlightSpan] = []
                    var rightWords: [WordHighlightSpan] = []

                    if includeWordDiff, hunkKind == .modification, let lt = leftText, let rt = rightText {
                        let wordDiff = WordDiffEngine.computeWordDiff(leftLine: lt, rightLine: rt)
                        leftWords = wordDiff.leftHighlights
                        rightWords = wordDiff.rightHighlights
                    }

                    alignedRows.append(
                        AlignedDiffRow(
                            leftLineNumber: hasLeft ? currentLeft + i + 1 : nil,
                            leftText: leftText,
                            leftKind: hasLeft ? .deletion : .spacer,
                            leftWordHighlights: leftWords,
                            rightLineNumber: hasRight ? currentRight + i + 1 : nil,
                            rightText: rightText,
                            rightKind: hasRight ? .addition : .spacer,
                            rightWordHighlights: rightWords,
                            hunkIndex: hunkId
                        )
                    )
                }

                hunks.append(
                    DiffHunk(
                        id: hunkId,
                        leftLineRange: leftRange,
                        rightLineRange: rightRange,
                        alignedRowRange: startRow..<alignedRows.count,
                        leftLines: Array(leftLines[leftRange]),
                        rightLines: Array(rightLines[rightRange]),
                        kind: hunkKind
                    )
                )
                hunkId += 1
            }

            // Append unchanged common line if not at the end
            if k < commonCount {
                alignedRows.append(
                    AlignedDiffRow(
                        leftLineNumber: nextLeftCommon + 1,
                        leftText: leftLines[nextLeftCommon],
                        leftKind: .unchanged,
                        rightLineNumber: nextRightCommon + 1,
                        rightText: rightLines[nextRightCommon],
                        rightKind: .unchanged,
                        hunkIndex: nil
                    )
                )
                currentLeft = nextLeftCommon + 1
                currentRight = nextRightCommon + 1
            }
        }

        return DiffResult(
            hunks: hunks,
            alignedRows: alignedRows,
            additionsCount: additionsCount,
            deletionsCount: deletionsCount
        )
    }

    /// Applies a single hunk copy from source text into target text.
    ///
    /// The hunk is validated against the current texts first: if it no longer matches
    /// (stale diff, concurrent edit), both texts are returned unchanged. Never guesses.
    public static func applyHunk(
        _ hunk: DiffHunk,
        leftText: String,
        rightText: String,
        direction: MergeDirection
    ) -> (newLeftText: String, newRightText: String) {
        var leftLines = splitLines(leftText)
        var rightLines = splitLines(rightText)

        guard hunk.leftLineRange.lowerBound >= 0,
              hunk.leftLineRange.upperBound <= leftLines.count,
              hunk.rightLineRange.lowerBound >= 0,
              hunk.rightLineRange.upperBound <= rightLines.count,
              literallyEqual(Array(leftLines[hunk.leftLineRange]), hunk.leftLines),
              literallyEqual(Array(rightLines[hunk.rightLineRange]), hunk.rightLines) else {
            return (leftText, rightText)
        }

        switch direction {
        case .leftToRight:
            rightLines.replaceSubrange(hunk.rightLineRange, with: hunk.leftLines)
            return (leftText, joinLines(rightLines))

        case .rightToLeft:
            leftLines.replaceSubrange(hunk.leftLineRange, with: hunk.rightLines)
            return (joinLines(leftLines), rightText)
        }
    }
}
