import Foundation

/// The file a pane was opened from (or saved to), and what was last written to it.
public struct PaneDocument {
    public var url: URL
    public var encoding: TextFileEncoding
    /// Exact text as last loaded/saved; the pane is dirty when its text differs from this.
    public var savedText: String
    public var modificationDate: Date?

    public init(url: URL, encoding: TextFileEncoding, savedText: String, modificationDate: Date?) {
        self.url = url
        self.encoding = encoding
        self.savedText = savedText
        self.modificationDate = modificationDate
    }

    public init(loaded: LoadedTextFile) {
        self.init(url: loaded.url, encoding: loaded.encoding, savedText: loaded.text, modificationDate: loaded.modificationDate)
    }

    /// Byte-exact, so undoing back to the saved text makes the pane clean again.
    public func isDirty(currentText: String) -> Bool {
        return !currentText.utf8.elementsEqual(savedText.utf8)
    }

    /// True when another application modified the file since we loaded or saved it.
    public var hasChangedOnDisk: Bool {
        guard let known = modificationDate,
              let current = TextFileLoader.modificationDate(of: url.resolvingSymlinksInPath()) else { return false }
        return current != known
    }
}
