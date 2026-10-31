import Foundation

/// Allocation-free text primitives over raw UTF-8 / UTF-16 buffers.
///
/// The generic Swift paths (`String(decoding:as: UTF16.self)`, `utf8.split`, hashing
/// `Substring`s, bridging a mutable `NSString`) are an order of magnitude slower than these
/// tight loops on multi-megabyte inputs, and the diff runs them on every edit.
enum TextBuffers {
    /// Transcodes UTF-16 to a native UTF-8 `String`. Lone surrogates become U+FFFD,
    /// matching Swift's own bridging, so UTF-16 offsets stay 1:1 with the source.
    static func string(fromUTF16 units: UnsafeBufferPointer<UInt16>) -> String {
        let n = units.count
        if n == 0 { return "" }
        return String(unsafeUninitializedCapacity: n * 3) { out in
            var o = 0
            var i = 0
            while i < n {
                let u = units[i]
                if u < 0x80 {
                    out[o] = UInt8(truncatingIfNeeded: u)
                    o += 1
                    i += 1
                } else if u < 0x800 {
                    out[o] = UInt8(truncatingIfNeeded: 0xC0 | (u >> 6))
                    out[o + 1] = UInt8(truncatingIfNeeded: 0x80 | (u & 0x3F))
                    o += 2
                    i += 1
                } else if UTF16.isLeadSurrogate(u), i + 1 < n, UTF16.isTrailSurrogate(units[i + 1]) {
                    let scalar = 0x10000 + ((UInt32(u) - 0xD800) << 10) + (UInt32(units[i + 1]) - 0xDC00)
                    out[o] = UInt8(truncatingIfNeeded: 0xF0 | (scalar >> 18))
                    out[o + 1] = UInt8(truncatingIfNeeded: 0x80 | ((scalar >> 12) & 0x3F))
                    out[o + 2] = UInt8(truncatingIfNeeded: 0x80 | ((scalar >> 6) & 0x3F))
                    out[o + 3] = UInt8(truncatingIfNeeded: 0x80 | (scalar & 0x3F))
                    o += 4
                    i += 2
                } else {
                    // BMP character, or a lone surrogate replaced by U+FFFD.
                    let scalar: UInt16 = (UTF16.isLeadSurrogate(u) || UTF16.isTrailSurrogate(u)) ? 0xFFFD : u
                    out[o] = UInt8(truncatingIfNeeded: 0xE0 | (scalar >> 12))
                    out[o + 1] = UInt8(truncatingIfNeeded: 0x80 | ((scalar >> 6) & 0x3F))
                    out[o + 2] = UInt8(truncatingIfNeeded: 0x80 | (scalar & 0x3F))
                    o += 3
                    i += 1
                }
            }
            return o
        }
    }

    /// Appends the UTF-16 form of valid UTF-8 bytes (e.g. from a native `String`) to `out`.
    static func appendUTF16(fromUTF8 bytes: UnsafeBufferPointer<UInt8>, to out: inout [UInt16]) {
        let n = bytes.count
        var i = 0
        while i < n {
            let b = bytes[i]
            if b < 0x80 {
                out.append(UInt16(b))
                i += 1
            } else if b < 0xE0, i + 1 < n {
                out.append((UInt16(b & 0x1F) << 6) | UInt16(bytes[i + 1] & 0x3F))
                i += 2
            } else if b < 0xF0, i + 2 < n {
                out.append((UInt16(b & 0x0F) << 12) | (UInt16(bytes[i + 1] & 0x3F) << 6) | UInt16(bytes[i + 2] & 0x3F))
                i += 3
            } else if i + 3 < n {
                let scalar = (UInt32(b & 0x07) << 18) | (UInt32(bytes[i + 1] & 0x3F) << 12)
                    | (UInt32(bytes[i + 2] & 0x3F) << 6) | UInt32(bytes[i + 3] & 0x3F)
                let v = scalar - 0x10000
                out.append(UInt16(truncatingIfNeeded: 0xD800 + (v >> 10)))
                out.append(UInt16(truncatingIfNeeded: 0xDC00 + (v & 0x3FF)))
                i += 4
            } else {
                out.append(0xFFFD) // truncated sequence; cannot happen for a native String
                i = n
            }
        }
    }

    /// Byte ranges of each line, split on "\n" only (the "\n" itself excluded), keeping a
    /// trailing empty line when the text ends with "\n". Empty text has no lines.
    static func lineRanges(utf8 bytes: UnsafeBufferPointer<UInt8>) -> [Range<Int>] {
        let n = bytes.count
        guard n > 0, let base = bytes.baseAddress else { return [] }
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(n / 32 + 1)
        var start = 0
        while start <= n {
            let remaining = n - start
            if remaining > 0, let hit = memchr(base + start, 0x0A, remaining) {
                let end = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                ranges.append(start..<end)
                start = end + 1
            } else {
                ranges.append(start..<n)
                break
            }
        }
        return ranges
    }

    /// Upper bound on the display width of the widest line, in monospace columns:
    /// tabs count 4, characters of 3+ UTF-8 bytes count 2 (CJK, emoji).
    static func maxColumns(utf8 bytes: UnsafeBufferPointer<UInt8>) -> Int {
        var best = 0
        var col = 0
        for b in bytes {
            if b == 0x0A {
                if col > best { best = col }
                col = 0
            } else if b == 0x09 {
                col += 4
            } else if b & 0xC0 != 0x80 {
                col += (b >= 0xE0) ? 2 : 1
            }
        }
        return max(best, col)
    }
}

/// Maps byte ranges to dense integer ids (equal bytes ⇔ equal id), for diffing ints instead of text.
///
/// Byte equality, not `String ==`: Swift's canonical equivalence ("é" == "e\u{301}") would hide
/// exactly the kind of invisible difference a diff tool must reveal.
///
/// Open addressing with a fast word-at-a-time hash; equality is always confirmed with `memcmp`,
/// so collisions cost time, never correctness. Several times faster than `Dictionary` with
/// `Hasher` (SipHash) for the tens of thousands of short keys a diff interns.
struct ByteInterner {
    private var slots: [Int32]
    private var hashes: [UInt64] = []
    private var bases: [UnsafeRawPointer?] = []
    private var counts: [Int] = []
    private let mask: Int

    /// `capacity` must be at least the number of `id(for:count:)` calls that will be made.
    init(capacity: Int) {
        var size = 16
        while size < capacity * 2 { size <<= 1 }
        slots = [Int32](repeating: -1, count: size)
        mask = size - 1
        hashes.reserveCapacity(capacity)
        bases.reserveCapacity(capacity)
        counts.reserveCapacity(capacity)
    }

    @inline(__always)
    private static func hash(_ base: UnsafeRawPointer?, _ count: Int) -> UInt64 {
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15 ^ UInt64(truncatingIfNeeded: count)
        guard let base = base else { return h }
        var i = 0
        while i + 8 <= count {
            var word: UInt64 = 0
            memcpy(&word, base + i, 8)
            h = (h ^ word) &* 0x0000_0100_0000_01B3 &+ 0x2545_F491_4F6C_DD1D
            h ^= h >> 29
            i += 8
        }
        if i < count {
            var word: UInt64 = 0
            memcpy(&word, base + i, count - i)
            h = (h ^ word) &* 0x0000_0100_0000_01B3 &+ 0x2545_F491_4F6C_DD1D
        }
        h ^= h >> 32
        h = h &* 0xD6E8_FEB8_6659_FD93
        h ^= h >> 32
        return h
    }

    mutating func id(for base: UnsafeRawPointer?, count: Int) -> Int {
        let h = Self.hash(base, count)
        var slot = Int(truncatingIfNeeded: h) & mask
        while true {
            let entry = Int(slots[slot])
            if entry < 0 {
                let newId = hashes.count
                slots[slot] = Int32(newId)
                hashes.append(h)
                bases.append(base)
                counts.append(count)
                return newId
            }
            if hashes[entry] == h && counts[entry] == count
                && (count == 0 || memcmp(bases[entry]!, base!, count) == 0) {
                return entry
            }
            slot = (slot + 1) & mask
        }
    }
}
