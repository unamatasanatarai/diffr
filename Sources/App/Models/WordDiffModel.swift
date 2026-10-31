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

    /// Computes word-level highlights between two modified lines
    public static func computeWordDiff(
        leftLine: String,
        rightLine: String
    ) -> (leftHighlights: [WordHighlightSpan], rightHighlights: [WordHighlightSpan]) {
        if leftLine.utf8.elementsEqual(rightLine.utf8) {
            return ([], [])
        }
        if leftLine.utf16.count > maxLineLength || rightLine.utf16.count > maxLineLength {
            return ([], [])
        }

        let leftTokens = tokenize(line: leftLine)
        let rightTokens = tokenize(line: rightLine)
        if leftTokens.count + rightTokens.count > maxTokenCount {
            return ([], [])
        }

        var interner = TextInterner(capacity: leftTokens.count + rightTokens.count)
        let leftIds = leftTokens.map { interner.id(for: Substring($0.text)) }
        let rightIds = rightTokens.map { interner.id(for: Substring($0.text)) }
        let (deleted, inserted) = MyersDiff.diff(leftIds, rightIds, costBudget: costBudget)

        let leftSpans = mergedSpans(tokens: leftTokens, flags: deleted)
        let rightSpans = mergedSpans(tokens: rightTokens, flags: inserted)
        return (leftSpans, rightSpans)
    }

    /// Merges changed tokens separated only by unchanged whitespace into one span,
    /// so highlights read as phrases, not confetti.
    private static func mergedSpans(tokens: [(text: String, range: NSRange)], flags: [Bool]) -> [WordHighlightSpan] {
        var spans: [WordHighlightSpan] = []
        var current: NSRange?
        for (idx, token) in tokens.enumerated() {
            if flags[idx] {
                if let open = current {
                    current = NSRange(location: open.location, length: NSMaxRange(token.range) - open.location)
                } else {
                    current = token.range
                }
            } else if current != nil, classify(token.text.unicodeScalars.first ?? "x") == .whitespace {
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
