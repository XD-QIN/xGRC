import BLEKit
import Foundation

/// GATT layout of Fujifilm X and GFX bodies (protocol reference § Bluetooth protocol
/// reference › Fujifilm). Full UUIDs from furble's `Fujifilm.h` and
/// `FujifilmSecure.h`; the characteristic `85B9163E` exists in both pairing
/// services, which is why characteristics are keyed by service too.
public enum Fujifilm {
    public static let companyID: UInt16 = 0x04D8

    /// Advertised by legacy-firmware bodies.
    public static let legacyAdvertisedServices = [
        UUID(uuidString: "AF854C2E-B214-458E-97E2-912C4ECF2CB8")!,
        UUID(uuidString: "117C4142-EDD4-4C77-8696-DD18EEBB770A")!,
    ]
    /// Advertised by a secure-firmware body that has no registration yet (pairing).
    public static let unregisteredService = UUID(uuidString: "A9D2B304-E8D6-4902-8336-352B772D7597")!

    public static let legacyPairingService = UUID(uuidString: "91F1DE68-DFF6-466E-8B65-FF13B0F16FB8")!
    /// Also advertised, with the serial, by a registered secure-firmware body.
    public static let securePairingService = UUID(uuidString: "123D8F06-62A1-4935-9322-833C531EE225")!
    public static let stateService = UUID(uuidString: "4C0020FE-F3B6-40DE-ACC9-77D129067B14")!
    public static let settingsService = UUID(uuidString: "4E941240-D01D-46B9-A5EA-67636806830B")!
    public static let geotagService = UUID(uuidString: "3B46EC2B-48BA-41FD-B1B8-ED860B60D22B")!
    public static let shutterService = UUID(uuidString: "6514EB81-4E8F-458D-AA2A-E691336CDFAC")!

    private static func chr(_ service: UUID, _ uuid: String) -> GATTCharacteristicID {
        GATTCharacteristicID(service: service, characteristic: UUID(uuidString: uuid)!)
    }

    /// Legacy: the 4-byte token from the advertisement.
    public static let legacyToken = chr(legacyPairingService, "ABA356EB-9633-4E60-B73F-F52516DBD671")
    public static let legacyName = chr(legacyPairingService, "85B9163E-62D1-49FF-A6F5-054B4630D4A1")
    /// Secure: read 4 bytes, write them back with byte 3 = `0x20`.
    public static let secureStatus = chr(securePairingService, "F557D96B-8284-4667-8793-B971C1DECA2A")
    public static let secureName = chr(securePairingService, "85B9163E-62D1-49FF-A6F5-054B4630D4A1")

    /// Indication (AP state).
    public static let apState = chr(stateService, "A68E3F66-0FCC-4395-8D4C-AA980B5877FA")
    /// Indication (TRANSFER_STATE).
    public static let transferState = chr(stateService, "BD17BA04-B76B-4892-A545-B73BA1F74DAE")
    /// NOT1 = DATE_SYNC_STATE: `01 00` = the camera asks for the time.
    public static let dateSyncState = chr(stateService, "F9150137-5D40-4801-A8DC-F7FC5B01DA50")
    /// The camera asks for a location: `01 00`.
    public static let geotagRequest = chr(stateService, "AD06C7B7-F41A-46F4-A29A-712055319122")
    /// Indication, legacy firmware only.
    public static let legacyIndication = chr(stateService, "049EC406-EF75-4205-A390-08FE209C51F0")
    /// CAMERA_VITAL_STATE.
    public static let vitalState = chr(stateService, "E6692C5C-B7CD-44F4-95FC-EDA07CE32560")

    /// LOCATION_SYNC_CYCLE, uint16 seconds (10, 15, 20, 30, 60, 120, 240, 480).
    public static let locationSyncCycle = chr(settingsService, "C95D91AE-B247-4D6D-8661-7DD5D6A0F85B")
    /// The other settings notifications the official app (and furble) subscribe
    /// to: camera name, an unknown one, LOCATION_SYNC_SETTING, then four more.
    public static let settingsNotifications = [
        chr(settingsService, "BF6DC9CF-3606-4EC9-A4C8-D77576E93EA4"),
        chr(settingsService, "75823784-FBB7-4B71-ABAE-CD9A34072E3C"),
        chr(settingsService, "AAB609C4-94DD-4D89-BC60-665D5090B828"),
        chr(settingsService, "2A125640-706D-4DD1-B420-C0F4AB93C361"),
        chr(settingsService, "82A9F452-C5CE-4EF5-8203-3FC9A47F8171"),
        chr(settingsService, "DEEF7187-3F43-4364-9E22-11A8C8A15951"),
    ]

    /// The 23-byte location answer, write with response.
    public static let geotagPacket = chr(geotagService, "0F36EC14-29E5-411A-A1B6-64EE8383F090")
    /// Shutter: two writes, `01 00` then the parameter.
    public static let shutter = chr(shutterService, "7FCF49C6-4FF0-4777-A03D-1A79166AF7A8")

    /// Shutter commands as one 4-byte value: the command `01 00` and the
    /// parameter. The driver splits each into the camera's two writes.
    public enum Shutter {
        public static let full = Data([0x01, 0x00, 0x02, 0x00])
        public static let half = Data([0x01, 0x00, 0x03, 0x00])
        /// Ends focus and shutter alike.
        public static let release = Data([0x01, 0x00, 0x00, 0x00])
    }

    public static let locationRequest = Data([0x01, 0x00])
    /// furble's interval: the shortest the camera offers.
    public static let syncCycleSeconds: UInt16 = 10

    /// Which pairing the body speaks, from the advertisement's type byte.
    public enum Firmware: Hashable, Sendable {
        /// Type `0x02` with a 4-byte token, reused on every connect.
        case legacy(token: Data)
        /// Type `0x01` with a 5-byte serial (July 2025 firmware and later).
        case secure(serial: Data)
    }

    /// Decodes manufacturer data: company `0x04D8` (little-endian), then the
    /// type byte. Detection is by type byte, never by a model list.
    public static func firmware(manufacturerData d: Data) -> Firmware? {
        let b = [UInt8](d)
        guard b.count >= 3, b[0] == 0xD8, b[1] == 0x04 else { return nil }
        switch (b[2], b.count) {
        case (0x02, 7): return .legacy(token: Data(b[3..<7]))
        case (0x01, 8): return .secure(serial: Data(b[3..<8]))
        default: return nil
        }
    }

    /// The location answer (little-endian): latitude and longitude × 10⁷,
    /// altitude in whole metres, speed (sent as 0), then the UTC date and time.
    public static func locationPacket(_ fix: GeoFix, time: Date) -> Data {
        var p: [UInt8] = []
        func put<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { p.append(contentsOf: $0) }
        }
        put(Int32(clamping: Int64((fix.latitude * 1e7).rounded())))
        put(Int32(clamping: Int64((fix.longitude * 1e7).rounded())))
        put(Int32(clamping: Int64((fix.altitude ?? 0).rounded())))
        put(Int32(0))
        let c = utcComponents(time)
        put(UInt16(c.year ?? 2000))
        p += [UInt8(c.month ?? 1), UInt8(c.day ?? 1), UInt8(c.hour ?? 0), UInt8(c.minute ?? 0), UInt8(c.second ?? 0)]
        return Data(p)
    }

    /// Location requests are `01 00`; everything else is logged undecoded.
    public static func decode(_ value: Data, from chr: GATTCharacteristicID) -> CameraEvent {
        if chr == geotagRequest, value.prefix(2) == locationRequest { return .locationRequested }
        return .unknown(characteristic: chr, value: value)
    }
}

/// Fujifilm driver, legacy and secure firmware. No focus or shutter ack
/// exists (the shutter service is write-only), so every shot is a timed
/// press reported as *assumed*. Geotag is pull: the camera asks with `01 00`
/// every sync cycle and the session answers with one packet. The separate
/// time packet is not sent: its UUIDs are not public yet (Phase 5 doc in Dev_Doc).
public actor FujifilmDriver: CameraDriver {
    public static let descriptor = DriverDescriptor(
        id: "fujifilm",
        brand: .fujifilm,
        displayName: "Fujifilm",
        capabilities: [.halfPress, .bulb, .geotag, .geotagPull, .backgroundShooting],
        ackSource: "none (timed press)"
    )

    public static var serviceUUIDs: [UUID] { [Fujifilm.shutterService, Fujifilm.geotagService] }

    public static func matches(_ advertisement: Advertisement) -> CameraMatch? {
        guard let data = advertisement.manufacturerData,
              let firmware = Fujifilm.firmware(manufacturerData: data) else { return nil }
        let pairable: Bool
        var details: [String: String]
        switch firmware {
        case .legacy(let token):
            pairable = true
            details = ["firmware": "legacy", "token": token.hexString]
        case .secure(let serial):
            // A registered body advertises the pairing service instead.
            pairable = advertisement.serviceUUIDs.contains(Fujifilm.unregisteredService)
            details = ["firmware": "secure", "serial": serial.hexString]
        }
        return CameraMatch(driverID: descriptor.id, displayName: advertisement.localName ?? "Fujifilm",
                           modelCode: nil, isPairable: pairable, details: details)
    }

    /// How long a shot's press is held before the release, with no ack to wait for.
    static let pressHold: Duration = .milliseconds(100)
    /// Half-press to full press when Shoot starts with nothing held.
    static let focusSettle: Duration = .milliseconds(250)

    private let link: DriverLink
    private var usesRemote = true
    private var locationActive = false
    /// Whole UTC second of the last answer; the camera ignores one that is not newer.
    private var lastStamp: Int64?

    public init(transport: any GATTTransport) {
        link = DriverLink(transport: transport)
    }

    public func setFeatures(remote: Bool, geotag: Bool) {
        usesRemote = remote
    }

    public nonisolated var shotScript: ShotScript { Self.script }

    public nonisolated func events() -> AsyncStream<CameraEvent> {
        link.events.stream()
    }

    static let script: ShotScript = {
        let full = ShotStep.write(ShotWrite(Fujifilm.Shutter.full, to: Fujifilm.shutter, firesShutter: true))
        let half = ShotStep.write(ShotWrite(Fujifilm.Shutter.half, to: Fujifilm.shutter))
        let release = ShotStep.write(ShotWrite(Fujifilm.Shutter.release, to: Fujifilm.shutter))
        let shot: [ShotStep] = [full, .hold(pressHold), release]
        return ShotScript(
            focusSupported: true,
            focusPress: [half],
            focusRelease: [release],
            shootFromFocus: shot,
            shootWithoutFocus: shot,
            latch: [full],
            unlatch: [release],
            releaseAll: [release],
            minimumWriteGap: .zero,
            acknowledgesFocus: false,
            focusSettle: focusSettle
        )
    }()

    // MARK: Pairing and reconnect

    public func pair(_ advertisement: Advertisement, client: ClientIdentity,
                     progress: @escaping @Sendable (PairingStep) -> Void) async throws -> CameraIdentity {
        guard let data = advertisement.manufacturerData,
              let firmware = Fujifilm.firmware(manufacturerData: data) else { throw CameraError.unsupported }
        let identity = Self.identity(for: firmware)
        // Secure: the status read raises the system dialog and the code on the
        // camera, which the user confirms within 30 s.
        progress(.bonding)
        try await register(firmware, client: client, window: DriverLink.bondingWindow, progress: progress)
        progress(.done)
        return identity
    }

    /// Registration runs again on every connect, as furble does for both firmwares.
    public func reconnect(identity: CameraIdentity, client: ClientIdentity) async throws {
        guard let firmware = Self.firmware(from: identity) else { throw CameraError.pairAgain }
        try await register(firmware, client: client, window: DriverLink.writeTimeout, progress: { _ in })
    }

    public func disconnect() async {
        // Through `send`, so each 4-byte value goes out as the camera's two writes.
        for write in Self.script.releaseAllWrites { try? await send(write) }
        locationActive = false
        await link.disconnect()
    }

    static func identity(for firmware: Fujifilm.Firmware) -> CameraIdentity {
        switch firmware {
        case .legacy(let token): CameraIdentity(values: ["token": token])
        case .secure(let serial): CameraIdentity(values: ["serial": serial])
        }
    }

    static func firmware(from identity: CameraIdentity) -> Fujifilm.Firmware? {
        if let token = identity.values["token"] { return .legacy(token: token) }
        if let serial = identity.values["serial"] { return .secure(serial: serial) }
        return nil
    }

    private func register(_ firmware: Fujifilm.Firmware, client: ClientIdentity, window: Duration,
                          progress: (PairingStep) -> Void) async throws {
        var required = [Fujifilm.dateSyncState, Fujifilm.geotagRequest]
        required.append(usesRemote ? Fujifilm.shutter : Fujifilm.geotagPacket)
        let name = Data(client.name.utf8)

        switch firmware {
        case .secure:
            try await link.discover([Fujifilm.securePairingService, Fujifilm.stateService, Fujifilm.settingsService,
                                     Fujifilm.geotagService, Fujifilm.shutterService],
                                    required: required + [Fujifilm.secureStatus, Fujifilm.secureName])
            let status = try await link.read(Fujifilm.secureStatus, timeout: window)
            guard status.count == 4 else { throw CameraError.pairingRejected }
            progress(.registering)
            var ack = [UInt8](status)
            ack[3] = 0x20
            try await link.write(Data(ack), to: Fujifilm.secureStatus, timeout: window)
            try await link.write(name, to: Fujifilm.secureName)
        case .legacy(let token):
            try await link.discover([Fujifilm.legacyPairingService, Fujifilm.stateService, Fujifilm.settingsService,
                                     Fujifilm.geotagService, Fujifilm.shutterService],
                                    required: required + [Fujifilm.legacyToken, Fujifilm.legacyName])
            // The camera may ask for encryption on this first write.
            try await link.write(token, to: Fujifilm.legacyToken, timeout: window)
            progress(.registering)
            try await link.write(name, to: Fujifilm.legacyName)
        }

        // The notification set, in the official app's order. NOT1 and the
        // geotag request are mandatory; the rest only log.
        let mandatory: Set = [Fujifilm.dateSyncState, Fujifilm.geotagRequest]
        var subscriptions = [Fujifilm.apState, Fujifilm.transferState, Fujifilm.dateSyncState,
                             Fujifilm.geotagRequest]
        if case .legacy = firmware {
            subscriptions.append(Fujifilm.legacyIndication)
        } else {
            subscriptions += [Fujifilm.vitalState] + Fujifilm.settingsNotifications + [Fujifilm.locationSyncCycle]
        }
        for chr in subscriptions {
            guard await link.has(chr) else { continue }
            do {
                try await link.subscribe(chr, decode: { Fujifilm.decode($0, from: chr) })
            } catch where !mandatory.contains(chr) {
                continue
            }
        }

        if await link.has(Fujifilm.locationSyncCycle) {
            var cycle = Fujifilm.syncCycleSeconds.littleEndian
            try await link.write(Data(bytes: &cycle, count: 2), to: Fujifilm.locationSyncCycle)
        }
    }

    // MARK: Location (pull)

    public nonisolated var geotagRules: GeotagRules { GeotagRules() }

    public func startLocationLink() async throws -> LocationLinkMode {
        guard await link.has(Fujifilm.geotagPacket) else { throw CameraError.unsupported }
        locationActive = true
        return .pull
    }

    /// The camera keeps asking while its own location sync is on; xGRC simply
    /// stops answering.
    public func stopLocationLink() async {
        locationActive = false
    }

    public func updateLocation(_ fix: GeoFix, time: Date, zone: TimeZone) async throws {
        guard locationActive else { throw CameraError.unsupported }
        let stamp = Int64(time.timeIntervalSince1970.rounded(.down))
        if let lastStamp, stamp <= lastStamp { return }
        try await link.send(ShotWrite(Fujifilm.locationPacket(fix, time: time), to: Fujifilm.geotagPacket))
        lastStamp = stamp
    }

    // MARK: Buttons

    public func press(_ button: CameraButton) async throws -> PressOutcome {
        switch button {
        case .focus: try await send(ShotWrite(Fujifilm.Shutter.half, to: Fujifilm.shutter))
        case .shutter: try await send(ShotWrite(Fujifilm.Shutter.full, to: Fujifilm.shutter, firesShutter: true))
        case .movie: return .unsupported
        }
        return .sent
    }

    public func release(_ button: CameraButton) async throws {
        guard button != .movie else { return }
        try await send(ShotWrite(Fujifilm.Shutter.release, to: Fujifilm.shutter))
    }

    /// A 4-byte shutter value goes out as the camera's two writes, back to back.
    public func send(_ write: ShotWrite) async throws {
        guard write.characteristic == Fujifilm.shutter, write.data.count == 4 else {
            try await link.send(write)
            return
        }
        try await link.send([ShotWrite(Data(write.data.prefix(2)), to: Fujifilm.shutter),
                             ShotWrite(Data(write.data.suffix(2)), to: Fujifilm.shutter)])
    }
}

/// UTC calendar fields, shared by the packet builders.
func utcComponents(_ time: Date) -> DateComponents {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    return utc.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: time)
}
