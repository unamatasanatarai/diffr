import Foundation

public enum TextFileLoadError: LocalizedError, Equatable {
    case notARegularFile
    case tooLarge(bytes: Int64, limit: Int64)
    case binary
    case undecodable
    case unencodable(encodingName: String)

    public var errorDescription: String? {
        switch self {
        case .notARegularFile:
            return "This is not a regular file."
        case .tooLarge(let bytes, let limit):
            let formatter = ByteCountFormatter()
            return "The file is too large to compare (\(formatter.string(fromByteCount: bytes)); limit \(formatter.string(fromByteCount: limit)))."
        case .binary:
            return "The file appears to be binary, not text."
        case .undecodable:
            return "The file's text encoding could not be determined."
        case .unencodable(let name):
            return "The text contains characters that cannot be saved in the file's encoding (\(name))."
        }
    }
}

/// The on-disk encoding of a loaded file, remembered so saving writes the same kind of bytes back.
public enum TextFileEncoding: Equatable {
    case utf8
    case utf16LittleEndianBOM
    case utf16BigEndianBOM
    case windowsCP1252
    case isoLatin1
    case macOSRoman

    public var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16LittleEndianBOM: return "UTF-16 LE"
        case .utf16BigEndianBOM: return "UTF-16 BE"
        case .windowsCP1252: return "Windows-1252"
        case .isoLatin1: return "ISO Latin-1"
        case .macOSRoman: return "Mac OS Roman"
        }
    }

    fileprivate var stringEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16LittleEndianBOM: return .utf16LittleEndian
        case .utf16BigEndianBOM: return .utf16BigEndian
        case .windowsCP1252: return .windowsCP1252
        case .isoLatin1: return .isoLatin1
        case .macOSRoman: return .macOSRoman
        }
    }

    fileprivate var bom: [UInt8] {
        switch self {
        case .utf16LittleEndianBOM: return [0xFF, 0xFE]
        case .utf16BigEndianBOM: return [0xFE, 0xFF]
        default: return [] // A UTF-8 BOM, if any, is part of the text itself (U+FEFF).
        }
    }
}

public struct LoadedTextFile {
    public let url: URL
    public let text: String
    public let encoding: TextFileEncoding
    public let modificationDate: Date?
}

/// Loads and saves text files, refusing inputs that would hang or mislead the diff.
public enum TextFileLoader {
    public static let maxFileSize: Int64 = 32 * 1024 * 1024

    public static func load(url: URL, maxSize: Int64 = maxFileSize) throws -> String {
        return try loadFile(url: url, maxSize: maxSize).text
    }

    public static func loadFile(url: URL, maxSize: Int64 = maxFileSize) throws -> LoadedTextFile {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        guard values.isRegularFile == true else { throw TextFileLoadError.notARegularFile }
        let size = Int64(values.fileSize ?? 0)
        guard size <= maxSize else { throw TextFileLoadError.tooLarge(bytes: size, limit: maxSize) }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard Int64(data.count) <= maxSize else { throw TextFileLoadError.tooLarge(bytes: Int64(data.count), limit: maxSize) }
        let (text, encoding) = try decodeWithEncoding(data)
        return LoadedTextFile(url: url, text: text, encoding: encoding, modificationDate: values.contentModificationDate)
    }

    public static func decode(_ data: Data) throws -> String {
        return try decodeWithEncoding(data).text
    }

    public static func decodeWithEncoding(_ data: Data) throws -> (text: String, encoding: TextFileEncoding) {
        if data.isEmpty { return ("", .utf8) }

        // UTF-16 files carry a BOM and legitimately contain NUL bytes.
        let head = [UInt8](data.prefix(2))
        for encoding in [TextFileEncoding.utf16LittleEndianBOM, .utf16BigEndianBOM] where head == encoding.bom {
            if let text = String(data: data.dropFirst(2), encoding: encoding.stringEncoding) {
                return (text, encoding)
            }
            throw TextFileLoadError.undecodable
        }

        // NUL bytes in the first 64 KB: treat as binary rather than showing garbage.
        if data.prefix(64 * 1024).contains(0) {
            throw TextFileLoadError.binary
        }

        // A UTF-8 BOM is kept on purpose: it is a real byte difference between files,
        // shown as a highlighted change (and as "¦" with invisibles on).
        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }
        // Common legacy encodings; Windows-1252 is a superset of Latin-1 for printable text.
        for encoding in [TextFileEncoding.windowsCP1252, .isoLatin1, .macOSRoman] {
            if let text = String(data: data, encoding: encoding.stringEncoding) { return (text, encoding) }
        }
        throw TextFileLoadError.undecodable
    }

    /// Encodes without loss; throws instead of silently replacing characters the encoding lacks.
    public static func encode(_ text: String, as encoding: TextFileEncoding) throws -> Data {
        guard let body = text.data(using: encoding.stringEncoding, allowLossyConversion: false) else {
            throw TextFileLoadError.unencodable(encodingName: encoding.displayName)
        }
        return Data(encoding.bom) + body
    }

    public static func modificationDate(of url: URL) -> Date? {
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Writes `text` safely and returns the new modification date.
    ///
    /// The new contents are written to a temporary file first and swapped in, so a failed write
    /// never leaves a truncated file. Symlinks are followed (the link itself is preserved), and
    /// `replaceItemAt` keeps the original file's permissions and metadata.
    @discardableResult
    public static func save(_ text: String, to url: URL, encoding: TextFileEncoding) throws -> Date? {
        let data = try encode(text, as: encoding)
        let target = url.resolvingSymlinksInPath()
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: target.path) {
            let scratchDir = try fileManager.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: target,
                create: true
            )
            defer { try? fileManager.removeItem(at: scratchDir) }
            let scratch = scratchDir.appendingPathComponent(target.lastPathComponent)
            try data.write(to: scratch)
            _ = try fileManager.replaceItemAt(target, withItemAt: scratch)
        } else {
            try data.write(to: target, options: .atomic)
        }
        return modificationDate(of: target)
    }
}
