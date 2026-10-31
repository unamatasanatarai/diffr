import Foundation

public final class WordDiffEngine {
    /// Lines longer than this (UTF-16 units) get no intra-line highlighting; the whole line
    /// is still marked as changed. Keeps minified/generated one-liners from stalling the diff.
    static let maxLineLength = 20_000
    /// Upper bound on combined token count for a line pair.
    static let maxTokenCount = 6_000
    /// Comparison budget for a single line pair.
    static let costBudget = 2_000_000

    private enum TokenClass {
        case word, whitespace, other
    }

    private static func classify(_ scalar: Unicode.Scalar) -> TokenClass {
        if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" { return .word }
        if scalar == " " || scalar == "\t" { return .whitespace }
        return .other
    }

    /// Tokenizes a line into alphanumeric words, whitespace runs, and individual symbols.
    /// Ranges are UTF-16 based (NSString/TextKit compatible) and never split a surrogate pair.
    public static func tokenize(line: String) -> [(text: String, range: NSRange)] {
        var tokens: [(text: String, range: NSRange)] = []
        if line.isEmpty { return tokens }

        let scalars = line.unicodeScalars
        var index = scalars.startIndex
        var utf16Offset = 0

        while index < scalars.endIndex {
            let startIndex = index
            let startOffset = utf16Offset
            let tokenClass = classify(scalars[index])
            utf16Offset += scalars[index].utf16.count
            index = scalars.index(after: index)

            if tokenClass != .other {
                while index < scalars.endIndex, classify(scalars[index]) == tokenClass {
                    utf16Offset += scalars[index].utf16.count
                    index = scalars.index(after: index)
                }
            }

            let text = String(scalars[startIndex..<index])
            tokens.append((text: text, range: NSRange(location: startOffset, length: utf16Offset - startOffset)))
        }

        return tokens
    }

    /// A token inside a UTF-16 line buffer.
    struct Token {
        let start: Int
        let length: Int
        let isWhitespace: Bool
    }

    @inline(__always)
    private static func classify(unit: UInt16, buffer: UnsafeBufferPointer<UInt16>, at i: Int) -> (TokenClass, Int) {
        // ASCII fast path: no CharacterSet lookup, no scalar decoding.
        if unit < 0x80 {
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: return (.word, 1)
            case 0x20, 0x09: return (.whitespace, 1)
            default: return (.other, 1)
            }
        }
        if UTF16.isLeadSurrogate(unit), i + 1 < buffer.count, UTF16.isTrailSurrogate(buffer[i + 1]) {
            let value = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(buffer[i + 1]) - 0xDC00)
            let scalar = Unicode.Scalar(value)!
            return (classify(scalar), 2)
        }
        guard let scalar = Unicode.Scalar(unit) else { return (.other, 1) } // lone surrogate
        return (classify(scalar), 1)
    }

    /// Same token rules as `tokenize(line:)`, but over a UTF-16 buffer with no per-token allocation.
    static func tokens(in buffer: UnsafeBufferPointer<UInt16>) -> [Token] {
        var tokens: [Token] = []
        tokens.reserveCapacity(buffer.count / 3 + 1)
        var i = 0
        let n = buffer.count
        while i < n {
            let start = i
            let (cls, width) = classify(unit: buffer[i], buffer: buffer, at: i)
            i += width
            if cls != .other {
                while i < n {
                    let (next, w) = classify(unit: buffer[i], buffer: buffer, at: i)
                    guard next == cls else { break }
                    i += w
                }
            }
            tokens.append(Token(start: start, length: i - start, isWhitespace: cls == .whitespace))
        }
        return tokens
    }

    /// Computes word-level highlights between two modified lines
    public static func computeWordDiff(
        leftLine: String,
        rightLine: String
    ) -> (leftHighlights: [WordHighlightSpan], rightHighlights: [WordHighlightSpan]) {
        if leftLine.utf8.elementsEqual(rightLine.utf8) {
            return ([], [])
        }
        let left = Array(leftLine.utf16)
        let right = Array(rightLine.utf16)
        if left.count > maxLineLength || right.count > maxLineLength {
            return ([], [])
        }
        return left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                computeWordDiff(left: l, right: r)
            }
        }
    }

    static func computeWordDiff(
        left: UnsafeBufferPointer<UInt16>,
        right: UnsafeBufferPointer<UInt16>
    ) -> (leftHighlights: [WordHighlightSpan], rightHighlights: [WordHighlightSpan]) {
        if left.count > maxLineLength || right.count > maxLineLength { return ([], []) }
        let leftTokens = tokens(in: left)
        let rightTokens = tokens(in: right)
        if leftTokens.count + rightTokens.count > maxTokenCount {
            return ([], [])
        }
        var interner = ByteInterner(capacity: leftTokens.count + rightTokens.count)
        let lBase = left.baseAddress.map { UnsafeRawPointer($0) }
        let rBase = right.baseAddress.map { UnsafeRawPointer($0) }
        let leftIds = leftTokens.map { interner.id(for: lBase?.advanced(by: $0.start * 2), count: $0.length * 2) }
        let rightIds = rightTokens.map { interner.id(for: rBase?.advanced(by: $0.start * 2), count: $0.length * 2) }
        let (deleted, inserted) = MyersDiff.diff(leftIds, rightIds, costBudget: costBudget)

        return (mergedSpans(tokens: leftTokens, flags: deleted), mergedSpans(tokens: rightTokens, flags: inserted))
    }

    /// Merges changed tokens separated only by unchanged whitespace into one span,
    /// so highlights read as phrases, not confetti.
    private static func mergedSpans(tokens: [Token], flags: [Bool]) -> [WordHighlightSpan] {
        var spans: [WordHighlightSpan] = []
        var current: NSRange?
        for (idx, token) in tokens.enumerated() {
            let range = NSRange(location: token.start, length: token.length)
            if flags[idx] {
                if let open = current {
                    current = NSRange(location: open.location, length: NSMaxRange(range) - open.location)
                } else {
                    current = range
                }
            } else if current != nil, token.isWhitespace {
                continue // bridge; the span only grows if another changed token follows
            } else if let open = current {
                spans.append(WordHighlightSpan(range: open, isEmphasized: true))
                current = nil
            }
        }
        if let open = current {
            spans.append(WordHighlightSpan(range: open, isEmphasized: true))
        }
        return spans
    }
}
