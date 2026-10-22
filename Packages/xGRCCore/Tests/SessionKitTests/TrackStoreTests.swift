import CameraKit
import Foundation
import Persistence
import Testing

/// A session's GPS track: one CSV per session, named by its start time.
@Suite("GPS tracks")
struct TrackStoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("xgrc-tracks-\(UUID().uuidString)", isDirectory: true)
    let zone = TimeZone(identifier: "America/New_York")!
    /// 2026-10-21 09:54:36 in New York.
    let start = Date(timeIntervalSince1970: 1_792_590_876)

    private func fix(_ i: Int, altitude: Double? = 42) -> GeoFix {
        GeoFix(latitude: 37.71585 + Double(i) * 0.0001, longitude: -119.67722, altitude: altitude,
               horizontalAccuracy: 5, timestamp: start.addingTimeInterval(Double(i)))
    }

    @Test("The file is named by the session's local start time and holds one row per fix")
    func recordsAndReadsBack() async throws {
        let store = TrackStore(directory: directory, timeZone: { [zone] in zone })
        await store.begin(startedAt: start)
        #expect(await store.current() == nil)
        try await store.append(fix(0))
        try await store.append(fix(1, altitude: nil))
        await store.finish()

        let tracks = await store.list()
        #expect(tracks.map(\.url.lastPathComponent) == ["2026-10-21-09-54-36.csv"])
        let csv = try String(contentsOf: tracks[0].url, encoding: .utf8)
        #expect(csv.split(separator: "\n").map(String.init) == [
            TrackStore.header,
            "2026-10-21T13:54:36.000Z,37.7158500,-119.6772200,42.0,5.0,0",
            "2026-10-21T13:54:37.000Z,37.7159500,-119.6772200,,5.0,0",
        ])
        // Read back as written: the same rows, to the precision the file keeps.
        let points = try await store.points(of: tracks[0])
        #expect(points.map(TrackStore.line(for:)) == [fix(0), fix(1, altitude: nil)]
            .map { TrackStore.line(for: TrackPoint(fix: $0)) })
        #expect(points.map(\.fix.timestamp) == [start, start.addingTimeInterval(1)])
        #expect(points[1].fix.altitude == nil)
        #expect(points.allSatisfy { !$0.isShot })
        #expect(TrackStore.date(fromName: tracks[0].name, timeZone: zone) == start)
    }

    @Test("A session that never geotagged leaves no file; one in the same second gets a suffix")
    func emptyAndSameSecond() async throws {
        let store = TrackStore(directory: directory, timeZone: { [zone] in zone })
        await store.begin(startedAt: start)
        await store.finish()
        #expect(await store.list().isEmpty)

        await store.begin(startedAt: start)
        try await store.append(fix(0))
        await store.begin(startedAt: start)
        try await store.append(fix(1))
        await store.finish()
        #expect(await store.list().map(\.name) == ["2026-10-21-09-54-36-2", "2026-10-21-09-54-36"])
        // Fixes after the end go nowhere.
        try await store.append(fix(2))
        #expect(try await store.points(of: store.list()[0]).count == 1)
    }

    @Test("A shot is a row at the last fix with its own time and shot 1; without a recent fix it is dropped")
    func shots() async throws {
        let store = TrackStore(directory: directory, timeZone: { [zone] in zone })
        await store.begin(startedAt: start)
        try await store.markShot(at: start)
        #expect(await store.current() == nil)
        try await store.append(fix(0))
        try await store.markShot(at: start.addingTimeInterval(4))
        try await store.markShot(at: start.addingTimeInterval(TrackStore.shotFixMaximumAge + 1))
        await store.finish()

        let track = try #require(await store.list().first)
        let lines = try String(contentsOf: track.url, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(lines.last == "2026-10-21T13:54:40.000Z,37.7158500,-119.6772200,42.0,5.0,1")
        let points = try await store.points(of: track)
        #expect(points.map(\.isShot) == [false, true])
    }

    @Test("A track from before the shot column reads as fixes")
    func oldFormat() {
        let points = TrackStore.parse("""
        timestamp,latitude,longitude,altitude_m,horizontal_accuracy_m
        2026-10-21T13:54:36.000Z,37.7158500,-119.6772200,42.0,5.0
        """)
        #expect(points.count == 1)
        #expect(points[0].isShot == false)
    }

    @Test("Delete removes the file, and a cut-off last line is skipped")
    func deleteAndDamagedLine() async throws {
        let store = TrackStore(directory: directory, timeZone: { [zone] in zone })
        await store.begin(startedAt: start)
        try await store.append(fix(0))
        await store.finish()
        let track = try #require(await store.list().first)
        let handle = try FileHandle(forWritingTo: track.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("2026-10-21T13:54:40.000Z,37.71".utf8))
        try handle.close()
        #expect(try await store.points(of: track).count == 1)
        try await store.delete(track)
        #expect(await store.list().isEmpty)
    }
}
