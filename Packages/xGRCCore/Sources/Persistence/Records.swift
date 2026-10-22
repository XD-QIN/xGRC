import CameraKit
import Foundation

/// A saved camera on this device. Bonds and identities are per device: the
/// watch and the phone each keep their own records (architecture doc § Data).
public struct CameraRecord: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var driverID: String
    public var name: String
    public var modelCode: String?
    /// The last `CBPeripheral.identifier`; iOS never exposes the MAC address.
    public var peripheralID: UUID
    public var isDemo: Bool
    public var addedAt: Date
    public var lastConnectedAt: Date?
    /// Sony *Keep camera awake* (`CC02` keep-alive during geotag); off by
    /// default because it keeps the camera's screen on.
    public var keepAwake: Bool

    public init(id: UUID = UUID(), driverID: String, name: String, modelCode: String?, peripheralID: UUID,
                isDemo: Bool = false, addedAt: Date = Date(), lastConnectedAt: Date? = nil,
                keepAwake: Bool = false) {
        self.id = id
        self.driverID = driverID
        self.name = name
        self.modelCode = modelCode
        self.peripheralID = peripheralID
        self.isDemo = isDemo
        self.addedAt = addedAt
        self.lastConnectedAt = lastConnectedAt
        self.keepAwake = keepAwake
    }

    /// Fields added after the first release, and any optional field that
    /// does not decode, take their defaults. Only the identity is required.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        driverID = try c.decode(String.self, forKey: .driverID)
        name = try c.decode(String.self, forKey: .name)
        modelCode = c.lenient(String.self, forKey: .modelCode)
        peripheralID = try c.decode(UUID.self, forKey: .peripheralID)
        isDemo = c.lenient(Bool.self, forKey: .isDemo) ?? false
        addedAt = c.lenient(Date.self, forKey: .addedAt) ?? Date()
        lastConnectedAt = c.lenient(Date.self, forKey: .lastConnectedAt)
        keepAwake = c.lenient(Bool.self, forKey: .keepAwake) ?? false
    }
}

/// What the app is used for. Remembered on each device.
public enum SessionMode: String, Hashable, Sendable, Codable, CaseIterable {
    /// Shutter and geotag together (the Shutter and Geotag pages).
    case remoteAndGeotag
    /// Shutter only: no location is used.
    case remoteOnly
    /// Geotag only: starts with the session; works with the camera's remote
    /// function off (Sony bodies before the α7 IV need it off to geotag).
    case geotagOnly

    public var usesRemote: Bool { self != .geotagOnly }
    public var usesGeotag: Bool { self != .remoteOnly }
}

/// Light, dark, or the system's appearance (iPhone and iPad; the watch is always dark).
public enum AppearanceSetting: String, Hashable, Sendable, Codable, CaseIterable {
    case system
    case light
    case dark
}

/// App settings, stored on each device independently.
public struct AppSettings: Hashable, Sendable, Codable {
    /// The longest timed bulb: 99 min 59 s, the most Canon's own Bluetooth
    /// remote bulb accepts. Fujifilm closes a bulb itself at 60 minutes;
    /// Sony and Nikon state no limit.
    public static let maxBulbSeconds = 99 * 60 + 59

    /// Single tap toggles focus instead of holding it for the grace period.
    public var afHold: Bool
    /// How long a single tap keeps focus held, 1–10 s.
    public var focusGraceSeconds: Int
    /// Show the Demo camera in the camera list. No setting shows it any
    /// more; tests (and a build for App Review) turn it on.
    public var showDemoCamera: Bool
    /// The camera the last session used, reconnected on launch.
    public var lastActiveCameraID: UUID?
    /// Seconds between location pushes, 5–60.
    public var geotagIntervalSeconds: Int
    /// A geotag session is open: re-created at launch, including after
    /// Core Location relaunches the app.
    public var openGeotagSession: Bool
    /// Release delay in seconds, 0 = off, else 1–60.
    public var releaseDelaySeconds: Int
    /// Bulb time in seconds, 0 = off. When set, one tap opens the bulb, it
    /// counts down and closes by itself (at most `maxBulbSeconds`).
    public var bulbSeconds: Int
    /// The last intervalometer settings, offered again next time.
    public var intervalometer: IntervalometerPlan
    /// Onboarding (Return to Clock, don't force-quit) was shown.
    public var onboardingDone: Bool
    /// Geotag only, remote only, or both.
    public var sessionMode: SessionMode
    /// End the session after this many minutes idle or unable to reach the
    /// camera; 0 = never.
    public var autoDisconnectMinutes: Int
    /// iPhone: start the Live Activity with the session.
    public var liveActivity: Bool
    /// Watch: a single tap on the shutter focuses and then shoots at once,
    /// and a haptic marks the release. Off: tap focuses, double tap shoots.
    /// Hand Double Tap shoots (focusing first) either way.
    public var tapToShoot: Bool
    /// Reconnect when the link drops and reopen the last session at launch.
    /// Off: a dropped link ends the session.
    public var autoReconnect: Bool
    /// iPhone and iPad: light, dark or the system's appearance.
    public var appearance: AppearanceSetting

    public init(afHold: Bool = false, focusGraceSeconds: Int = 3, showDemoCamera: Bool = false,
                lastActiveCameraID: UUID? = nil, geotagIntervalSeconds: Int = 5,
                openGeotagSession: Bool = false, releaseDelaySeconds: Int = 0, bulbSeconds: Int = 0,
                intervalometer: IntervalometerPlan = IntervalometerPlan(), onboardingDone: Bool = false,
                sessionMode: SessionMode = .remoteAndGeotag, autoDisconnectMinutes: Int = 15,
                liveActivity: Bool = true, tapToShoot: Bool = false, autoReconnect: Bool = true,
                appearance: AppearanceSetting = .system) {
        self.afHold = afHold
        self.focusGraceSeconds = focusGraceSeconds
        self.showDemoCamera = showDemoCamera
        self.lastActiveCameraID = lastActiveCameraID
        self.geotagIntervalSeconds = geotagIntervalSeconds
        self.openGeotagSession = openGeotagSession
        self.releaseDelaySeconds = releaseDelaySeconds
        self.bulbSeconds = bulbSeconds
        self.intervalometer = intervalometer
        self.onboardingDone = onboardingDone
        self.sessionMode = sessionMode
        self.autoDisconnectMinutes = autoDisconnectMinutes
        self.liveActivity = liveActivity
        self.tapToShoot = tapToShoot
        self.autoReconnect = autoReconnect
        self.appearance = appearance
    }

    /// Each setting decodes on its own: one that is missing or unreadable
    /// (an unknown mode from a newer version, a wrong type) takes its
    /// default and every other setting is kept.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        afHold = c.lenient(Bool.self, forKey: .afHold) ?? d.afHold
        focusGraceSeconds = c.lenient(Int.self, forKey: .focusGraceSeconds) ?? d.focusGraceSeconds
        showDemoCamera = c.lenient(Bool.self, forKey: .showDemoCamera) ?? d.showDemoCamera
        lastActiveCameraID = c.lenient(UUID.self, forKey: .lastActiveCameraID)
        geotagIntervalSeconds = c.lenient(Int.self, forKey: .geotagIntervalSeconds) ?? d.geotagIntervalSeconds
        openGeotagSession = c.lenient(Bool.self, forKey: .openGeotagSession) ?? d.openGeotagSession
        releaseDelaySeconds = c.lenient(Int.self, forKey: .releaseDelaySeconds) ?? d.releaseDelaySeconds
        bulbSeconds = c.lenient(Int.self, forKey: .bulbSeconds) ?? d.bulbSeconds
        intervalometer = c.lenient(IntervalometerPlan.self, forKey: .intervalometer) ?? d.intervalometer
        onboardingDone = c.lenient(Bool.self, forKey: .onboardingDone) ?? d.onboardingDone
        sessionMode = c.lenient(SessionMode.self, forKey: .sessionMode) ?? d.sessionMode
        autoDisconnectMinutes = c.lenient(Int.self, forKey: .autoDisconnectMinutes) ?? d.autoDisconnectMinutes
        liveActivity = c.lenient(Bool.self, forKey: .liveActivity) ?? d.liveActivity
        tapToShoot = c.lenient(Bool.self, forKey: .tapToShoot) ?? d.tapToShoot
        autoReconnect = c.lenient(Bool.self, forKey: .autoReconnect) ?? d.autoReconnect
        appearance = c.lenient(AppearanceSetting.self, forKey: .appearance) ?? d.appearance
    }

    public static let `default` = AppSettings()
}

/// What the intervalometer sheet sets (architecture doc § Intervalometer rules).
public struct IntervalometerPlan: Hashable, Sendable, Codable {
    /// Start-to-start, at least 1 s.
    public var intervalSeconds: Double
    /// `nil` runs until stopped.
    public var frames: Int?
    public var initialWaitSeconds: Double
    /// Run the focus step (2 s timeout) on every frame.
    public var focusEachFrame: Bool
    /// Shutter-open time; above 1 s it runs as bulb. `nil` = the camera's own shutter speed.
    public var exposureSeconds: Double?

    public init(intervalSeconds: Double = 5, frames: Int? = 100, initialWaitSeconds: Double = 0,
                focusEachFrame: Bool = false, exposureSeconds: Double? = nil) {
        self.intervalSeconds = intervalSeconds
        self.frames = frames
        self.initialWaitSeconds = initialWaitSeconds
        self.focusEachFrame = focusEachFrame
        self.exposureSeconds = exposureSeconds
    }

    /// Field by field, like `AppSettings`: an unreadable field takes its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IntervalometerPlan()
        intervalSeconds = c.lenient(Double.self, forKey: .intervalSeconds) ?? d.intervalSeconds
        // `null` is a meaningful value here (run until stopped).
        frames = c.contains(.frames) ? c.lenient(Int.self, forKey: .frames) : d.frames
        initialWaitSeconds = c.lenient(Double.self, forKey: .initialWaitSeconds) ?? d.initialWaitSeconds
        focusEachFrame = c.lenient(Bool.self, forKey: .focusEachFrame) ?? d.focusEachFrame
        exposureSeconds = c.lenient(Double.self, forKey: .exposureSeconds)
    }
}

extension KeyedDecodingContainer {
    /// The value, or `nil` when it is missing, `null` or does not decode.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// Decodes one element of a list, `nil` when that element is unreadable,
/// so one bad camera record does not cost the others.
private struct Lossy<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}

extension JSONFileStore where Value == [CameraRecord] {
    /// The camera list: each record decodes on its own.
    public init(cameraListAt url: URL) {
        self.init(url: url, defaultValue: []) { data in
            let all = try JSONDecoder.store.decode([Lossy<CameraRecord>].self, from: data)
            let records = all.compactMap(\.value)
            return (records, records.count < all.count)
        }
    }
}

/// A Codable value in one JSON file in the app's private container, written
/// atomically. SwiftData is deliberately not used (architecture doc § Data).
public actor JSONFileStore<Value: Codable & Sendable> {
    public let url: URL
    private let defaultValue: Value
    /// The value, and whether part of the file could not be read.
    private let decode: @Sendable (Data) throws -> (Value, partial: Bool)
    private var cached: Value?

    public init(url: URL, defaultValue: Value,
                decode: @escaping @Sendable (Data) throws -> (Value, partial: Bool) = {
                    (try JSONDecoder.store.decode(Value.self, from: $0), false)
                }) {
        self.url = url
        self.defaultValue = defaultValue
        self.decode = decode
    }

    /// The stored value, or the default when nothing is stored or the file is
    /// unreadable. A file that is wholly or partly unreadable is first copied
    /// aside (`<name>.unreadable-<time>.json`), so the next save cannot destroy it.
    public func load() -> Value {
        if let cached { return cached }
        var value = defaultValue
        if let data = try? Data(contentsOf: url) {
            do {
                let (decoded, partial) = try decode(data)
                value = decoded
                if partial { backUpUnreadableFile() }
            } catch {
                backUpUnreadableFile()
            }
        }
        cached = value
        return value
    }

    /// Where an unreadable file was copied, if one was.
    public private(set) var unreadableBackup: URL?

    private func backUpUnreadableFile() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        let stamp = formatter.string(from: Date())
        let name = url.deletingPathExtension().lastPathComponent
        let backup = url.deletingLastPathComponent().appendingPathComponent("\(name).unreadable-\(stamp).json")
        try? FileManager.default.removeItem(at: backup)
        if (try? FileManager.default.copyItem(at: url, to: backup)) != nil {
            unreadableBackup = backup
        }
    }

    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder.store.encode(value).write(to: url, options: .atomic)
        cached = value
    }

    /// Loads, applies `change`, saves, and returns the new value.
    @discardableResult
    public func update(_ change: @Sendable (inout Value) -> Void) throws -> Value {
        var value = load()
        change(&value)
        try save(value)
        return value
    }
}

extension JSONEncoder {
    public static var store: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    public static var store: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// The stores of the app's private container.
public struct Stores: Sendable {
    public let cameras: JSONFileStore<[CameraRecord]>
    public let settings: JSONFileStore<AppSettings>
    public let secrets: any SecretStore
    /// GPS tracks, one CSV per session that geotagged.
    public let tracks: TrackStore

    public init(directory: URL, secrets: any SecretStore) {
        cameras = JSONFileStore(cameraListAt: directory.appendingPathComponent("cameras.json"))
        settings = JSONFileStore(url: directory.appendingPathComponent("settings.json"), defaultValue: .default)
        self.secrets = secrets
        tracks = TrackStore(directory: directory.appendingPathComponent("Tracks", isDirectory: true))
    }

    /// `Application Support/xGRC` in the app's own container (never the App Group).
    public static func appDefault() throws -> Stores {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        #if canImport(Security)
        let secrets: any SecretStore = KeychainSecretStore(service: "xGRC")
        #else
        let secrets: any SecretStore = InMemorySecretStore()
        #endif
        return Stores(directory: base.appendingPathComponent("xGRC", isDirectory: true), secrets: secrets)
    }
}
