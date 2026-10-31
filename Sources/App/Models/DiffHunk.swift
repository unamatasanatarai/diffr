import Foundation

public enum DiffLineKind: Equatable {
    case unchanged
    case addition
    case deletion
    case spacer // Visual padding for aligned split diff display
}

public enum HunkKind: Equatable {
    case addition
    case deletion
    case modification
}

public enum EditorSide: Equatable {
    case left
    case right
}

public enum MergeDirection: Equatable {
    case leftToRight
    case rightToLeft
}

public struct WordHighlightSpan: Equatable {
    public let range: NSRange
    public let isEmphasized: Bool

    public init(range: NSRange, isEmphasized: Bool) {
        self.range = range
        self.isEmphasized = isEmphasized
    }
}

public struct AlignedDiffRow: Equatable {
    public let leftLineNumber: Int?
    public let leftText: String?
    public let leftKind: DiffLineKind
    public let leftWordHighlights: [WordHighlightSpan]

    public let rightLineNumber: Int?
    public let rightText: String?
    public let rightKind: DiffLineKind
    public let rightWordHighlights: [WordHighlightSpan]

    public let hunkIndex: Int?

    public init(
        leftLineNumber: Int?,
        leftText: String?,
        leftKind: DiffLineKind,
        leftWordHighlights: [WordHighlightSpan] = [],
        rightLineNumber: Int?,
        rightText: String?,
        rightKind: DiffLineKind,
        rightWordHighlights: [WordHighlightSpan] = [],
        hunkIndex: Int?
    ) {
        self.leftLineNumber = leftLineNumber
        self.leftText = leftText
        self.leftKind = leftKind
        self.leftWordHighlights = leftWordHighlights
        self.rightLineNumber = rightLineNumber
        self.rightText = rightText
        self.rightKind = rightKind
        self.rightWordHighlights = rightWordHighlights
        self.hunkIndex = hunkIndex
    }
}

public struct DiffHunk: Equatable {
    public let id: Int
    public let leftLineRange: Range<Int>   // 0-indexed line range in left text
    public let rightLineRange: Range<Int>  // 0-indexed line range in right text
    public let alignedRowRange: Range<Int> // 0-indexed row range in alignedRows
    public let leftLines: [String]
    public let rightLines: [String]
    public let kind: HunkKind

    public init(
        id: Int,
        leftLineRange: Range<Int>,
        rightLineRange: Range<Int>,
        alignedRowRange: Range<Int>,
        leftLines: [String],
        rightLines: [String],
        kind: HunkKind
    ) {
        self.id = id
        self.leftLineRange = leftLineRange
        self.rightLineRange = rightLineRange
        self.alignedRowRange = alignedRowRange
        self.leftLines = leftLines
        self.rightLines = rightLines
        self.kind = kind
    }
}

public struct DiffResult: Equatable {
    public let hunks: [DiffHunk]
    public let alignedRows: [AlignedDiffRow]
    public let additionsCount: Int
    public let deletionsCount: Int

    public var isIdentical: Bool {
        return hunks.isEmpty
    }

    public init(
        hunks: [DiffHunk],
        alignedRows: [AlignedDiffRow],
        additionsCount: Int,
        deletionsCount: Int
    ) {
        self.hunks = hunks
        self.alignedRows = alignedRows
        self.additionsCount = additionsCount
        self.deletionsCount = deletionsCount
    }

    public static var empty: DiffResult {
        return DiffResult(hunks: [], alignedRows: [], additionsCount: 0, deletionsCount: 0)
    }
}
