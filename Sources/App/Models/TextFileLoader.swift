import Foundation

public enum TextFileLoadError: LocalizedError, Equatable {
    case notARegularFile
    case tooLarge(bytes: Int64, limit: Int64)
    case binary
    case undecodable

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
        }
    }
}

/// Loads a text file for comparison, refusing inputs that would hang or mislead the diff.
public enum TextFileLoader {
    public static let maxFileSize: Int64 = 32 * 1024 * 1024

    public static func load(url: URL, maxSize: Int64 = maxFileSize) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw TextFileLoadError.notARegularFile }
        let size = Int64(values.fileSize ?? 0)
        guard size <= maxSize else { throw TextFileLoadError.tooLarge(bytes: size, limit: maxSize) }

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard Int64(data.count) <= maxSize else { throw TextFileLoadError.tooLarge(bytes: Int64(data.count), limit: maxSize) }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> String {
        if data.isEmpty { return "" }

        // UTF-16/32 files carry a BOM and legitimately contain NUL bytes.
        let bom = [UInt8](data.prefix(4))
        if bom.starts(with: [0xFF, 0xFE]) || bom.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return text }
            throw TextFileLoadError.undecodable
        }

        // NUL bytes in the first 64 KB: treat as binary rather than showing garbage.
        if data.prefix(64 * 1024).contains(0) {
            throw TextFileLoadError.binary
        }

        // A UTF-8 BOM is kept on purpose: it is a real byte difference between files,
        // shown as a highlighted change (and as "¦" with invisibles on).
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        // Common legacy encodings; Windows-1252 is a superset of Latin-1 for printable text.
        for encoding in [String.Encoding.windowsCP1252, .isoLatin1, .macOSRoman] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        throw TextFileLoadError.undecodable
    }
}
