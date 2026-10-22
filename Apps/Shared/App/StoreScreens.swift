import BLEKit
import CameraKit
import Foundation
import LocationKit
import Persistence
import SessionKit

/// App Store screenshots in the simulator, which has no Bluetooth. Launched
/// with `-StoreScreens <scene>`, the app runs on the simulated Sony body the
/// unit tests use, from throwaway stores seeded with a few saved cameras, the
/// Sony open and geotagging, and a fixed GPS walk; the scene then sets up one
/// screen (`stage`). Debug simulator builds only: elsewhere `scene` is `nil`
/// and none of it is compiled (AppStorePreview/README.md).
enum StoreScreens {
    #if DEBUG && targetEnvironment(simulator)
    /// The word after `-StoreScreens` (`session` when there is none).
    static let scene: String? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-StoreScreens") else { return nil }
        return arguments.indices.contains(index + 1) ? arguments[index + 1] : "session"
    }()
    #else
    static let scene: String? = nil
    #endif

    /// The coordinator for a screenshot run, or `nil` for a normal launch.
    @MainActor
    static func coordinator(logger: TranscriptLogger, rescanOnDisconnect: Bool = false) -> SessionCoordinator? {
        #if DEBUG && targetEnvironment(simulator)
        guard let scene else { return nil }
        _ = launchedAt
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xGRC-StoreScreens")
        try? FileManager.default.removeItem(at: directory)
        try? seed(directory, scene: scene)
        let central = DemoCentral()
        // Tunnel View, Yosemite: somewhere people take a camera.
        let start = GeoFix(latitude: 37.71585, longitude: -119.67722, altitude: 1347,
                           horizontalAccuracy: 5, timestamp: Date())
        return SessionCoordinator(stores: Stores(directory: directory, secrets: InMemorySecretStore()),
                                  central: central, demoCentral: central,
                                  location: SimulatedLocationSource(start: start),
                                  rescanOnDisconnect: rescanOnDisconnect, logger: logger)
        #else
        return nil
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    /// The Sony is the simulated body (a saved camera, not the Demo one, so
    /// it shows as Sony); the others are saved and stay off.
    private static func seed(_ directory: URL, scene: String) throws {
        let sonyMatch = DriverRegistry.standard.match(DemoCentral.advertisement)
        let sony = CameraRecord(driverID: "sony", name: "ILCE-7M4", modelCode: sonyMatch?.modelCode,
                                peripheralID: DemoCentral.peripheralID, lastConnectedAt: Date())
        let saved = [
            ("fujifilm", "X-T5"),
            ("ricoh", "GR IIIx"),
            ("canon.smart", "EOS R6 Mark II"),
            ("nikon.remote", "Z f"),
        ].map { CameraRecord(driverID: $0.0, name: $0.1, modelCode: nil, peripheralID: UUID(),
                             lastConnectedAt: Date().addingTimeInterval(-86_400 * 3)) }
        var settings = AppSettings.default
        settings.onboardingDone = true
        settings.lastActiveCameraID = sony.id
        settings.openGeotagSession = true
        switch scene {
        case "bulb": settings.bulbSeconds = 150
        case "delay": settings.releaseDelaySeconds = 10
        case "tap": settings.tapToShoot = true
        default: break
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.store.encode([sony] + saved).write(to: directory.appendingPathComponent("cameras.json"))
        try JSONEncoder.store.encode(settings).write(to: directory.appendingPathComponent("settings.json"))
        try seedTrack(in: directory.appendingPathComponent("Tracks", isDirectory: true))
    }

    /// An earlier session's track: a two-hour wander along the valley floor
    /// from Tunnel View, one fix every 20 s and a shot every ten minutes.
    private static func seedTrack(in directory: URL) throws {
        let start = Date().addingTimeInterval(-26 * 3600)
        var rows = [TrackStore.header]
        for i in 0..<360 {
            let t = Double(i) / 359
            let fix = GeoFix(latitude: 37.7159 + 0.024 * t + 0.0025 * sin(t * 9),
                             longitude: -119.6772 + 0.105 * t + 0.0015 * cos(t * 13),
                             altitude: 1347 - 130 * t, horizontalAccuracy: 4 + Double(i % 5),
                             timestamp: start.addingTimeInterval(Double(i) * 20))
            rows.append(TrackStore.line(for: TrackPoint(fix: fix)))
            // A shot every ten minutes or so.
            if i % 30 == 15 {
                var shot = fix
                shot.timestamp = fix.timestamp.addingTimeInterval(5)
                rows.append(TrackStore.line(for: TrackPoint(fix: shot, isShot: true)))
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = TrackStore.name(for: start, timeZone: .current)
        try (rows.joined(separator: "\n") + "\n").write(to: directory.appendingPathComponent("\(name).csv"),
                                                        atomically: true, encoding: .utf8)
    }
    #endif

    #if DEBUG && targetEnvironment(simulator)
    /// When the app started, for scenes timed to the capture.
    private static let launchedAt = Date()
    #endif

    /// Sets up the scene once the simulated Sony is connected.
    @MainActor
    static func stage(_ model: AppModel) async {
        #if DEBUG && targetEnvironment(simulator)
        guard let scene else { return }
        for _ in 0..<100 where !model.isReady { try? await Task.sleep(for: .milliseconds(100)) }
        switch scene {
        case "cameras":
            model.path = []
        case "settings":
            model.path = [.settings]
        case "tracks", "track":
            model.path = [.tracks]
        case "shots":
            // A session's worth of confirmed shots, the last one 14 s after
            // launch, so a capture at 15 s finds it still on screen.
            for _ in 0..<35 {
                model.send(.shoot)
                try? await Task.sleep(for: .milliseconds(250))
            }
            let last = launchedAt.addingTimeInterval(14).timeIntervalSinceNow
            if last > 0 { try? await Task.sleep(for: .seconds(last)) }
            model.send(.shoot)
        case "bulb", "delay":
            model.send(.shoot)
        case "timelapse":
            model.startIntervalometer(IntervalometerPlan(intervalSeconds: 4, frames: 360))
        default:
            break
        }
        #endif
    }
}
