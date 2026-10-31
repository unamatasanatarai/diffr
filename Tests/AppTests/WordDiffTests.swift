import Foundation

public enum WordDiffTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("WordDiffEngine tokenizes words, spaces, and punctuation correctly") {
            let line = "let count = 42;"
            let tokens = WordDiffEngine.tokenize(line: line)

            let texts = tokens.map { $0.text }
            try expect(texts.contains("let"), "Should contain word 'let'")
            try expect(texts.contains(" "), "Should contain space token")
            try expect(texts.contains("count"), "Should contain word 'count'")
            try expect(texts.contains("="), "Should contain '=' token")
            try expect(texts.contains("42"), "Should contain '42' token")
            try expect(texts.contains(";"), "Should contain ';' token")
        }

        testRunner("WordDiffEngine identifies word changes between modified lines") {
            let left = "print(\"hello world\")"
            let right = "print(\"hello brave new world\")"

            let diff = WordDiffEngine.computeWordDiff(leftLine: left, rightLine: right)
            try expect(!diff.rightHighlights.isEmpty, "Right line should have inserted word highlights")
        }

        testRunner("WordDiffEngine returns empty highlights for identical lines") {
            let line = "const value = true;"
            let diff = WordDiffEngine.computeWordDiff(leftLine: line, rightLine: line)
            try expect(diff.leftHighlights.isEmpty)
            try expect(diff.rightHighlights.isEmpty)
        }
    }
}
