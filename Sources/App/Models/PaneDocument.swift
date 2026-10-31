import Foundation

/// The file a pane was opened from (or saved to), and what was last written to it.
public struct PaneDocument {
    public var url: URL
    public var encoding: TextFileEncoding
    /// Exact text as last loaded/saved; the pane is dirty when its text differs from this.
    public var savedText: String {
        didSet { savedSnapshot = NSString(string: savedText) }
    }
    /// Foundation-native copy of `savedText`, so dirty checks against the editor's NSString are
    /// a length check plus a memcmp-speed literal compare instead of a per-character bridge.
    private var savedSnapshot: NSString
    public var modificationDate: Date?

    public init(url: URL, encoding: TextFileEncoding, savedText: String, modificationDate: Date?) {
        self.url = url
        self.encoding = encoding
        self.savedText = savedText
        self.savedSnapshot = NSString(string: savedText)
        self.modificationDate = modificationDate
    }

    public init(loaded: LoadedTextFile) {
        self.init(url: loaded.url, encoding: loaded.encoding, savedText: loaded.text, modificationDate: loaded.modificationDate)
    }

    /// Byte-exact, so undoing back to the saved text makes the pane clean again.
    public func isDirty(currentText: String) -> Bool {
        return !currentText.utf8.elementsEqual(savedText.utf8)
    }

    /// Same check against the editor's backing string: literal UTF-16 comparison (no Unicode
    /// normalization), with no conversion of the whole text on every diff.
    public func isDirty(current: NSString) -> Bool {
        return current.length != savedSnapshot.length || !current.isEqual(savedSnapshot)
    }

    /// True when another application modified the file since we loaded or saved it.
    public var hasChangedOnDisk: Bool {
        guard let known = modificationDate,
              let current = TextFileLoader.modificationDate(of: url.resolvingSymlinksInPath()) else { return false }
        return current != known
    }
}
