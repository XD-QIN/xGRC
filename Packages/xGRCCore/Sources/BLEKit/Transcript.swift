import Foundation

/// One line of a transcript (schema v1, JSON Lines). architecture doc § Key abstractions:
/// `t`, `op`, `service`, `char`, `props`, `bytes`, `attError`, `linkEvent`,
/// plus `latencyMs` and a free-text `note`.
public struct TranscriptEntry: Codable, Hashable, Sendable {
    public enum Op: String, Codable, Sendable {
        case scan, connect, discover, read, write, writeNoResponse, subscribe, notify, link, note, error
    }

    /// Seconds since the transcript started.
    public var t: Double
    public var op: Op
    public var service: String?
    public var char: String?
    public var props: String?
    public var bytes: String?
    public var attError: Int?
    public var linkEvent: String?
    public var latencyMs: Double?
    public var note: String?

    public init(t: Double, op: Op, service: String? = nil, char: String? = nil, props: String? = nil,
                bytes: String? = nil, attError: Int? = nil, linkEvent: String? = nil,
                latencyMs: Double? = nil, note: String? = nil) {
        self.t = t
        self.op = op
        self.service = service
        self.char = char
        self.props = props
        self.bytes = bytes
        self.attError = attError
        self.linkEvent = linkEvent
        self.latencyMs = latencyMs
        self.note = note
    }
}

/// First line of an exported transcript.
public struct TranscriptHeader: Codable, Hashable, Sendable {
    public var schema = 1
    public var startedAt: Date
    public var os: String
    public var device: String
    public var appVersion: String
    /// `maximumWriteLength(withResponse: false)` of the connected camera, when known.
    public var maxWriteWithoutResponse: Int?
    public var camera: String?

    public init(startedAt: Date, os: String, device: String, appVersion: String,
                maxWriteWithoutResponse: Int? = nil, camera: String? = nil) {
        self.startedAt = startedAt
        self.os = os
        self.device = device
        self.appVersion = appVersion
        self.maxWriteWithoutResponse = maxWriteWithoutResponse
        self.camera = camera
    }
}

/// A ring buffer of GATT operations, kept in memory on this device (the app
/// has no transcript export since 2026-10-16). JSON Lines export stays for
/// tests and development builds (architecture doc § Testing strategy).
public actor TranscriptLogger {
    public static let defaultCapacity = 20_000

    private var header: TranscriptHeader
    private var entries: [TranscriptEntry] = []
    /// Once the buffer is full: the index of the oldest entry, overwritten next.
    private var head = 0
    private let capacity: Int
    private let start = ContinuousClock.now
    private var dropped = 0

    public init(header: TranscriptHeader, capacity: Int = TranscriptLogger.defaultCapacity) {
        self.header = header
        self.capacity = capacity
    }

    /// Seconds since the logger started, for `TranscriptEntry.t`.
    public func elapsed() -> Double {
        let d = start.duration(to: .now)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    public func log(_ entry: TranscriptEntry) {
        guard capacity > 0 else {
            dropped += 1
            return
        }
        if entries.count < capacity {
            entries.append(entry)
        } else {
            // Full: overwrite the oldest in place instead of shifting them all.
            entries[head] = entry
            head = (head + 1) % capacity
            dropped += 1
        }
    }

    public func log(_ op: TranscriptEntry.Op, note: String) {
        log(TranscriptEntry(t: elapsed(), op: op, note: note))
    }

    public func update(camera: String?, maxWriteWithoutResponse: Int?) {
        if let camera { header.camera = camera }
        if let maxWriteWithoutResponse { header.maxWriteWithoutResponse = maxWriteWithoutResponse }
    }

    /// The entries, oldest first.
    public func snapshot() -> [TranscriptEntry] {
        Array(entries[head...] + entries[..<head])
    }

    public func clear() {
        entries.removeAll()
        head = 0
        dropped = 0
    }

    /// Header line followed by one line per entry.
    public func exportJSONLines() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var out = Data()
        out.append(try encoder.encode(header))
        out.append(0x0A)
        for entry in snapshot() {
            out.append(try encoder.encode(entry))
            out.append(0x0A)
        }
        return out
    }

    /// Writes the export to `directory/xGRC-transcript-<timestamp>.jsonl` and returns the URL.
    public func export(to directory: URL) throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
        let url = directory.appendingPathComponent("xGRC-transcript-\(stamp).jsonl")
        try exportJSONLines().write(to: url, options: .atomic)
        return url
    }
}
