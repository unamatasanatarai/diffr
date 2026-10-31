import Foundation

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

    /// UTF-16 units of `string`, copied in one bulk call.
    public static func utf16Units(of string: NSString) -> [UInt16] {
        let length = string.length
        guard length > 0 else { return [] }
        return [UInt16](unsafeUninitializedCapacity: length) { buffer, count in
            string.getCharacters(buffer.baseAddress!, range: NSRange(location: 0, length: length))
            count = length
        }
    }

    /// Native, contiguous UTF-8 Swift string with the contents of `string` (lone surrogates
    /// become U+FFFD, exactly as Swift's own bridging would do).
    public static func nativeString(from string: NSString) -> String {
        return nativeString(fromUTF16: utf16Units(of: string))
    }

    public static func nativeString(fromUTF16 units: [UInt16]) -> String {
        return units.withUnsafeBufferPointer { TextBuffers.string(fromUTF16: $0) }
    }

    /// Number of lines with the same semantics as `lineRanges(in:)`, without allocating per line.
    public static func lineCount(in string: NSString) -> Int {
        let length = string.length
        if length == 0 { return 0 }
        let chunk = 16_384
        var buffer = [unichar](repeating: 0, count: chunk)
        var count = 1
        var location = 0
        while location < length {
            let n = min(chunk, length - location)
            buffer.withUnsafeMutableBufferPointer { buf in
                string.getCharacters(buf.baseAddress!, range: NSRange(location: location, length: n))
                for i in 0..<n where buf[i] == 0x0A { count += 1 }
            }
            location += n
        }
        return count
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
        // Native contiguous UTF-8 (a no-op for strings that already are), then work on raw bytes.
        var left = leftText
        var right = rightText
        left.makeContiguousUTF8()
        right.makeContiguousUTF8()
        return left.withUTF8 { l in
            right.withUTF8 { r in
                computeDiff(left: l, right: r, includeWordDiff: includeWordDiff)
            }
        }
    }

    private static func computeDiff(
        left lb: UnsafeBufferPointer<UInt8>,
        right rb: UnsafeBufferPointer<UInt8>,
        includeWordDiff: Bool
    ) -> DiffResult {
        let leftLines = TextBuffers.lineRanges(utf8: lb)
        let rightLines = TextBuffers.lineRanges(utf8: rb)
        let leftMaxColumns = TextBuffers.maxColumns(utf8: lb)
        let rightMaxColumns = TextBuffers.maxColumns(utf8: rb)

        func string(_ buffer: UnsafeBufferPointer<UInt8>, _ range: Range<Int>) -> String {
            return String(decoding: UnsafeBufferPointer(rebasing: buffer[range]), as: UTF8.self)
        }

        // Byte equality, never `String ==`: canonical equivalence ("é" == "e\u{301}") would hide
        // exactly the kind of invisible difference a diff tool must reveal.
        if lb.count == rb.count && (lb.count == 0 || memcmp(lb.baseAddress!, rb.baseAddress!, lb.count) == 0) {
            var alignedRows: [AlignedDiffRow] = []
            alignedRows.reserveCapacity(leftLines.count)
            for idx in leftLines.indices {
                alignedRows.append(
                    AlignedDiffRow(
                        leftLineNumber: idx + 1,
                        leftKind: .unchanged,
                        rightLineNumber: idx + 1,
                        rightKind: .unchanged,
                        hunkIndex: nil
                    )
                )
            }
            var result = DiffResult(hunks: [], alignedRows: alignedRows, additionsCount: 0, deletionsCount: 0)
            result.leftMaxColumns = leftMaxColumns
            result.rightMaxColumns = rightMaxColumns
            return result
        }

        // Intern lines to dense ids so Myers compares ints, not strings.
        var interner = ByteInterner(capacity: leftLines.count + rightLines.count)
        let leftBase = lb.baseAddress.map { UnsafeRawPointer($0) }
        let rightBase = rb.baseAddress.map { UnsafeRawPointer($0) }
        let leftIds = leftLines.map { interner.id(for: leftBase?.advanced(by: $0.lowerBound), count: $0.count) }
        let rightIds = rightLines.map { interner.id(for: rightBase?.advanced(by: $0.lowerBound), count: $0.count) }
        let (removed, inserted) = MyersDiff.diff(leftIds, rightIds)

        var hunks: [DiffHunk] = []
        var alignedRows: [AlignedDiffRow] = []
        alignedRows.reserveCapacity(max(leftLines.count, rightLines.count))
        /// (row, left line, right line) pairs that need intra-line highlighting.
        var wordDiffJobs: [(row: Int, left: Int, right: Int)] = []

        var additionsCount = 0
        var deletionsCount = 0
        var i = 0
        var j = 0
        let n = leftLines.count
        let m = rightLines.count

        while i < n || j < m {
            if i < n && j < m && !removed[i] && !inserted[j] {
                alignedRows.append(
                    AlignedDiffRow(
                        leftLineNumber: i + 1,
                        leftKind: .unchanged,
                        rightLineNumber: j + 1,
                        rightKind: .unchanged,
                        hunkIndex: nil
                    )
                )
                i += 1
                j += 1
                continue
            }

            // A hunk: every removed line on the left and inserted line on the right up to the next common line.
            let leftStart = i
            let rightStart = j
            while i < n && removed[i] { i += 1 }
            while j < m && inserted[j] { j += 1 }
            let leftDiffCount = i - leftStart
            let rightDiffCount = j - rightStart
            // Myers marks equally many common lines on both sides, so a step always makes progress.
            guard leftDiffCount + rightDiffCount > 0 else {
                assertionFailure("Inconsistent line diff")
                break
            }

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

            let hunkId = hunks.count
            let startRow = alignedRows.count
            for k in 0..<max(leftDiffCount, rightDiffCount) {
                let hasLeft = k < leftDiffCount
                let hasRight = k < rightDiffCount
                if includeWordDiff && hasLeft && hasRight {
                    wordDiffJobs.append((alignedRows.count, leftStart + k, rightStart + k))
                }
                alignedRows.append(
                    AlignedDiffRow(
                        leftLineNumber: hasLeft ? leftStart + k + 1 : nil,
                        leftKind: hasLeft ? .deletion : .spacer,
                        rightLineNumber: hasRight ? rightStart + k + 1 : nil,
                        rightKind: hasRight ? .addition : .spacer,
                        hunkIndex: hunkId
                    )
                )
            }

            let leftRange = leftStart..<i
            let rightRange = rightStart..<j
            hunks.append(
                DiffHunk(
                    id: hunkId,
                    leftLineRange: leftRange,
                    rightLineRange: rightRange,
                    alignedRowRange: startRow..<alignedRows.count,
                    leftLines: leftLines[leftRange].map { string(lb, $0) },
                    rightLines: rightLines[rightRange].map { string(rb, $0) },
                    kind: hunkKind
                )
            )
        }

        if !wordDiffJobs.isEmpty {
            let highlights = computeWordHighlights(
                jobs: wordDiffJobs,
                left: lb, leftLines: leftLines,
                right: rb, rightLines: rightLines
            )
            for (index, job) in wordDiffJobs.enumerated() {
                alignedRows[job.row].leftWordHighlights = highlights[index].0
                alignedRows[job.row].rightWordHighlights = highlights[index].1
            }
        }

        var result = DiffResult(
            hunks: hunks,
            alignedRows: alignedRows,
            additionsCount: additionsCount,
            deletionsCount: deletionsCount
        )
        result.leftMaxColumns = leftMaxColumns
        result.rightMaxColumns = rightMaxColumns
        return result
    }

    /// Word diffs of independent line pairs, spread across all cores.
    private static func computeWordHighlights(
        jobs: [(row: Int, left: Int, right: Int)],
        left lb: UnsafeBufferPointer<UInt8>, leftLines: [Range<Int>],
        right rb: UnsafeBufferPointer<UInt8>, rightLines: [Range<Int>]
    ) -> [([WordHighlightSpan], [WordHighlightSpan])] {
        var output = [([WordHighlightSpan], [WordHighlightSpan])](repeating: ([], []), count: jobs.count)
        let chunkSize = 64
        let chunkCount = (jobs.count + chunkSize - 1) / chunkSize
        // A UTF-8 length over 3x the UTF-16 limit is over the limit for sure; the exact UTF-16
        // check happens in the word diff.
        let byteLimit = WordDiffEngine.maxLineLength * 3
        output.withUnsafeMutableBufferPointer { out in
            let outBase = out.baseAddress!
            let work: (Int) -> Void = { chunk in
                var leftUnits: [UInt16] = []
                var rightUnits: [UInt16] = []
                for index in (chunk * chunkSize)..<min(jobs.count, (chunk + 1) * chunkSize) {
                    let job = jobs[index]
                    let l = UnsafeBufferPointer(rebasing: lb[leftLines[job.left]])
                    let r = UnsafeBufferPointer(rebasing: rb[rightLines[job.right]])
                    if l.count > byteLimit || r.count > byteLimit { continue }
                    // Byte-identical lines (cannot normally pair up, but be safe): no word spans.
                    if l.count == r.count && (l.count == 0 || memcmp(l.baseAddress!, r.baseAddress!, l.count) == 0) { continue }
                    leftUnits.removeAll(keepingCapacity: true)
                    rightUnits.removeAll(keepingCapacity: true)
                    TextBuffers.appendUTF16(fromUTF8: l, to: &leftUnits)
                    TextBuffers.appendUTF16(fromUTF8: r, to: &rightUnits)
                    let spans = leftUnits.withUnsafeBufferPointer { lu in
                        rightUnits.withUnsafeBufferPointer { ru in
                            WordDiffEngine.computeWordDiff(left: lu, right: ru)
                        }
                    }
                    (outBase + index).pointee = spans
                }
            }
            if chunkCount == 1 {
                work(0)
            } else {
                DispatchQueue.concurrentPerform(iterations: chunkCount, execute: work)
            }
        }
        return output
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
