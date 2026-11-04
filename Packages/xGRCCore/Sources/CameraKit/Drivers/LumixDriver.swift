import BLEKit
import Foundation

/// GATT layout of Panasonic LUMIX bodies (protocol reference § Bluetooth protocol
/// reference › Panasonic LUMIX). Ported from furble's `Lumix.cpp` (MIT,
/// gkoh/furble PR #282, from S5II and BGH1 traces), cross-checked against
/// tobiasbrummer/lux-lat-long-log (S5, MIT; handshake and GPS verified on a
/// real camera) and Aikhjarto/LUMIX-G9II-Remote-Control (G9II command bytes).
/// Every UUID ends in the Panasonic suffix shown below, except the remote
/// control service.
public enum Lumix {
    private static func chr(_ service: UUID, _ uuid: String) -> GATTCharacteristicID {
        GATTCharacteristicID(service: service, characteristic: UUID(uuidString: uuid)!)
    }

    /// Bluetooth SIG company ID of Panasonic, first in the manufacturer data.
    public static let companyID: UInt16 = 0x003A

    /// Advertised by the camera; holds the session handshake.
    public static let sessionService = UUID(uuidString: "054AC620-3214-11E6-AC0D-0002A5D5C51B")!
    /// Write `MEI0` here first on every connect.
    public static let sessionInit = chr(sessionService, "8D08A420-3213-11E6-8ACA-0002A5D5C51B")
    /// Then our name, ASCII.
    public static let deviceName = chr(sessionService, "CD7A71A0-3213-11E6-8F56-0002A5D5C51B")

    public static let controlService = UUID(uuidString: "7BE5FAAE-475B-11E7-A919-92EBCB67FE33")!
    /// One command byte per button change.
    public static let control = chr(controlService, "7BE5FD56-475B-11E7-A919-92EBCB67FE33")

    public static let locationService = UUID(uuidString: "1D74AFE0-3214-11E6-8AB4-0002A5D5C51B")!
    /// The 16-byte GPS packet.
    public static let location = chr(locationService, "DAFF1BC0-3216-11E6-91C8-0002A5D5C51B")
    /// Notifies `01` once the camera takes locations (lux-lat-long-log).
    public static let locationReady = chr(locationService, "37701B80-32A7-11E6-BB83-0002A5D5C51B")

    public static let clockService = UUID(uuidString: "34738720-3214-11E6-B66B-0002A5D5C51B")!
    /// The 10-byte clock packet.
    public static let clock = chr(clockService, "EAD55E60-3216-11E6-A42E-0002A5D5C51B")
    /// Notifies `01` once the camera takes the clock.
    public static let clockReady = chr(clockService, "4CF487C0-32A7-11E6-A50D-0002A5D5C51B")

    /// The session handshake furble sends: magic `MEI0`, fixed flags, then a
    /// session counter and a check value the camera does not verify
    /// (lux-lat-long-log replays one fixed packet across reconnects).
    public static let mei0 = Data([0x4D, 0x45, 0x49, 0x30, 0x01, 0x00, 0x10, 0x00,
                                   0x80, 0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x00])

    public enum Command {
        public static let focusPress = Data([0x01])
        public static let focusRelease = Data([0x02])
        public static let shutterPress = Data([0x04])
        public static let shutterRelease = Data([0x05])
    }

    /// Seconds from the Unix epoch to the GPS epoch, 1980-01-06.
    static let gpsEpochOffset: Int64 = 315_964_800

    /// The 16-byte GPS packet, little-endian: GPS-epoch seconds (UTC, no leap
    /// seconds), latitude and longitude × 10⁷ as Int32, altitude in whole
    /// metres as UInt16 (below sea level is sent as 0), `'A'` (valid fix), `00`.
    public static func gpsPacket(_ fix: GeoFix, time: Date) -> Data {
        var p: [UInt8] = []
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { p.append(contentsOf: $0) }
        }
        let seconds = Int64(time.timeIntervalSince1970.rounded(.down)) - gpsEpochOffset
        put(UInt32(clamping: seconds))
        put(Int32(clamping: Int64((fix.latitude * 10_000_000).rounded())))
        put(Int32(clamping: Int64((fix.longitude * 10_000_000).rounded())))
        let altitude = (fix.altitude ?? 0).rounded()
        put(UInt16(clamping: altitude.isFinite ? Int64(altitude) : 0))
        p += [0x41, 0x00]
        return Data(p)
    }

    /// The 10-byte clock packet as lux-lat-long-log sends it to an S5: year
    /// (UInt16 LE), month, day, hour, minute, second in UTC, then the zone's
    /// standard offset in minutes (Int16 LE) and a daylight-saving flag. In
    /// Central European summer time the tail is `3c 00 01`, the bytes the
    /// LUMIX app sent in that trace.
    public static func clockPacket(_ time: Date, zone: TimeZone) -> Data {
        let c = utcComponents(time)
        var p: [UInt8] = []
        withUnsafeBytes(of: UInt16(c.year ?? 2000).littleEndian) { p.append(contentsOf: $0) }
        p += [UInt8(c.month ?? 1), UInt8(c.day ?? 1), UInt8(c.hour ?? 0), UInt8(c.minute ?? 0),
              UInt8(c.second ?? 0)]
        let daylight = zone.daylightSavingTimeOffset(for: time)
        let standardMinutes = (zone.secondsFromGMT(for: time) - Int(daylight)) / 60
        withUnsafeBytes(of: Int16(clamping: standardMinutes).littleEndian) { p.append(contentsOf: $0) }
        p.append(daylight != 0 ? 0x01 : 0x00)
        return Data(p)
    }
}

/// Panasonic LUMIX, ported from furble's untested driver. A half-press and a
/// full press with separate releases; no shot acknowledgement is decoded, so
/// shots are timed presses reported as *assumed*. Locations are pushed. The
/// camera does not bond: the `MEI0` handshake and our name run on every
/// connect, then (geotag sessions only) the camera clock is set once both
/// ready notifications arrive, as the LUMIX app does. Everything here waits
/// for the device test pass.
public actor LumixDriver: CameraDriver {
    public static let descriptor = DriverDescriptor(
        id: "lumix",
        brand: .panasonic,
        displayName: "Panasonic LUMIX",
        capabilities: [.halfPress, .bulb, .geotag, .clockSync, .backgroundShooting],
        ackSource: "none decoded (timed press)"
    )

    public static var serviceUUIDs: [UUID] { [Lumix.sessionService, Lumix.locationService] }

    /// furble matches Panasonic manufacturer data plus the session service;
    /// lux-lat-long-log matches the location service. Either service is enough.
    public static func matches(_ advertisement: Advertisement) -> CameraMatch? {
        let services = [Lumix.sessionService, Lumix.locationService]
        guard advertisement.serviceUUIDs.contains(where: { services.contains($0) }) else { return nil }
        var details: [String: String] = [:]
        if let data = advertisement.manufacturerData, data.count >= 3,
           UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8 == Lumix.companyID {
            details["flags"] = Data([data[data.startIndex + 2]]).hexString
        }
        return CameraMatch(driverID: descriptor.id, displayName: advertisement.localName ?? "LUMIX",
                           modelCode: nil, isPairable: true, details: details)
    }

    static let pressHold: Duration = .milliseconds(100)
    static let focusSettle: Duration = .milliseconds(250)

    private let link: DriverLink
    /// How long a connect waits for the ready notifications before going on.
    private let readyWindow: Duration
    private var usesRemote = true
    private var usesGeotag = true
    private var locationActive = false
    private var locationReady = false
    private var clockReady = false

    public init(transport: any GATTTransport) {
        self.init(transport: transport, readyWindow: .seconds(3))
    }

    init(transport: any GATTTransport, readyWindow: Duration) {
        link = DriverLink(transport: transport, adaptiveWrites: true)
        self.readyWindow = readyWindow
    }

    public func setFeatures(remote: Bool, geotag: Bool) {
        usesRemote = remote
        usesGeotag = geotag
    }

    public nonisolated var shotScript: ShotScript { Self.script }

    public nonisolated func events() -> AsyncStream<CameraEvent> {
        link.events.stream()
    }

    static let script: ShotScript = {
        func write(_ data: Data, fires: Bool = false) -> ShotStep {
            .write(ShotWrite(data, to: Lumix.control, firesShutter: fires))
        }
        let focus = write(Lumix.Command.focusPress)
        let unfocus = write(Lumix.Command.focusRelease)
        let full = write(Lumix.Command.shutterPress, fires: true)
        let up = write(Lumix.Command.shutterRelease)
        let shot: [ShotStep] = [full, .hold(pressHold), up]
        return ShotScript(focusSupported: true, focusPress: [focus], focusRelease: [unfocus],
                          shootFromFocus: shot, shootWithoutFocus: shot, latch: [full], unlatch: [up, unfocus],
                          releaseAll: [up, unfocus], minimumWriteGap: .zero,
                          acknowledgesFocus: false, focusSettle: focusSettle)
    }()

    // MARK: Pairing and reconnect

    /// No bond is expected (lux-lat-long-log saw no SMP on an S5), but the
    /// first write gets the bonding window in case a body asks for one, and
    /// the user is told to keep the camera on its pairing screen.
    public func pair(_ advertisement: Advertisement, client: ClientIdentity,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity {
        progress(.bonding)
        try await connect(client, window: DriverLink.bondingWindow)
        progress(.done)
        return .bondOnly
    }

    public func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws {
        try await connect(client, window: DriverLink.writeTimeout)
    }

    public func disconnect() async {
        for write in Self.script.releaseAllWrites { try? await send(write) }
        locationActive = false
        await link.disconnect()
    }

    /// Ready subscriptions, `MEI0`, our name, the wait for both ready
    /// notifications, then the clock. A shortened sequence (`MEI0` straight
    /// to GPS) made an S5 drop the link.
    private func connect(_ client: ClientIdentity, window: Duration) async throws {
        locationReady = false
        clockReady = false
        try await link.discover([Lumix.sessionService, Lumix.controlService, Lumix.locationService,
                                 Lumix.clockService],
                                required: [Lumix.sessionInit, Lumix.deviceName]
                                    + (usesRemote ? [Lumix.control] : [Lumix.location]))
        for chr in [Lumix.locationReady, Lumix.clockReady] {
            guard await link.has(chr) else { continue }
            try? await link.subscribe(chr, handler: { [weak self] value in
                await self?.ready(chr, value)
            })
        }
        try await link.write(Lumix.mei0, to: Lumix.sessionInit, timeout: window)
        try await link.write(Data(client.name.utf8), to: Lumix.deviceName)
        let deadline = ContinuousClock.now.advanced(by: readyWindow)
        while !(locationReady && clockReady), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        if usesGeotag, await link.has(Lumix.clock) {
            try? await syncClock(Date(), zone: .current)
        }
    }

    private func ready(_ chr: GATTCharacteristicID, _ value: Data) {
        if value.first == 0x01 {
            if chr == Lumix.locationReady { locationReady = true } else { clockReady = true }
        }
        // Logged for the support table until a device test decodes other values.
        link.events.yield(.unknown(characteristic: chr, value: value))
    }

    // MARK: Location (push)

    public nonisolated var geotagRules: GeotagRules {
        GeotagRules(maximumFixAge: .seconds(30), minimumInterval: .seconds(1), stampsSendTime: false)
    }

    public func startLocationLink() async throws -> LocationLinkMode {
        guard await link.has(Lumix.location) else { throw CameraError.unsupported }
        locationActive = true
        return .push
    }

    public func stopLocationLink() async {
        locationActive = false
    }

    public func syncClock(_ time: Date, zone: TimeZone) async throws {
        try await link.send(ShotWrite(Lumix.clockPacket(time, zone: zone), to: Lumix.clock))
    }

    public func updateLocation(_ fix: GeoFix, time: Date, zone: TimeZone) async throws {
        guard locationActive else { throw CameraError.unsupported }
        try await link.send(ShotWrite(Lumix.gpsPacket(fix, time: time), to: Lumix.location))
    }

    // MARK: Buttons

    public func press(_ button: CameraButton) async throws -> PressOutcome {
        switch button {
        case .focus: try await send(ShotWrite(Lumix.Command.focusPress, to: Lumix.control))
        case .shutter: try await send(ShotWrite(Lumix.Command.shutterPress, to: Lumix.control, firesShutter: true))
        case .movie: return .unsupported
        }
        return .sent
    }

    public func release(_ button: CameraButton) async throws {
        switch button {
        case .focus: try await send(ShotWrite(Lumix.Command.focusRelease, to: Lumix.control))
        case .shutter: try await send(ShotWrite(Lumix.Command.shutterRelease, to: Lumix.control))
        case .movie: return
        }
    }

    public func send(_ write: ShotWrite) async throws {
        try await link.send(write)
    }
}
