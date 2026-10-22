import BLEKit
import Foundation

/// GATT layout of Sony α / ZV / RX / FX bodies (protocol reference § Bluetooth protocol
/// reference › Sony). Services are 128-bit; characteristics are 16-bit.
public enum Sony {
    public static let companyID: UInt16 = 0x012D

    public static let remoteService = UUID(uuidString: "8000FF00-FF00-FFFF-FFFF-FFFFFFFFFFFF")!
    public static let statusService = UUID(uuidString: "8000CC00-CC00-FFFF-FFFF-FFFFFFFFFFFF")!
    public static let locationService = UUID(uuidString: "8000DD00-DD00-FFFF-FFFF-FFFFFFFFFFFF")!
    public static let pairingService = UUID(uuidString: "8000EE00-EE00-FFFF-FFFF-FFFFFFFFFFFF")!

    /// Remote commands, write with response. Error `0x90` = Bluetooth Rmt Ctrl Off.
    public static let ff01 = GATTCharacteristicID(service: remoteService, characteristic: .bluetooth(0xFF01))
    /// Remote status notifications: focus and shutter acknowledgements.
    public static let ff02 = GATTCharacteristicID(service: remoteService, characteristic: .bluetooth(0xFF02))
    /// TLV camera info (tag `0x0003` = remote control available). Read and logged.
    public static let cc09 = GATTCharacteristicID(service: statusService, characteristic: .bluetooth(0xCC09))
    /// App-level pairing registration, written once on first pairing.
    public static let ee01 = GATTCharacteristicID(service: pairingService, characteristic: .bluetooth(0xEE01))
    /// Auto-power-off avoidance, `03 08 10 00` every 9 s (keeps the screen on).
    public static let cc02 = GATTCharacteristicID(service: statusService, characteristic: .bluetooth(0xCC02))
    /// Location link advisory notifications (last byte 1 = sync on).
    public static let dd01 = GATTCharacteristicID(service: locationService, characteristic: .bluetooth(0xDD01))
    /// Location packet, write with response.
    public static let dd11 = GATTCharacteristicID(service: locationService, characteristic: .bluetooth(0xDD11))
    /// Location features; picks the 91- or 95-byte packet.
    public static let dd21 = GATTCharacteristicID(service: locationService, characteristic: .bluetooth(0xDD21))
    /// Location lock (newer firmware only).
    public static let dd30 = GATTCharacteristicID(service: locationService, characteristic: .bluetooth(0xDD30))
    /// Location enable (newer firmware only).
    public static let dd31 = GATTCharacteristicID(service: locationService, characteristic: .bluetooth(0xDD31))

    /// `CC02` keep-alive value, from SonyGpsApp.
    public static let keepAliveValue = Data([0x03, 0x08, 0x10, 0x00])

    /// The registration packet from the Creators' App iOS binary.
    public static let registration = Data([0x06, 0x08, 0x01, 0x00, 0x00, 0x00, 0x00])

    /// `FF01` command bytes: length `0x01`, then the code.
    public enum Command {
        public static let halfDown = Data([0x01, 0x07])
        public static let halfUp = Data([0x01, 0x06])
        public static let fullDown = Data([0x01, 0x09])
        public static let fullUp = Data([0x01, 0x08])
        public static let recordDown = Data([0x01, 0x0F])
        public static let recordUp = Data([0x01, 0x0E])
    }

    /// `FF02` notifications.
    public enum Status {
        public static let focusLost = Data([0x02, 0x3F, 0x00])
        public static let focusAcquired = Data([0x02, 0x3F, 0x20])
        public static let shutterReady = Data([0x02, 0xA0, 0x00])
        public static let shutterActive = Data([0x02, 0xA0, 0x20])
        public static let recordingStopped = Data([0x02, 0xD5, 0x00])
        public static let recordingStarted = Data([0x02, 0xD5, 0x20])
    }

    /// ATT errors with a defined meaning.
    public enum ATT {
        public static let remoteControlOff: UInt8 = 0x90
        public static let locationLinkOff: UInt8 = 0x9D
        public static let lockedByAnotherDevice: UInt8 = 0x9F
    }

    /// Decoded manufacturer data (protocol reference § Sony › Advertisement).
    public struct AdvertisementInfo: Hashable, Sendable {
        /// `0x64` older firmware, `0x65` newer. Logged only, never gated on.
        public let protocolVersion: UInt8
        /// Model code, hex as it appears on air.
        public let modelCode: String
        /// Byte 9.
        public let modeFlags: UInt8

        public var pairingSupported: Bool { modeFlags & 0x80 != 0 }
        public var pairingEnabled: Bool { modeFlags & 0x40 != 0 }
        public var locationSupported: Bool { modeFlags & 0x20 != 0 }
        public var locationEnabled: Bool { modeFlags & 0x10 != 0 }
        /// Shown as pairable when bits 7 and 6 are set; the disputed low bits
        /// are never used to filter.
        public var isPairable: Bool { pairingSupported && pairingEnabled }

        /// `nil` unless the data is a Sony camera advertisement: company
        /// `0x012D` (little-endian), device type `0x0003`, tag `0x22` at offset 8.
        public init?(manufacturerData d: Data) {
            let b = [UInt8](d)
            guard b.count >= 10,
                  b[0] == 0x2D, b[1] == 0x01,
                  b[2] == 0x03, b[3] == 0x00,
                  b[8] == 0x22
            else { return nil }
            protocolVersion = b[4]
            modelCode = String(format: "%02X%02X", b[6], b[7])
            modeFlags = b[9]
        }
    }

    /// Which `DD11` packet the body takes, from `DD21` (protocol reference § Sony › Location link).
    public enum LocationProfile: Hashable, Sendable {
        /// 95 bytes, with standard UTC offset and DST.
        case withTimeZone
        /// 91 bytes; any `DD21` value that is not a 6–7-byte value with byte 4 bit `0x02`.
        case basic

        public init(features: Data) {
            let b = [UInt8](features)
            if (6...7).contains(b.count), b[4] & 0x02 != 0 {
                self = .withTimeZone
            } else {
                self = .basic
            }
        }

        public var packetLength: Int { self == .withTimeZone ? 95 : 91 }
    }

    /// The `DD11` packet (big-endian). Coordinates are × 10⁷, rounded to the
    /// nearest integer; date and time are UTC; the 95-byte form appends the
    /// standard offset (excluding DST) and the DST in effect, in minutes.
    public static func locationPacket(_ fix: GeoFix, time: Date, zone: TimeZone,
                                      profile: LocationProfile) -> Data {
        var p = [UInt8](repeating: 0, count: profile.packetLength)
        let payload = UInt16(profile.packetLength - 2)
        p[0] = UInt8(payload >> 8)
        p[1] = UInt8(payload & 0xFF)
        p[2] = 0x08; p[3] = 0x02; p[4] = 0xFC
        p[5] = profile == .withTimeZone ? 0x03 : 0x00
        p[6] = 0x00; p[7] = 0x00; p[8] = 0x10; p[9] = 0x10; p[10] = 0x10
        put(Int32(clamping: Int64((fix.latitude * 1e7).rounded())), at: 11, in: &p)
        put(Int32(clamping: Int64((fix.longitude * 1e7).rounded())), at: 15, in: &p)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: time)
        let year = UInt16(c.year ?? 2000)
        p[19] = UInt8(year >> 8)
        p[20] = UInt8(year & 0xFF)
        p[21] = UInt8(c.month ?? 1)
        p[22] = UInt8(c.day ?? 1)
        p[23] = UInt8(c.hour ?? 0)
        p[24] = UInt8(c.minute ?? 0)
        p[25] = UInt8(c.second ?? 0)

        if profile == .withTimeZone {
            let dst = Int(zone.daylightSavingTimeOffset(for: time))
            let standard = zone.secondsFromGMT(for: time) - dst
            put(Int16(clamping: standard / 60), at: 91, in: &p)
            put(Int16(clamping: dst / 60), at: 93, in: &p)
        }
        return Data(p)
    }

    private static func put<T: FixedWidthInteger>(_ value: T, at offset: Int, in bytes: inout [UInt8]) {
        withUnsafeBytes(of: value.bigEndian) { raw in
            for (i, byte) in raw.enumerated() { bytes[offset + i] = byte }
        }
    }

    /// Decodes a `DD01` advisory: last byte 1 = location sync on.
    public static func decode(locationAdvisory value: Data) -> CameraEvent {
        guard let last = value.last, value.count >= 2 else { return .unknown(characteristic: dd01, value: value) }
        return .locationEnabled(last == 0x01)
    }

    /// Decodes an `FF02` notification by its code (byte 1) and the state bit
    /// `0x20` of byte 2, so other bits in byte 2 or a longer value still
    /// decode (alpharemote reads it the same way).
    public static func decode(status value: Data) -> CameraEvent {
        let b = [UInt8](value)
        guard b.count >= 3 else { return .unknown(characteristic: ff02, value: value) }
        let on = b[2] & 0x20 != 0
        switch b[1] {
        case 0x3F: return on ? .focusAcquired : .focusLost
        case 0xA0: return on ? .shutterActive : .shutterReady
        case 0xD5: return .recording(on)
        default: return .unknown(characteristic: ff02, value: value)
        }
    }
}

/// Sony driver. Shot order half-down, full-down, full-up, half-up, confirmed
/// by `FF02` (alpharemote, CameraSync, GeoShutter; furble's lock path).
/// Bulb toggles: with a Bluetooth remote the camera opens the shutter on one
/// press and closes it on the next (Sony help guides; alpharemote).
/// Location link: `DD01` advisory, `DD21` profile, `DD30`/`DD31` lock and
/// enable where present, `DD11` packets (Phase 2).
public actor SonyDriver: CameraDriver {
    public static let descriptor = DriverDescriptor(
        id: "sony",
        brand: .sony,
        displayName: "Sony",
        capabilities: [.halfPress, .bulb, .movie, .geotag, .clockSync, .ackFocus, .ackShutter, .backgroundShooting],
        ackSource: "FF02 notify"
    )

    public static var serviceUUIDs: [UUID] { [Sony.remoteService, Sony.locationService] }

    public static func matches(_ advertisement: Advertisement) -> CameraMatch? {
        guard let data = advertisement.manufacturerData,
              let info = Sony.AdvertisementInfo(manufacturerData: data) else { return nil }
        return CameraMatch(
            driverID: descriptor.id,
            displayName: advertisement.localName ?? "Sony \(info.modelCode)",
            modelCode: info.modelCode,
            isPairable: info.isPairable,
            details: [
                "protocolVersion": String(format: "0x%02X", info.protocolVersion),
                "modeFlags": String(format: "0x%02X", info.modeFlags),
                "locationEnabled": String(info.locationEnabled),
            ]
        )
    }

    /// The bonding dialog can stay up while the user confirms on the camera.
    static let bondingWindow: Duration = .seconds(60)
    static let writeTimeout: Duration = .seconds(5)

    private let transport: any GATTTransport
    private let broadcaster = Broadcaster<CameraEvent>()
    private var pump: Task<Void, Never>?
    private var locationPump: Task<Void, Never>?
    private var writeTail: Task<Void, Never>?
    private var services: [GATTService] = []
    /// Set while the location link is enabled; `reconnect` re-enables it.
    private var locationProfile: Sony.LocationProfile?
    /// We took the `DD30` lock on this connection. Tracked apart from the
    /// profile so a start that fails after the lock still releases it.
    private var holdsLocationLock = false
    /// Geotagging is on for this session: every reconnect enables the
    /// location link again, also after a re-enable that failed.
    private var wantsLocationLink = false
    /// `false` in a geotag-only session: the camera's *Bluetooth Rmt Ctrl*
    /// may be off (pre-α7 IV bodies need it off to geotag), so the remote
    /// service is optional.
    private var usesRemote = true

    public func setFeatures(remote: Bool, geotag: Bool) {
        usesRemote = remote
    }

    public init(transport: any GATTTransport) {
        self.transport = transport
    }

    public nonisolated var shotScript: ShotScript { Self.script }

    public nonisolated func events() -> AsyncStream<CameraEvent> {
        broadcaster.stream()
    }

    static let script: ShotScript = {
        let halfDown = ShotStep.write(ShotWrite(Sony.Command.halfDown, to: Sony.ff01))
        let halfUp = ShotStep.write(ShotWrite(Sony.Command.halfUp, to: Sony.ff01))
        let fullDown = ShotStep.write(ShotWrite(Sony.Command.fullDown, to: Sony.ff01, firesShutter: true))
        let fullUp = ShotStep.write(ShotWrite(Sony.Command.fullUp, to: Sony.ff01))
        let shutterAck = ShotStep.awaitAck(.shutter, timeout: .seconds(3), optional: false)
        // The press that closes a bulb; not counted as a shot.
        let closeDown = ShotStep.write(ShotWrite(Sony.Command.fullDown, to: Sony.ff01))
        return ShotScript(
            focusSupported: true,
            focusPress: [halfDown],
            focusRelease: [halfUp],
            shootFromFocus: [fullDown, shutterAck, fullUp],
            shootWithoutFocus: [halfDown, .awaitAck(.focus, timeout: .seconds(2), optional: true),
                                fullDown, shutterAck, fullUp, halfUp],
            // Bulb with a Bluetooth remote is a toggle: press and release to
            // open (held until the shutter ack, as the camera may still be
            // focusing), press and release again to close. Releasing a held
            // press does not close it.
            latch: [fullDown, shutterAck, fullUp, halfUp],
            unlatch: [halfDown, closeDown, fullUp, halfUp],
            releaseAll: [fullUp, halfUp],
            minimumWriteGap: .zero,
            unlatchToggles: true
        )
    }()

    // MARK: Pairing and reconnect

    public func pair(_ advertisement: Advertisement, client: ClientIdentity,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity {
        let services = try await discover()
        let pairable = advertisement.manufacturerData
            .flatMap(Sony.AdvertisementInfo.init(manufacturerData:))?.isPairable ?? false

        // The first protected access raises the system pairing dialog while
        // the camera is in its pairing menu.
        progress(.bonding)
        try await startRemoteEvents(timeout: Self.bondingWindow)

        // EE01 exactly once, on the first connection, only while the camera
        // advertises pairing mode; outside pairing mode it disconnects us.
        if pairable, services.contains(Sony.ee01) {
            progress(.registering)
            let transport = self.transport
            try await Self.mapErrors {
                try await withTimeout(Self.bondingWindow) {
                    try await transport.write(Sony.registration, to: Sony.ee01)
                }
            }
        }
        await logCameraInfo(services)
        progress(.done)
        return .bondOnly
    }

    public func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws {
        let services = try await discover()
        try await startRemoteEvents(timeout: Self.writeTimeout)
        await logCameraInfo(services)
        if wantsLocationLink {
            // A location failure must not take the remote down with it; the
            // Geotag page shows the camera's location link as off instead.
            do {
                _ = try await startLocationLink()
            } catch {
                broadcaster.yield(.locationEnabled(false))
            }
        }
    }

    public func disconnect() async {
        for step in Self.script.releaseAll {
            if case .write(let write) = step { try? await send(write) }
        }
        await stopLocationLink()
        pump?.cancel()
        pump = nil
        await transport.disconnect()
    }

    // MARK: Location link

    public nonisolated var geotagRules: GeotagRules {
        // Sony's own app stops trusting a fix after 10 s (SonyGpsApp).
        GeotagRules(maximumFixAge: .seconds(10), minimumInterval: .seconds(1), stampsSendTime: true)
    }

    public nonisolated var keepAlive: KeepAlivePolicy? {
        KeepAlivePolicy(interval: .seconds(9), write: ShotWrite(Sony.keepAliveValue, to: Sony.cc02))
    }

    public func startLocationLink() async throws -> LocationLinkMode {
        do {
            let mode = try await enableLocationLink()
            wantsLocationLink = true
            return mode
        } catch {
            await releaseLocationLink()
            throw error
        }
    }

    private func enableLocationLink() async throws -> LocationLinkMode {
        if services.isEmpty { services = try await discover() }
        guard services.contains(Sony.dd11) else { throw CameraError.unsupported }
        let transport = self.transport

        if services.contains(Sony.dd01) {
            locationPump?.cancel()
            let stream = try await Self.mapErrors {
                try await withTimeout(Self.writeTimeout) { try await transport.subscribe(Sony.dd01) }
            }
            let broadcaster = self.broadcaster
            locationPump = Task {
                do {
                    for try await value in stream { broadcaster.yield(Sony.decode(locationAdvisory: value)) }
                } catch {}
            }
        }

        var profile = Sony.LocationProfile.basic
        if services.contains(Sony.dd21) {
            let features = try await Self.mapErrors {
                try await withTimeout(Self.writeTimeout) { try await transport.read(Sony.dd21) }
            }
            profile = Sony.LocationProfile(features: features)
        }
        // The single-packet limit is the without-response length (with a
        // response, iOS reports 512 and splits into a long write). A shorter
        // one is not refused: the packet goes as a long write, and the
        // transcript logs the length next to the DD11 writes.
        _ = await transport.maximumWriteLength(withResponse: false)

        // Newer firmware: take the lock, then enable. Written only when not
        // already 0x01, as furble does.
        for chr in [Sony.dd30, Sony.dd31] where services.contains(chr) {
            let current = try? await withTimeout(Self.writeTimeout) { try await transport.read(chr) }
            if current != Data([0x01]) {
                try await send(ShotWrite(Data([0x01]), to: chr))
            }
            if chr == Sony.dd30 { holdsLocationLock = true }
        }
        locationProfile = profile
        return .push
    }

    public func stopLocationLink() async {
        wantsLocationLink = false
        guard locationProfile != nil || holdsLocationLock else { return }
        await releaseLocationLink()
    }

    /// Enable off, then lock off, so another phone or watch can take it.
    private func releaseLocationLink() async {
        let wasEnabled = locationProfile != nil || holdsLocationLock
        locationProfile = nil
        holdsLocationLock = false
        locationPump?.cancel()
        locationPump = nil
        guard wasEnabled else { return }
        for chr in [Sony.dd31, Sony.dd30] where services.contains(chr) {
            try? await send(ShotWrite(Data([0x00]), to: chr))
        }
    }

    /// The `DD11` packet carries the time; the camera sets its clock from it
    /// when its own auto-time setting (`DD32`) is on.
    public func syncClock(_ time: Date, zone: TimeZone) async throws {}

    public func updateLocation(_ fix: GeoFix, time: Date, zone: TimeZone) async throws {
        guard let profile = locationProfile else { throw CameraError.unsupported }
        try await send(ShotWrite(Sony.locationPacket(fix, time: time, zone: zone, profile: profile), to: Sony.dd11))
    }

    // MARK: Buttons

    public func press(_ button: CameraButton) async throws -> PressOutcome {
        switch button {
        case .focus: try await send(ShotWrite(Sony.Command.halfDown, to: Sony.ff01))
        case .shutter: try await send(ShotWrite(Sony.Command.fullDown, to: Sony.ff01, firesShutter: true))
        case .movie: try await send(ShotWrite(Sony.Command.recordDown, to: Sony.ff01))
        }
        return .sent
    }

    public func release(_ button: CameraButton) async throws {
        switch button {
        case .focus: try await send(ShotWrite(Sony.Command.halfUp, to: Sony.ff01))
        case .shutter: try await send(ShotWrite(Sony.Command.fullUp, to: Sony.ff01))
        case .movie: try await send(ShotWrite(Sony.Command.recordUp, to: Sony.ff01))
        }
    }

    /// Writes are chained so a release from a cancel never overtakes a shot in flight.
    public func send(_ write: ShotWrite) async throws {
        let previous = writeTail
        let transport = self.transport
        let operation = Task { () -> Result<Void, Error> in
            await previous?.value
            do {
                try await Self.mapErrors {
                    try await withTimeout(Self.writeTimeout) {
                        if write.withResponse {
                            try await transport.write(write.data, to: write.characteristic)
                        } else {
                            try await transport.writeWithoutResponse(write.data, to: write.characteristic)
                        }
                    }
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        writeTail = Task { _ = await operation.value }
        try await operation.value.get()
    }

    // MARK: Private

    private func discover() async throws -> [GATTService] {
        let transport = self.transport
        let services = try await Self.mapErrors {
            try await withTimeout(.seconds(10)) {
                try await transport.discover(services: [Sony.remoteService, Sony.statusService,
                                                        Sony.locationService, Sony.pairingService])
            }
        }
        let required = usesRemote ? [Sony.ff01, Sony.ff02] : [Sony.dd11]
        for chr in required where !services.contains(chr) {
            throw CameraError.missingCharacteristic(chr)
        }
        self.services = services
        return services
    }

    /// `FF02` events. In a geotag-only session a missing or refused remote
    /// service is not an error; losing the bond still is.
    private func startRemoteEvents(timeout: Duration) async throws {
        do {
            try await startEvents(timeout: timeout)
        } catch let error where !usesRemote {
            switch error {
            case CameraError.pairAgain, CameraError.transport(.insufficientAuthentication),
                 CameraError.transport(.disconnected), CameraError.transport(.timeout):
                throw error
            default:
                break
            }
        }
    }

    private func startEvents(timeout: Duration) async throws {
        pump?.cancel()
        let transport = self.transport
        let stream = try await Self.mapErrors {
            try await withTimeout(timeout) { try await transport.subscribe(Sony.ff02) }
        }
        let broadcaster = self.broadcaster
        pump = Task {
            do {
                for try await value in stream {
                    broadcaster.yield(Sony.decode(status: value))
                }
            } catch {
                // Link lost; the session reconnects and calls `reconnect`.
            }
        }
    }

    private func logCameraInfo(_ services: [GATTService]) async {
        guard services.contains(Sony.cc09) else { return }
        let transport = self.transport
        _ = try? await withTimeout(Self.writeTimeout) { try await transport.read(Sony.cc09) }
    }

    static func mapErrors<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as GATTError {
            switch error {
            case .att(Sony.ATT.remoteControlOff): throw CameraError.remoteControlOff
            case .att(Sony.ATT.lockedByAnotherDevice): throw CameraError.busy
            case .att(Sony.ATT.locationLinkOff): throw CameraError.locationLinkOff
            case .peerRemovedPairing: throw CameraError.pairAgain
            default: throw CameraError.transport(error)
            }
        }
    }
}
