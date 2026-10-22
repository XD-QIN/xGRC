import CameraKit
import Foundation

/// One session's GPS track: a CSV file named after the session's start time
/// in local time, `yyyy-MM-dd-HH-mm-ss.csv`. The file is the record and the
/// export: nothing else describes it.
public struct TrackFile: Identifiable, Hashable, Sendable {
    public let url: URL
    /// The file name without `.csv`, e.g. `2026-10-21-09-54-36`.
    public var name: String { url.deletingPathExtension().lastPathComponent }
    public var id: String { name }
    /// When the session started, read back from the name.
    public var startedAt: Date? { TrackStore.date(fromName: name) }

    public init(url: URL) {
        self.url = url
    }
}

/// One row of a track: a fix, or a remote shot at the last fix's position.
public struct TrackPoint: Hashable, Sendable {
    public var fix: GeoFix
    /// The remote shutter fired here (`shot` is 1 in the CSV).
    public var isShot: Bool

    public init(fix: GeoFix, isShot: Bool = false) {
        self.fix = fix
        self.isShot = isShot
    }
}

/// The GPS tracks on this device, one CSV file per session that geotagged,
/// in `Application Support/xGRC/Tracks`. They never leave the device unless
/// the user exports one (privacy policy).
///
/// Recording: `begin` when a session starts, `append` for every fix the
/// geotag filter accepts, `markShot` when the remote shutter fires, `finish`
/// when the session ends. The file is created with the first fix, so a
/// session that never geotagged leaves none, and each row is one appended
/// line, so a long session costs no rewrites.
public actor TrackStore {
    public nonisolated let directory: URL
    private let timeZone: @Sendable () -> TimeZone
    private var recording: TrackFile?
    private var handle: FileHandle?
    /// The session's last fix, where a shot is placed.
    private var lastFix: GeoFix?

    /// A shot is placed at the last fix only if that fix is this recent.
    public static let shotFixMaximumAge: TimeInterval = 120

    public static let header = "timestamp,latitude,longitude,altitude_m,horizontal_accuracy_m,shot"

    public init(directory: URL, timeZone: @escaping @Sendable () -> TimeZone = { .current }) {
        self.directory = directory
        self.timeZone = timeZone
    }

    // MARK: Recording

    /// Starts the track of a session that started at `startedAt`. A second
    /// session in the same second gets `-2`, `-3`… after the name.
    public func begin(startedAt: Date) {
        finish()
        let base = Self.name(for: startedAt, timeZone: timeZone())
        var name = base
        var counter = 2
        while FileManager.default.fileExists(atPath: url(named: name).path) {
            name = "\(base)-\(counter)"
            counter += 1
        }
        recording = TrackFile(url: url(named: name))
    }

    /// Adds a fix to the session's track; ignored when no session records.
    public func append(_ fix: GeoFix) throws {
        guard recording != nil else { return }
        lastFix = fix
        try write(TrackPoint(fix: fix))
    }

    /// A remote shot at `time`: a row at the session's last fix, marked as a
    /// shot. Ignored when the session has no recent fix to place it at.
    public func markShot(at time: Date) throws {
        guard recording != nil, var fix = lastFix,
              time.timeIntervalSince(fix.timestamp) <= Self.shotFixMaximumAge else { return }
        fix.timestamp = time
        try write(TrackPoint(fix: fix, isShot: true))
    }

    private func write(_ point: TrackPoint) throws {
        guard let recording else { return }
        if handle == nil {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: recording.url.path) {
                try Data((Self.header + "\n").utf8).write(to: recording.url, options: .atomic)
            }
            handle = try FileHandle(forWritingTo: recording.url)
            try handle?.seekToEnd()
        }
        try handle?.write(contentsOf: Data((Self.line(for: point) + "\n").utf8))
    }

    /// Ends the session's track.
    public func finish() {
        try? handle?.close()
        handle = nil
        recording = nil
        lastFix = nil
    }

    /// The track being recorded, once it has a fix.
    public func current() -> TrackFile? {
        guard let recording, FileManager.default.fileExists(atPath: recording.url.path) else { return nil }
        return recording
    }

    // MARK: Reading

    /// Every track, newest first.
    public func list() -> [TrackFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "csv" }
            .map(TrackFile.init(url:))
            .sorted { $0.name > $1.name }
    }

    /// The rows of a track, in the order they were recorded. Lines that do
    /// not read as a row (the header, a line cut short) are skipped.
    public func points(of track: TrackFile) throws -> [TrackPoint] {
        try Self.parse(String(contentsOf: track.url, encoding: .utf8))
    }

    public func delete(_ track: TrackFile) throws {
        if track == recording { finish() }
        try FileManager.default.removeItem(at: track.url)
    }

    private func url(named name: String) -> URL {
        directory.appendingPathComponent(name).appendingPathExtension("csv")
    }

    // MARK: Format

    /// `2026-10-21-09-54-36`: the start time in the device's time zone.
    public static func name(for date: Date, timeZone: TimeZone) -> String {
        nameFormatter(timeZone).string(from: date)
    }

    /// The start time a track's name gives, in the device's time zone. A
    /// `-2` suffix is ignored.
    public static func date(fromName name: String, timeZone: TimeZone = .current) -> Date? {
        nameFormatter(timeZone).date(from: String(name.prefix(19)))
    }

    private static func nameFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }

    /// One CSV row: the time in UTC (ISO 8601), degrees to seven places
    /// (about 1 cm), metres to one place, and `shot` 1 for a remote shot, 0
    /// for a fix. No altitude is an empty field.
    public static func line(for point: TrackPoint) -> String {
        let fix = point.fix
        let altitude = fix.altitude.map { String(format: "%.1f", $0) } ?? ""
        return [timestampFormatter.string(from: fix.timestamp),
                String(format: "%.7f", fix.latitude),
                String(format: "%.7f", fix.longitude),
                altitude,
                String(format: "%.1f", fix.horizontalAccuracy),
                point.isShot ? "1" : "0"].joined(separator: ",")
    }

    /// Reads rows with or without the `shot` column (tracks recorded before
    /// it have none: every row a fix).
    public static func parse(_ csv: String) -> [TrackPoint] {
        csv.split(whereSeparator: \.isNewline).compactMap { row in
            let fields = row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5 || fields.count == 6,
                  let timestamp = timestampFormatter.date(from: fields[0]),
                  let latitude = Double(fields[1]), let longitude = Double(fields[2]),
                  let accuracy = Double(fields[4]) else { return nil }
            let fix = GeoFix(latitude: latitude, longitude: longitude, altitude: Double(fields[3]),
                             horizontalAccuracy: accuracy, timestamp: timestamp)
            return TrackPoint(fix: fix, isShot: fields.count == 6 && fields[5] == "1")
        }
    }

    // ISO8601DateFormatter is thread-safe for formatting and parsing.
    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
