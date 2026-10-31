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

public enum EditorSide: Hashable, CaseIterable {
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

/// One visual row of the split view. Rows carry no line text (that already lives in the
/// editors and, for changed lines, in the hunk): keeping a copy of every line here doubled
/// memory for large files.
public struct AlignedDiffRow: Equatable {
    public let leftLineNumber: Int?
    public let leftKind: DiffLineKind
    public internal(set) var leftWordHighlights: [WordHighlightSpan]

    public let rightLineNumber: Int?
    public let rightKind: DiffLineKind
    public internal(set) var rightWordHighlights: [WordHighlightSpan]

    public let hunkIndex: Int?

    public init(
        leftLineNumber: Int?,
        leftKind: DiffLineKind,
        leftWordHighlights: [WordHighlightSpan] = [],
        rightLineNumber: Int?,
        rightKind: DiffLineKind,
        rightWordHighlights: [WordHighlightSpan] = [],
        hunkIndex: Int?
    ) {
        self.leftLineNumber = leftLineNumber
        self.leftKind = leftKind
        self.leftWordHighlights = leftWordHighlights
        self.rightLineNumber = rightLineNumber
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
    /// Upper bound on the display width of the widest line on each side, in monospace columns.
    public var leftMaxColumns: Int = 0
    public var rightMaxColumns: Int = 0

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

    /// O(1) lookup: hunk ids are their index in `hunks` (falls back to a scan otherwise).
    public func hunk(withId id: Int) -> DiffHunk? {
        if id >= 0 && id < hunks.count && hunks[id].id == id { return hunks[id] }
        return hunks.first { $0.id == id }
    }

    public static var empty: DiffResult {
        return DiffResult(hunks: [], alignedRows: [], additionsCount: 0, deletionsCount: 0)
    }
}
