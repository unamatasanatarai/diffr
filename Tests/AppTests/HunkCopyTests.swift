import Foundation

public enum HunkCopyTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("DiffEngine applies hunk copy from Left to Right") {
            let left = "func test() {\n    return 1\n}"
            let right = "func test() {\n    return 2\n}"

            let initialDiff = DiffEngine.computeDiff(leftText: left, rightText: right)
            try expect(initialDiff.hunks.count == 1)

            let hunk = initialDiff.hunks[0]
            let merged = DiffEngine.applyHunk(hunk, leftText: left, rightText: right, direction: .leftToRight)

            try expect(merged.newLeftText == left)
            try expect(merged.newRightText == left, "Right text should now match left text")

            let finalDiff = DiffEngine.computeDiff(leftText: merged.newLeftText, rightText: merged.newRightText)
            try expect(finalDiff.isIdentical, "Files should be identical after hunk copy")
        }

        testRunner("DiffEngine applies hunk copy from Right to Left") {
            let left = "line A\nline B\nline C"
            let right = "line A\nline MODIFIED\nline C"

            let initialDiff = DiffEngine.computeDiff(leftText: left, rightText: right)
            try expect(initialDiff.hunks.count == 1)

            let hunk = initialDiff.hunks[0]
            let merged = DiffEngine.applyHunk(hunk, leftText: left, rightText: right, direction: .rightToLeft)

            try expect(merged.newLeftText == right, "Left text should now match right text")
            try expect(merged.newRightText == right)

            let finalDiff = DiffEngine.computeDiff(leftText: merged.newLeftText, rightText: merged.newRightText)
            try expect(finalDiff.isIdentical)
        }

        testRunner("DiffEngine handles multiple hunks copied sequentially until identical") {
            let left = "item 1\nitem 2\nitem 3\nitem 4"
            let right = "item 1\nitem TWO\nitem 3\nitem FOUR"

            var currentRight = right
            var diff = DiffEngine.computeDiff(leftText: left, rightText: currentRight)
            try expect(diff.hunks.count == 2, "Should have 2 separate hunks")

            // Copy first hunk
            let merged1 = DiffEngine.applyHunk(diff.hunks[0], leftText: left, rightText: currentRight, direction: .leftToRight)
            currentRight = merged1.newRightText

            // Recalculate
            diff = DiffEngine.computeDiff(leftText: left, rightText: currentRight)
            try expect(diff.hunks.count == 1, "Should have 1 remaining hunk")

            // Copy second hunk
            let merged2 = DiffEngine.applyHunk(diff.hunks[0], leftText: left, rightText: currentRight, direction: .leftToRight)
            currentRight = merged2.newRightText

            let finalDiff = DiffEngine.computeDiff(leftText: left, rightText: currentRight)
            try expect(finalDiff.isIdentical, "All hunks resolved, files must be identical")
        }
    }
}
