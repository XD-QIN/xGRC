import BLEKit
import Foundation

/// One camera brand and mode: pure protocol logic, no timing policy
/// (architecture doc § Key abstractions). Timing (gestures, ack windows, grace periods)
/// lives in SessionKit's `ShotSequencer`, which executes the driver's
/// `shotScript`, and `GeoTagStreamer` owns geotag timing.
public protocol CameraDriver: Actor {
    static var descriptor: DriverDescriptor { get }
    /// Decodes a foreground-scan advertisement. `nil` when it is not this brand.
    static func matches(_ advertisement: Advertisement) -> CameraMatch?
    /// Services that identify this brand on a connected peripheral, for
    /// finding a camera another app already has connected.
    static var serviceUUIDs: [UUID] { get }

    init(transport: any GATTTransport)

    /// First pairing on a camera found by scan. Triggers the system bonding
    /// dialog by touching a protected characteristic, runs the brand's
    /// registration, and returns the identity to persist.
    func pair(_ advertisement: Advertisement, client: ClientIdentity,
              progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity

    /// Every connect after pairing, including every OS auto-reconnect:
    /// re-subscribe, re-register, re-enable. Never writes first-pairing-only
    /// commands (Sony `EE01`).
    func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws

    /// Releases every button (`shotScript.releaseAllWrites`, errors ignored),
    /// then drops the link. An open bulb is closed by the sequencer first.
    func disconnect() async

    func press(_ button: CameraButton) async throws -> PressOutcome
    func release(_ button: CameraButton) async throws

    /// Sends one write from the shot script, serialised with the script's
    /// minimum write gap.
    func send(_ write: ShotWrite) async throws

    /// The brand's step lists for focus, shooting and bulb.
    nonisolated var shotScript: ShotScript { get }

    /// A fresh stream of decoded camera events for each caller.
    nonisolated func events() -> AsyncStream<CameraEvent>

    /// Which features the session uses (the app's Remote / Geotag / Both
    /// mode). A geotag-only session must work with the camera's remote
    /// function off. Called before `pair` or `reconnect`.
    func setFeatures(remote: Bool, geotag: Bool)

    // MARK: Location link (drivers without `.geotag` keep the defaults)

    /// Brand rules for fix age, interval and timestamps.
    nonisolated var geotagRules: GeotagRules { get }
    /// Enables the camera's location link (Sony `DD30`/`DD31`). Throws
    /// `CameraError.locationLinkOff` when the camera's own setting is off and
    /// `.busy` when another device holds the lock. Re-run by `reconnect`
    /// while it is active.
    func startLocationLink() async throws -> LocationLinkMode
    /// Disables the link so another device can take it. Never throws.
    func stopLocationLink() async
    /// Periodic write that keeps the camera awake, when the brand has one.
    nonisolated var keepAlive: KeepAlivePolicy? { get }
    /// Sets the camera clock where the protocol has a separate time packet.
    func syncClock(_ time: Date, zone: TimeZone) async throws
    /// Sends one fix. `time` is the stamp to send (send time or fix time,
    /// per `geotagRules`); `zone` gives the UTC offset and DST for brands
    /// that carry them (Sony 95-byte packet).
    func updateLocation(_ fix: GeoFix, time: Date, zone: TimeZone) async throws
}

extension CameraDriver {
    public static var serviceUUIDs: [UUID] { [] }
    public func setFeatures(remote: Bool, geotag: Bool) {}
    public nonisolated var geotagRules: GeotagRules { GeotagRules() }
    public func startLocationLink() async throws -> LocationLinkMode { throw CameraError.unsupported }
    public func stopLocationLink() async {}
    public nonisolated var keepAlive: KeepAlivePolicy? { nil }
    public func syncClock(_ time: Date, zone: TimeZone) async throws {}
    public func updateLocation(_ fix: GeoFix, time: Date, zone: TimeZone) async throws {
        throw CameraError.unsupported
    }
}

/// Static facts about a driver, shown in the UI and read by the sequencer.
public struct DriverDescriptor: Hashable, Sendable {
    /// Stable identifier persisted in `CameraRecord.driverID`.
    public let id: String
    public let brand: CameraBrand
    public let displayName: String
    public let capabilities: DriverCapabilities
    /// Where shot confirmations come from, for the transcript and the UI.
    public let ackSource: String

    public init(id: String, brand: CameraBrand, displayName: String,
                capabilities: DriverCapabilities, ackSource: String) {
        self.id = id
        self.brand = brand
        self.displayName = displayName
        self.capabilities = capabilities
        self.ackSource = ackSource
    }
}

public enum CameraBrand: String, Hashable, Sendable, Codable, CaseIterable {
    case sony, fujifilm, canon, nikon, ricoh, demo
}

public struct DriverCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let halfPress = DriverCapabilities(rawValue: 1 << 0)
    public static let bulb = DriverCapabilities(rawValue: 1 << 1)
    public static let bulbAsTime = DriverCapabilities(rawValue: 1 << 2)
    public static let movie = DriverCapabilities(rawValue: 1 << 3)
    public static let geotag = DriverCapabilities(rawValue: 1 << 4)
    public static let geotagPull = DriverCapabilities(rawValue: 1 << 5)
    public static let clockSync = DriverCapabilities(rawValue: 1 << 6)
    public static let backgroundShooting = DriverCapabilities(rawValue: 1 << 7)
    /// Camera-side timer (Ricoh 2 s flavour); not part of the gesture model.
    public static let cameraSelfTimer = DriverCapabilities(rawValue: 1 << 8)
    public static let ackFocus = DriverCapabilities(rawValue: 1 << 9)
    public static let ackShutter = DriverCapabilities(rawValue: 1 << 10)
    public static let ackLocation = DriverCapabilities(rawValue: 1 << 11)
}

/// What a scan learned about a camera from its advertisement.
public struct CameraMatch: Hashable, Sendable {
    public let driverID: String
    /// Name to show before pairing (the advertised local name, or the model).
    public let displayName: String
    /// Brand model code from the advertisement, for pairing instructions and quirks.
    public let modelCode: String?
    /// The camera is in its pairing menu now.
    public let isPairable: Bool
    /// Brand-specific flags worth logging for the support table.
    public let details: [String: String]

    public init(driverID: String, displayName: String, modelCode: String?, isPairable: Bool,
                details: [String: String] = [:]) {
        self.driverID = driverID
        self.displayName = displayName
        self.modelCode = modelCode
        self.isPairable = isPairable
        self.details = details
    }
}

/// Progress shown on the Pairing screen.
public enum PairingStep: Hashable, Sendable {
    case connecting
    /// Waiting for the user to confirm the system dialog and the camera.
    case bonding
    case registering
    case done
}

/// The physical buttons the protocols model. Named `CameraButton` so it does
/// not clash with SwiftUI's `Button` in app code.
public enum CameraButton: Hashable, Sendable {
    /// Half-press.
    case focus
    /// Full press.
    case shutter
    case movie
}

public enum PressOutcome: Hashable, Sendable {
    case sent
    /// The brand has no such button (e.g. no half-press).
    case unsupported
}

/// Decoded camera notifications.
public enum CameraEvent: Hashable, Sendable {
    case focusAcquired
    case focusLost
    case shutterActive
    case shutterReady
    case recording(Bool)
    /// Brand capture status (Ricoh), raw.
    case captureStatus(Data)
    case cardStatus(Data)
    case battery(Data)
    /// The camera asks for a location now (Fujifilm pull model).
    case locationRequested
    /// The camera reports its location link on or off (Sony `DD01`).
    case locationEnabled(Bool)
    /// A notification the driver does not decode; logged for the support table.
    case unknown(characteristic: GATTCharacteristicID, value: Data)
}

/// Driver-level errors the UI has copy for (product spec § States & errors).
public enum CameraError: Error, Hashable, Sendable {
    /// Sony `FF01` write error `0x90`: *Bluetooth Rmt Ctrl* is Off.
    case remoteControlOff
    /// The camera is linked to another device or the maker's app (Sony `0x9F`).
    case busy
    /// The camera's location link setting is off (Sony `0x9D`).
    case locationLinkOff
    /// The brand or body has no such feature.
    case unsupported
    /// The camera no longer knows us; pair again.
    case pairAgain
    /// The user declined the pairing on the camera, or did not answer in
    /// time (Canon Smartphone `0x03`, Nikon handshake).
    case pairingRejected
    /// A characteristic the driver needs is missing (firmware changed?).
    case missingCharacteristic(GATTCharacteristicID)
    case transport(GATTError)
}

/// Our identity as seen by cameras (architecture doc § Key abstractions). Generated once
/// per device and kept in Keychain, never synchronised.
public struct ClientIdentity: Hashable, Sendable, Codable {
    /// `xGRC-xxxxx`.
    public let name: String
    public let uuid: UUID

    public init(name: String, uuid: UUID) {
        self.name = name
        self.uuid = uuid
    }

    public static func generate() -> ClientIdentity {
        let uuid = UUID()
        let suffix = uuid.uuidString.replacingOccurrences(of: "-", with: "").suffix(5).lowercased()
        return ClientIdentity(name: "xGRC-\(suffix)", uuid: uuid)
    }
}

/// Per-camera identity a driver needs to reconnect, returned by `pair()`.
/// Sony and Canon need nothing beyond the bond; Fujifilm stores a token or
/// serial, Nikon device and nonce IDs.
public struct CameraIdentity: Hashable, Sendable, Codable {
    public var values: [String: Data]

    public init(values: [String: Data] = [:]) {
        self.values = values
    }

    public static let bondOnly = CameraIdentity()
}
